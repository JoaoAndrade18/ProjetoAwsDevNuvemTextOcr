#!/usr/bin/env bash
# Deploy do worker (SQS Consumer) - Git Bash / Linux
# Uso:
#   bash scripts/deploy-worker.sh <WORKER_IP> <path_pem> [AWS_PROFILE_NAME] [AWS_REGION] [AWS_CREDENTIALS_PATH] [AWS_CONFIG_PATH]
# Exemplo:
#   bash scripts/deploy-worker.sh 3.93.48.170 ./infra/keys/labsuser.pem default us-east-1 "$HOME/.aws/credentials" "$HOME/.aws/config"

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "uso: $0 <WORKER_IP> <path_pem> [AWS_PROFILE_NAME] [AWS_REGION] [AWS_CREDENTIALS_PATH] [AWS_CONFIG_PATH]"
  exit 1
fi

WORKER_IP="$1"
PEM="$2"
AWS_PROFILE_NAME="${3:-default}"
AWS_REGION="${4:-us-east-1}"
AWS_CREDENTIALS_PATH="${5:-$HOME/.aws/credentials}"
AWS_CONFIG_PATH="${6:-$HOME/.aws/config}"

BASE="$(cd "$(dirname "$0")/.." && pwd)"

# ==============================================================================
# SEÇÃO MODIFICADA
# ==============================================================================
echo "==[0/9] Preflight remoto (pastas, pacotes, disco, swap)=="
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WORKER_IP}" 'bash -lc "
  set -euo pipefail
  
  echo "--- [Preflight] 0. Pastas ---"
  sudo mkdir -p /opt/ocr-aws/worker /opt/ocr-aws/backend
  sudo chown -R ec2-user:ec2-user /opt/ocr-aws

  echo "--- [Preflight] 1. Pacotes (Python, tar, libGL) ---"
  # Adicionado: mesa-libGL (para yum/dnf) e libgl1-mesa-glx (para apt)
  (sudo dnf -y install python3.11 python3.11-pip tar mesa-libGL || \
   sudo yum -y install python3 python3-pip tar mesa-libGL || \
   (sudo apt-get update -y && sudo apt-get install -y python3 python3-venv python3-pip tar libgl1-mesa-glx))

  echo "--- [Preflight] 2. Expansão de Disco (Idempotente) ---"
  # Se o volume foi aumentado na AWS, isso expande a partição e o filesystem.
  # É seguro rodar mesmo que não haja nada a expandir.
  sudo growpart /dev/nvme0n1 1
  sudo xfs_growfs -d /
  echo "Discos atuais:"
  df -hT /

  echo "--- [Preflight] 3. Criação de Swap 4GB (Idempotente) ---"
  # Só cria o /swapfile se ele não existir
  if [ -f /swapfile ]; then
    echo \"/swapfile de 4GB já existe, pulando criação.\"
  else
    echo \"Criando /swapfile de 4GB...\"
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    echo \"/swapfile criado.\"
  fi
  
  # Só ativa o swap se ele não estiver ativo
  if swapon -s | grep -q \"/swapfile\"; then
    echo \"Swap já está ativo.\"
  else
    echo \"Ativando swap...\"
    sudo swapon /swapfile
    echo \"Adicionando swap ao /etc/fstab para ser permanente...\"
    echo \"/swapfile none swap sw 0 0\" | sudo tee -a /etc/fstab
  fi
  
  echo \"Memória atual (com swap):\"
  free -h

  echo \"[preflight] ok\"
"'
# ==============================================================================
# FIM DA SEÇÃO MODIFICADA
# ==============================================================================

echo "==[1/9] Empacotar worker/ (sem .venv / __pycache__)=="
TMP_TGZ="$(mktemp).tgz"
tar -C "$BASE" -czf "$TMP_TGZ" \
  --exclude="worker/.venv" \
  --exclude="worker/**/__pycache__" \
  --exclude="worker/.git" \
  worker

echo "==[2/9] Enviar e extrair worker/=="
scp -o StrictHostKeyChecking=no -i "$PEM" "$TMP_TGZ" "ec2-user@${WORKER_IP}:/tmp/worker.tgz"
rm -f "$TMP_TGZ"
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WORKER_IP}" 'bash -lc "
  set -euo pipefail
  mkdir -p /opt/ocr-aws
  tar -xzf /tmp/worker.tgz -C /opt/ocr-aws && rm -f /tmp/worker.tgz
"'

echo "==[3/9] Enviar .env do worker=="
scp -o StrictHostKeyChecking=no -i "$PEM" "$BASE/worker/.env" "ec2-user@${WORKER_IP}:/opt/ocr-aws/worker/.env"

echo "==[4/9] Garantir código Django disponível (app/ + manage.py + requirements.txt)=="
TMP_TGZ2="$(mktemp).tgz"
tar -C "$BASE/backend" -czf "$TMP_TGZ2" app manage.py requirements.txt
scp -o StrictHostKeyChecking=no -i "$PEM" "$TMP_TGZ2" "ec2-user@${WORKER_IP}:/tmp/backend_bits.tgz"
rm -f "$TMP_TGZ2"
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WORKER_IP}" 'bash -lc "
  set -euo pipefail
  mkdir -p /opt/ocr-aws/backend
  tar -xzf /tmp/backend_bits.tgz -C /opt/ocr-aws/backend && rm -f /tmp/backend_bits.tgz
  ls -la /opt/ocr-aws/backend ; ls -la /opt/ocr-aws/backend/app || true
"'

