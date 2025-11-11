"""
Worker OCR – Processamento assíncrono de imagens via AWS SQS e S3.

Este módulo executa o papel de "trabalhador" (worker) na arquitetura distribuída do
projeto AWS OCR. Ele consome mensagens da fila SQS, realiza o download das imagens
referenciadas no S3, processa OCR (usando PaddleOCR), e grava o resultado no banco
de dados RDS via ORM do Django.

Fluxo geral:
1. Recebe mensagens da SQS com job_id, item_id e caminho S3.
2. Faz download da imagem.
3. Executa OCR.
4. Atualiza status e texto reconhecido no RDS.
5. Marca o job como concluído se todos os itens forem processados.

Executado continuamente em instância EC2 (t3.micro educacional), gerenciado via systemd.
"""

import io
import os, sys, json, time, traceback
from dotenv import load_dotenv

# ================================================================
# Configuração inicial do ambiente e carregamento do Django
# ================================================================

# Carrega as variáveis de ambiente do arquivo .env localizado no diretório do worker
BASE_DIR = os.path.dirname(os.path.abspath(_file_))
load_dotenv(os.path.join(BASE_DIR, ".env"))

# Adiciona o diretório do backend ao path, permitindo importar os modelos Django
BACKEND_DIR = os.path.abspath(os.path.join(BASE_DIR, "..", "backend"))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

# Configura o Django para usar as definições do projeto
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "app.settings")
import django
django.setup()

# ================================================================
# Inicialização do OCR (substituímos PaddleOCR por EasyOCR)
# ================================================================

import easyocr

# ================================================================
# Integração com AWS (S3 e SQS) e modelos do Django
# ================================================================

import boto3
from django.conf import settings
from django.db import transaction
from app.jobs.models import Job, JobItem

# Cria a sessão AWS com base na região definida nas configurações do Django
session = boto3.session.Session(region_name=settings.AWS_REGION)
s3 = session.client("s3")
sqs = session.client("sqs")

# Inicializa o modelo EasyOCR apenas uma vez (para evitar recarregar a cada mensagem)
print("[WORKER] Inicializando EasyOCR (isso pode levar um tempo)...")
_EASYOCR_MODEL = easyocr.Reader(['en'], gpu=False)
print("[WORKER] EasyOCR pronto.")


def get_easyocr_model():
    """Retorna a instância global do modelo EasyOCR já carregado."""
    global _EASYOCR_MODEL
    return _EASYOCR_MODEL

# ================================================================
# Função de OCR usando EasyOCR
# ================================================================

def mock_ocr(bytes_data: bytes) -> str:
    """
    Executa o OCR diretamente nos bytes da imagem usando EasyOCR.

    - Não utiliza PIL nem Numpy, o que reduz dependências.
    - O processamento é feito em CPU (gpu=False).
    - O retorno é o texto reconhecido, unido em um único parágrafo.
    """
    ocr = get_easyocr_model() 
    
    print(f"[INFO] Processando imagem com EasyOCR...")

    result = ocr.readtext(bytes_data, detail=0, paragraph=True)
    
    return " ".join(result).strip()

# ================================================================
# Controle de status de jobs
# ================================================================

def set_job_status_if_complete(job: Job):
    """
    Verifica se todos os itens de um job foram processados.
    Caso positivo, marca o job como concluído (status DONE).
    """
    total = job.items.count()
    done = job.items.filter(status="DONE").count()
    if total > 0 and done == total and job.status != "DONE":
        job.status = "DONE"
        job.save(update_fields=["status"])
        print(f"[JOB_DONE] job={job.id} total={total}")

# ================================================================
# Processamento de mensagens da fila SQS
# ================================================================

def process_message(msg):
    """
    Processa uma mensagem da fila SQS, que representa um item de OCR.

    Etapas:
    1. Lê a mensagem e extrai job_id, item_id e informações do S3.
    2. Faz o download da imagem no S3.
    3. Atualiza o item como PROCESSING no banco.
    4. Executa o OCR com EasyOCR.
    5. Atualiza o texto reconhecido e marca o item como DONE.
    6. Se todos os itens do job estiverem concluídos, marca o job como DONE.
    """
    body = json.loads(msg["Body"])
    job_id = body["job_id"]
    item_id = body["item_id"]
    bucket = body["s3_bucket"]
    key = body["s3_key"]

    print(f"[RECV] job={job_id} item={item_id} key={key}")

    # Faz o download do arquivo no S3
    obj = s3.get_object(Bucket=bucket, Key=key)
    raw = obj["Body"].read()

    # Marca o item como "PROCESSING"
    try:
        with transaction.atomic():
            it = JobItem.objects.select_for_update().get(id=item_id)
            it.status = "PROCESSING"
            it.save(update_fields=["status"])
    except JobItem.DoesNotExist:
        print(f"[WARN] item não encontrado no DB: {item_id}")
        return

    # Executa o OCR e atualiza o banco
    try:
        text = mock_ocr(raw)
        with transaction.atomic():
            it = JobItem.objects.select_for_update().get(id=item_id)
            it.ocr_text = text
            it.status = "DONE"
            it.save(update_fields=["ocr_text", "status"])
            # tenta marcar o job DONE se todos concluidos
            set_job_status_if_complete(it.job)
        print(f"[DONE] job={job_id} item={item_id} text='{text[:60]}'")
    except Exception as e:
        err = f"{type(e)._name_}: {e}"
        with transaction.atomic():
            it = JobItem.objects.select_for_update().get(id=item_id)
            it.error_msg = err
            it.status = "ERROR"
            it.save(update_fields=["error_msg", "status"])
        print(f"[ERROR] job={job_id} item={item_id} {err}")
        traceback.print_exc()

# ================================================================
# Loop principal do worker
# ================================================================

def main():
    """
    Loop principal que mantém o worker escutando a fila SQS.

    - Faz long polling (20s) para reduzir custo e requisições ociosas.
    - Processa até 5 mensagens por vez.
    - Remove da fila as mensagens processadas com sucesso.
    - Mantém mensagens com erro para reprocessamento automático.
    """
    queue_url = settings.SQS_QUEUE_URL
    assert queue_url, "SQS_QUEUE_URL vazio no .env"

    print(f"[WORKER] start queue={queue_url}")
    while True:
        resp = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=5,
            WaitTimeSeconds=20, 
            VisibilityTimeout=60
        )
        msgs = resp.get("Messages", [])
        if not msgs:
            # Nenhuma nova mensagem — aguarda um pouco
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

# ================================================================
# Ponto de entrada do script
# ================================================================

if _name_ == "_main_":
    """
    Inicia o serviço worker.

    Este script deve ser executado continuamente em uma instância EC2.
    Normalmente, ele é iniciado e mantido em execução via systemd (ocr-worker.service).
    """
    main()