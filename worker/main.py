import io
import os, sys, json, time, traceback
from dotenv import load_dotenv

# --- MUDANÇA: Não precisamos mais de PIL ou Numpy aqui ---
# from PIL import Image
# import numpy as np

# carrega .env do worker
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))

# permite importar o backend (usa ORM do Django)
BACKEND_DIR = os.path.abspath(os.path.join(BASE_DIR, "..", "backend"))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "app.settings")
import django
django.setup()

# ==============================================================================
# MUDANÇA: Imports e ENVs
# ==============================================================================
# 1. Importa o EasyOCR
import easyocr

# 2. Removemos as ENVs do Paddle (PDX_HOME, etc.)

import boto3
from django.conf import settings
from django.db import transaction
from app.jobs.models import Job, JobItem

session = boto3.session.Session(region_name=settings.AWS_REGION)
s3 = session.client("s3")
sqs = session.client("sqs")

# ==============================================================================
# MUDANÇA: Inicializa o EasyOCR (globalmente, UMA VEZ)
# ==============================================================================
print("[WORKER] Inicializando EasyOCR (isso pode levar um tempo)...")
# Forçamos CPU (gpu=False) e carregamos o modelo de inglês ('en')
_EASYOCR_MODEL = easyocr.Reader(['en'], gpu=False)
print("[WORKER] EasyOCR pronto.")


def get_easyocr_model():
    """Retorna a instância global e pré-inicializada do EasyOCR."""
    global _EASYOCR_MODEL
    return _EASYOCR_MODEL

# ==============================================================================
# MUDANÇA: Função mock_ocr() agora usa EasyOCR
# ==============================================================================
def mock_ocr(bytes_data: bytes) -> str:
    """
    Roda o EasyOCR diretamente nos bytes da imagem.
    Sem resize, sem PIL, sem Numpy. Mais rápido e mais limpo.
    """
    ocr = get_easyocr_model() 
    
    print(f"[INFO] Processando imagem com EasyOCR...")

    # EasyOCR pode ler os bytes puros diretamente
    # detail=0 (só o texto) e paragraph=True (tenta juntar linhas)
    result = ocr.readtext(bytes_data, detail=0, paragraph=True)
    
    # O resultado já é uma lista de strings. Juntamos com espaço.
    return " ".join(result).strip()
# ==============================================================================


def set_job_status_if_complete(job: Job):
    # se todos itens do job estiverem DONE, marca o job como DONE
    total = job.items.count()
    done = job.items.filter(status="DONE").count()
    if total > 0 and done == total and job.status != "DONE":
        job.status = "DONE"
        job.save(update_fields=["status"])
        print(f"[JOB_DONE] job={job.id} total={total}")

def process_message(msg):
    body = json.loads(msg["Body"])
    job_id = body["job_id"]
    item_id = body["item_id"]
    bucket = body["s3_bucket"]
    key = body["s3_key"]

    print(f"[RECV] job={job_id} item={item_id} key={key}")

    # baixa bytes do S3
    obj = s3.get_object(Bucket=bucket, Key=key)
    raw = obj["Body"].read()

    # marca PROCESSING (idempotente)
    try:
        with transaction.atomic():
            it = JobItem.objects.select_for_update().get(id=item_id)
            it.status = "PROCESSING"
            it.save(update_fields=["status"])
    except JobItem.DoesNotExist:
        print(f"[WARN] item não encontrado no DB: {item_id}")
        return

    # OCR
    try:
        text = mock_ocr(raw) # Agora esta função usa EasyOCR
        with transaction.atomic():
            it = JobItem.objects.select_for_update().get(id=item_id)
            it.ocr_text = text
            it.status = "DONE"
            it.save(update_fields=["ocr_text", "status"])
            # tenta marcar o job DONE se todos concluidos
            set_job_status_if_complete(it.job)
        print(f"[DONE] job={job_id} item={item_id} text='{text[:60]}'")
    except Exception as e:
        err = f"{type(e).__name__}: {e}"
        with transaction.atomic():
            it = JobItem.objects.select_for_update().get(id=item_id)
            it.error_msg = err
            it.status = "ERROR"
            it.save(update_fields=["error_msg", "status"])
        print(f"[ERROR] job={job_id} item={item_id} {err}")
        traceback.print_exc()

def main():
    queue_url = settings.SQS_QUEUE_URL
    assert queue_url, "SQS_QUEUE_URL vazio no .env"

    print(f"[WORKER] start queue={queue_url}")
    while True:
        resp = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=5,
            WaitTimeSeconds=20,  # long polling
            VisibilityTimeout=60
        )
        msgs = resp.get("Messages", [])
        if not msgs:
            # pouca movimentação: dorme um tico
            time.sleep(2)
            continue

        for m in msgs:
            receipt = m["ReceiptHandle"]
            try:
                process_message(m)
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt)
                print(f"[ACK] deleted")
            except Exception as e:
                print(f"[FAIL] mantendo na fila: {e}")
                traceback.print_exc()

if __name__ == "__main__":
    main()