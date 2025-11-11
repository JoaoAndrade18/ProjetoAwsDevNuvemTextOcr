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
from PIL import Image
import numpy as np

# -------------------------------------------------------------------------
# 🔧 Carregamento inicial de ambiente e configuração do Django
# -------------------------------------------------------------------------

# Carrega o arquivo .env local do worker (contém variáveis sensíveis)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))

# Permite importar o backend Django (para acessar modelos e ORM)
BACKEND_DIR = os.path.abspath(os.path.join(BASE_DIR, "..", "backend"))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

# Define o módulo de configuração padrão do Django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "app.settings")
import django
django.setup()

# -------------------------------------------------------------------------
# ⚙️ Configuração do PaddleOCR
# -------------------------------------------------------------------------
print("[WORKER] Configurando ENVs do Paddle...")

# Define variáveis de ambiente exigidas pelo PaddleOCR
# Essas variáveis evitam erros de inicialização em ambiente EC2 minimalista
os.environ.setdefault("FLAGS_use_mkldnn", "0")
os.environ.setdefault("PDX_HOME", "/home/ec2-user/.pdx")
os.environ.setdefault("PADDLEOCR_HOME", "/home/ec2-user/.paddleocr")

# Import do PaddleOCR deve ocorrer após configuração das ENVs
from paddleocr import PaddleOCR

# -------------------------------------------------------------------------
# ☁️ Integração com AWS e ORM
# -------------------------------------------------------------------------
import boto3
from django.conf import settings
from django.db import transaction
from app.jobs.models import Job, JobItem

# Cria sessão AWS para S3 e SQS, usando região do arquivo de configuração Django
session = boto3.session.Session(region_name=settings.AWS_REGION)
s3 = session.client("s3")
sqs = session.client("sqs")

# -------------------------------------------------------------------------
# 🧠 Inicialização global do OCR (feito uma única vez)
# -------------------------------------------------------------------------
print("[WORKER] Inicializando PaddleOCR (isso pode levar um tempo)...")
_OCR = PaddleOCR(
    use_doc_orientation_classify=False,
    use_doc_unwarping=False,
    use_textline_orientation=False
)
print("[WORKER] PaddleOCR pronto.")

def get_ocr():
    """Retorna a instância global e pré-inicializada do PaddleOCR."""
    global _OCR
    return _OCR

# -------------------------------------------------------------------------
# 🔍 Função principal de OCR (mock realista usando PaddleOCR)
# -------------------------------------------------------------------------
def mock_ocr(bytes_data: bytes) -> str:
    """
    Executa OCR sobre bytes de imagem e retorna o texto extraído.

    - Redimensiona a imagem caso exceda 640px de largura (para performance).
    - Usa o PaddleOCR já inicializado.
    - Retorna o texto detectado, concatenado por quebras de linha.

    Parâmetros:
        bytes_data: Conteúdo binário da imagem (obtido via S3.get_object).

    Retorna:
        String com o texto reconhecido (ou string vazia se não houver texto).
    """
    ocr = get_ocr() # Agora apenas retorna a instância pronta
    img = Image.open(io.BytesIO(bytes_data)).convert("RGB")

    MAX_WIDTH = 640
    width, height = img.size

    if width > MAX_WIDTH:
        try:
            # Calcula a nova altura mantendo a proporção
            new_height = int(MAX_WIDTH * (height / width))
            print(f"[RESIZE] Redimensionando de {width}x{height} para {MAX_WIDTH}x{new_height}")
            # Usa ANTIALIAS para qualidade
            img = img.resize((MAX_WIDTH, new_height), Image.Resampling.LANCZOS) 
        except Exception as e:
            print(f"[RESIZE_WARN] Falha ao redimensionar imagem: {e}")
            # Continua com a imagem original se falhar

    result = ocr.predict(np.array(img)) 
    
    texts = []
    if result and result[0]:
        for line in result[0]:
            if line and len(line) >= 2 and line[1]:
                texts.append(line[1][0])
    return "\n".join(texts).strip()

# -------------------------------------------------------------------------
# 🧩 Utilitário: marca job como concluído se todos os itens estiverem DONE
# -------------------------------------------------------------------------
def set_job_status_if_complete(job: Job):
    """Verifica se todos os itens do job foram processados com sucesso."""
    total = job.items.count()
    done = job.items.filter(status="DONE").count()
    if total > 0 and done == total and job.status != "DONE":
        job.status = "DONE"
        job.save(update_fields=["status"])
        print(f"[JOB_DONE] job={job.id} total={total}")

# -------------------------------------------------------------------------
# 📦 Processamento individual de mensagens da fila SQS
# -------------------------------------------------------------------------
def process_message(msg):
    """
    Processa uma mensagem da fila SQS (um item de OCR).

    Fluxo:
        1. Extrai job_id, item_id e caminho do S3.
        2. Baixa os bytes da imagem do S3.
        3. Atualiza o status do item para PROCESSING.
        4. Executa OCR e grava resultado no banco.
        5. Marca job como DONE se todos os itens forem concluídos.

    Em caso de falha:
        - Atualiza status para ERROR.
        - Registra mensagem de erro em `error_msg`.
    """
    body = json.loads(msg["Body"])
    job_id = body["job_id"]
    item_id = body["item_id"]
    bucket = body["s3_bucket"]
    key = body["s3_key"]

    print(f"[RECV] job={job_id} item={item_id} key={key}")

    # Baixa o arquivo da imagem do S3
    obj = s3.get_object(Bucket=bucket, Key=key)
    raw = obj["Body"].read()

    # Marca item como PROCESSING
    try:
        with transaction.atomic():
            it = JobItem.objects.select_for_update().get(id=item_id)
            it.status = "PROCESSING"
            it.save(update_fields=["status"])
    except JobItem.DoesNotExist:
        print(f"[WARN] item não encontrado no DB: {item_id}")
        return

    # Executa OCR e grava resultado
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
        err = f"{type(e).__name__}: {e}"
        with transaction.atomic():
            it = JobItem.objects.select_for_update().get(id=item_id)
            it.error_msg = err
            it.status = "ERROR"
            it.save(update_fields=["error_msg", "status"])
        print(f"[ERROR] job={job_id} item={item_id} {err}")
        traceback.print_exc()

# -------------------------------------------------------------------------
# 🚀 Loop principal do worker
# -------------------------------------------------------------------------
def main():
    """
    Loop principal responsável por consumir continuamente a fila SQS.

    - Faz long polling (20s) para reduzir custo e requisições ociosas.
    - Processa até 5 mensagens por ciclo.
    - Em caso de sucesso, remove a mensagem da fila.
    - Em falhas, mantém a mensagem para reprocessamento automático (retry da SQS).
    """
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

# -------------------------------------------------------------------------
# ▶️ Ponto de entrada do worker
# -------------------------------------------------------------------------
if __name__ == "__main__":
    """
    Inicializa o serviço worker.

    Este script deve ser executado como processo persistente em EC2,
    tipicamente gerenciado via systemd (ocr-worker.service).
    """
    main()
