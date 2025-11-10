import hashlib
import io, uuid, imghdr
from typing import List
from django.db.models import Count, Q
from django.utils.timezone import make_aware
from django.conf import settings
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status, permissions
from .models import Job, JobItem
from .serializers import JobSerializer, JobDetailSerializer
from .aws_clients import upload_s3_bytes, enqueue_item, log_ddb
from .utils import retention_deadline_from_now

class JobsView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        qs = Job.objects.annotate(
            total_items=Count("items"),
            done_items=Count("items", filter=Q(items__status="DONE")),
        ).order_by("-created_at")
        data = JobSerializer(qs, many=True).data
        print(f"[LIST] {len(data)} jobs")
        return Response({"results": data})

    def post(self, request):
        name = request.data.get("name") or "untitled"
        files = request.FILES.getlist("images")
        if not files:
            return Response({"detail": "Envie ao menos uma imagem em 'images[]'."},
                            status=status.HTTP_400_BAD_REQUEST)

        job = Job.objects.create(name=name, status="PENDING")
        job.sqs_retention_deadline = make_aware(retention_deadline_from_now())
        job.save(update_fields=["sqs_retention_deadline"])

        print(f"[CREATE_JOB] id={job.id} name={job.name} files={len(files)} "
              f"deadline={job.sqs_retention_deadline}")

        created_items: List[JobItem] = []
        seen_hashes = set()  # <<< dedup deste POST por conteúdo

        for f in files:
            raw = f.read()

            h = hashlib.sha256(raw).hexdigest()
            if h in seen_hashes:
                print(f"[SKIP_DUP] mesmo conteúdo no mesmo POST: {f.name} sha256={h[:12]}...")
                continue
            seen_hashes.add(h)

            # tenta detectar tipo básico
            guess = imghdr.what(None, h=raw) or "jpeg"
            ext = "jpg" if guess in ("jpeg", "jpg") else guess
            item_id = uuid.uuid4()
            s3_key = f"jobs/{job.id}/{item_id}.{ext}"

            upload_s3_bytes(settings.S3_BUCKET, s3_key, raw, f.content_type or "image/jpeg")

            it = JobItem.objects.create(job=job, s3_key=s3_key, status="PENDING")
            created_items.append(it)

            msg = {
                "job_id": str(job.id),
                "item_id": str(it.id),
                "s3_bucket": settings.S3_BUCKET,
                "s3_key": s3_key,
                "created_at": job.created_at.isoformat(),
            }
            mid = enqueue_item(msg)
            print(f"[ENQUEUE] job={job.id} item={it.id} msgId={mid}")

        log_ddb(actor="backend", action="CREATE_JOB", pk=str(job.id), payload={
            "name": name, "n_items": len(created_items)
        })

        # retorna com contagens
        job.total_items = len(created_items)  # ad-hoc p/ serializer
        job.done_items = 0
        data = JobDetailSerializer(job).data
        return Response(data, status=status.HTTP_201_CREATED)

class JobDetailView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, job_id):
        try:
            job = Job.objects.annotate(
                total_items=Count("items"),
                done_items=Count("items", filter=Q(items__status="DONE")),
            ).get(id=job_id)
        except Job.DoesNotExist:
            return Response({"detail": "Job não encontrado."}, status=404)

        data = JobDetailSerializer(job).data
        print(f"[GET_JOB] {job_id}")
        return Response(data)

    def patch(self, request, job_id):
        try:
            job = Job.objects.get(id=job_id)
        except Job.DoesNotExist:
            return Response({"detail": "Job não encontrado."}, status=404)

        new_name = request.data.get("name")
        if not new_name:
            return Response({"detail": "Informe 'name'."}, status=400)

        old = job.name
        job.name = new_name
        job.save(update_fields=["name"])
        log_ddb(actor="backend", action="RENAME_JOB", pk=str(job.id), payload={
            "old": old, "new": new_name
        })
        print(f"[RENAME] {job_id} '{old}' -> '{new_name}'")
        return Response({"id": str(job.id), "name": job.name})

    def delete(self, request, job_id):
        from django.conf import settings
        import boto3

        try:
            job = Job.objects.get(id=job_id)
        except Job.DoesNotExist:
            return Response({"detail": "Job não encontrado."}, status=404)

        # apaga objetos S3 com prefixo jobs/<job_id>/
        session = boto3.session.Session(region_name=settings.AWS_REGION)
        s3 = session.client("s3")
        prefix = f"jobs/{job.id}/"
        print(f"[S3-DELETE] prefix={prefix}")

        # listar em páginas e deletar em lotes (até 1000 por chamada)
        to_delete = []
        token = None
        total = 0
        while True:
            kw = dict(Bucket=settings.S3_BUCKET, Prefix=prefix)
            if token:
                kw["ContinuationToken"] = token
            resp = s3.list_objects_v2(**kw)
            contents = resp.get("Contents", [])
            if not contents and not resp.get("IsTruncated"):
                break
            for obj in contents:
                to_delete.append({"Key": obj["Key"]})
                if len(to_delete) == 1000:
                    s3.delete_objects(Bucket=settings.S3_BUCKET, Delete={"Objects": to_delete})
                    total += len(to_delete)
                    print(f"[S3-DELETE] batch {len(to_delete)}")
                    to_delete = []
            if resp.get("IsTruncated"):
                token = resp.get("NextContinuationToken")
            else:
                break
        if to_delete:
            s3.delete_objects(Bucket=settings.S3_BUCKET, Delete={"Objects": to_delete})
            total += len(to_delete)
            print(f"[S3-DELETE] last batch {len(to_delete)}")

        n_items = job.items.count()
        job.delete()
        log_ddb(actor="backend", action="DELETE_JOB", pk=str(job_id), payload={"n_items": n_items, "s3_deleted": total})
        print(f"[DELETE] {job_id} rows={n_items+1} s3={total}")
        return Response(status=204)