echo "==[5/9] Venv + dependências do worker=="
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WORKER_IP}" 'bash -lc "
  set -euo pipefail
  cd /opt/ocr-aws/worker
  PY=\$(command -v python3.11 || command -v python3)
  \$PY -m venv .venv
  source .venv/bin/activate
  python -V; pip -V
  pip install -U pip
  pip install -r requirements.txt
  # driver postgres (caso o worker também escreva no RDS via Django/psycopg2)
  pip install psycopg2-binary==2.9.9
  echo [venv] ok
"'

echo "==[6/9] Publicar credenciais AWS do desktop para a EC2=="
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WORKER_IP}" 'bash -lc "
  set -euo pipefail
  mkdir -p /home/ec2-user/.aws
  chmod 700 /home/ec2-user/.aws
"'
if [ -f "$AWS_CREDENTIALS_PATH" ]; then
  scp -o StrictHostKeyChecking=no -i "$PEM" "$AWS_CREDENTIALS_PATH" "ec2-user@${WORKER_IP}:/home/ec2-user/.aws/credentials"
else
  echo "ATENÇÃO: $AWS_CREDENTIALS_PATH não encontrado; prossigo sem enviar 'credentials'."
fi
if [ -f "$AWS_CONFIG_PATH" ]; then
  scp -o StrictHostKeyChecking=no -i "$PEM" "$AWS_CONFIG_PATH" "ec2-user@${WORKER_IP}:/home/ec2-user/.aws/config"
fi
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WORKER_IP}" 'bash -lc "
  set -euo pipefail
  chown -R ec2-user:ec2-user /home/ec2-user/.aws
  chmod 600 /home/ec2-user/.aws/credentials 2>/dev/null || true
  chmod 600 /home/ec2-user/.aws/config 2>/dev/null || true
  echo [aws dir]; ls -la /home/ec2-user/.aws
"'

echo "==[7/9] Publicar systemd unit (com HOME e variáveis AWS) e iniciar=="
UNIT_FILE="$(mktemp)"
cat > "$UNIT_FILE" <<'EOF'
[Unit]
Description=OCR Worker (SQS Consumer)
After=network-online.target
Wants=network-online.target

[Service]
User=ec2-user
WorkingDirectory=/opt/ocr-aws/worker
EnvironmentFile=/opt/ocr-aws/worker/.env

# Para importar settings e modelos Django
Environment=DJANGO_SETTINGS_MODULE=app.settings
Environment=PYTHONPATH=/opt/ocr-aws/backend

# AWS via arquivos (~/.aws) — sem depender de IAM/IMDS
Environment=HOME=/home/ec2-user
Environment=AWS_SHARED_CREDENTIALS_FILE=/home/ec2-user/.aws/credentials
Environment=AWS_CONFIG_FILE=/home/ec2-user/.aws/config
Environment=AWS_PROFILE=__AWS_PROFILE__
Environment=AWS_DEFAULT_REGION=__AWS_REGION__
Environment=AWS_EC2_METADATA_DISABLED=true

ExecStart=/opt/ocr-aws/worker/.venv/bin/python -u /opt/ocr-aws/worker/main.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

# Substituir placeholders por valores reais
sed -e "s/__AWS_PROFILE__/${AWS_PROFILE_NAME}/g" \
    -e "s/__AWS_REGION__/${AWS_REGION}/g" \
    "$UNIT_FILE" > "${UNIT_FILE}.final"

scp -o StrictHostKeyChecking=no -i "$PEM" "${UNIT_FILE}.final" "ec2-user@${WORKER_IP}:/tmp/ocr-worker.service"
rm -f "$UNIT_FILE" "${UNIT_FILE}.final"

ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WORKER_IP}" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
sed -i 's/\r$//' /tmp/ocr-worker.service
mv /tmp/ocr-worker.service /etc/systemd/system/ocr-worker.service
systemctl daemon-reload
systemctl enable --now ocr-worker
sleep 1
echo "--- status (topo) ---"
/usr/bin/systemctl status --no-pager ocr-worker | /usr/bin/sed -n '1,40p' || true
echo "--- journal (últimas 80) ---"
/usr/bin/journalctl -u ocr-worker -n 80 --no-pager || true
REMOTE


echo "==[8/9] Verificação STS no mesmo ambiente do serviço=="
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WORKER_IP}" 'sudo bash -lc "
  set -euo pipefail
  export HOME=/home/ec2-user
  export AWS_SHARED_CREDENTIALS_FILE=/home/ec2-user/.aws/credentials
  export AWS_CONFIG_FILE=/home/ec2-user/.aws/config
  export AWS_EC2_METADATA_DISABLED=true
  /opt/ocr-aws/worker/.venv/bin/python -c \"import boto3, json;print(json.dumps(boto3.client(\"\"\"sts\"\"\").get_caller_identity(), indent=2))\"
"'

echo "==[9/9] (Opcional) Smoke-test do SQS a partir do .env do worker=="
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WORKER_IP}" 'bash -lc "
  set -euo pipefail
  cd /opt/ocr-aws/worker
  QURL=\$(grep -E ^SQS_QUEUE_URL= .env | cut -d=f2- || true)
  if [ -n \"\$QURL\" ]; then
    echo [sqs] testando receive_message em: \$QURL
    /opt/ocr-aws/worker/.venv/bin/python -c \"import os,boto3,json; q=os.environ.get(\"\"\"QURL\"\"\"); import sys; import os as _o; _o.environ[\"\"\"QURL\"\"\"]=q; s=boto3.client(\"\"\"sqs\"\"\"); print(json.dumps(s.receive_message(QueueUrl=q,MaxNumberOfMessages=1,WaitTimeSeconds=1,VisibilityTimeout=10), indent=2, default=str))\"
  else
    echo '[sqs] SQS_QUEUE_URL não encontrado em worker/.env – pulei o teste.'
  fi
"'