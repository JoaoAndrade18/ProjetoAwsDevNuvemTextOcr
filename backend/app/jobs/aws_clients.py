import os, time, json, uuid
import boto3
from django.conf import settings

_session = boto3.session.Session(region_name=settings.AWS_REGION)
s3 = _session.client("s3")
sqs = _session.client("sqs")
dynamodb = _session.resource("dynamodb")
ddb_table = dynamodb.Table(settings.DDB_TABLE_LOGS)

def log_ddb(actor: str, action: str, pk: str, payload: dict):
    ts = int(time.time() * 1000)
    item = {
        "pk": f"job#{pk}",
        "sk": f"ts#{ts}",
        "actor": actor,
        "action": action,
        "payload": json.dumps(payload),
    }
    print(f"[DDB] put_item {item}")
    ddb_table.put_item(Item=item)

def upload_s3_bytes(bucket: str, key: str, data: bytes, content_type: str):
    print(f"[S3] put_object bucket={bucket} key={key} size={len(data)}")
    s3.put_object(Bucket=bucket, Key=key, Body=data, ContentType=content_type)

def enqueue_item(message: dict):
    body = json.dumps(message)
    resp = sqs.send_message(QueueUrl=settings.SQS_QUEUE_URL, MessageBody=body)
    print(f"[SQS] send_message MessageId={resp.get('MessageId')} BodyLen={len(body)}")
    return resp.get("MessageId")
