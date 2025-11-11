#!/usr/bin/env bash

# Deploy do servidor WEB (Nginx + Backend e opcionalmente Frontend) em Amazon Linux 2023.
#
# O que este script faz:
# - Configura Nginx para servir o frontend e fazer proxy da API /health e /api para o backend (Gunicorn em 127.0.0.1:8000)
# - Envia o código do backend, cria virtualenv, instala dependências, roda migrações
# - Configura um serviço systemd para manter o backend rodando
# - Publica o frontend (caso exista build) ou um HTML simples como placeholder
#
# Uso:
#   ./deploy-web.sh <WEB_IP> <path_pem>

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "uso: $0 <WEB_IP> <path_pem>"
  exit 1
fi

WEB_IP="$1"
PEM="$2"

# Diretório raiz do projeto (onde estão o backend e, se existir, frontend)
BASE="$(cd "$(dirname "$0")/.." && pwd)"

# Valida presença mínima do backend antes de continuar
[ -f "$BASE/backend/manage.py" ] || { echo "backend/manage.py não encontrado"; exit 1; }
[ -f "$BASE/backend/requirements.txt" ] || { echo "backend/requirements.txt não encontrado"; exit 1; }
[ -f "$BASE/backend/.env" ] || { echo "backend/.env não encontrado"; exit 1; }

# Detecta build do frontend, se existir
FRONT_SRC=""
if [ -d "$BASE/frontend/dist" ]; then
  FRONT_SRC="$BASE/frontend/dist"
elif [ -d "$BASE/frontend/build" ]; then
  FRONT_SRC="$BASE/frontend/build"
elif [ -d "$BASE/frontend" ]; then
  # fallback: publica o conteúdo direto de /frontend
  FRONT_SRC="$BASE/frontend"
fi

# Garante permissão correta na chave SSH
chmod 600 "$PEM" || true

echo "==[0/9] Preflight remoto (pacotes, pastas, nginx)=="
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
sudo mkdir -p /opt/ocr-aws/backend /opt/ocr-aws/frontend
sudo chown -R ec2-user:ec2-user /opt/ocr-aws
(sudo dnf -y install python3.11 python3.11-pip nginx tar || \
 sudo yum -y install python3 python3-pip nginx tar || \
 (sudo apt-get update -y && sudo apt-get install -y python3 python3-venv python3-pip nginx tar))
sudo systemctl enable --now nginx || true
echo "[preflight] ok"
'

echo "==[1/9] Publicar conf do Nginx (/api e /health proxied)=="
NG_TMP="$(mktemp)"
cat > "$NG_TMP" <<'NG'
server {
    listen 80 default_server;
    server_name _;

    root /opt/ocr-aws/frontend;
    index index.html;

    client_max_body_size 2000m; # <= AQUI (ajuste conforme necessário)
    client_body_timeout 120s;

    # Proxy da API (preserva /api/...)
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }

    # Health check do backend (exposto em /health na raiz do Django)
    location /health {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Estáticos do front
    location ~* \.(?:js|css|svg|png|jpg|jpeg|gif|webp|ico|woff2?)$ {
        try_files $uri =404;
        access_log off;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    # SPA fallback
    location / {
        try_files $uri /index.html;
    }
}
NG

scp -o StrictHostKeyChecking=no -i "$PEM" "$NG_TMP" "ec2-user@${WEB_IP}:/home/ec2-user/ocr.conf"
rm -f "$NG_TMP"

ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
sudo rm -f /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/welcome.conf || true
sudo mv /home/ec2-user/ocr.conf /etc/nginx/conf.d/ocr.conf
sudo nginx -t
sudo systemctl restart nginx
echo "[nginx] conf aplicada e reiniciada"
'

echo "==[2/9] Publicar frontend (se existir) ou placeholder=="
if [ -n "${FRONT_SRC}" ] && [ -d "${FRONT_SRC}" ]; then
  TAR_FRONT="$(mktemp).tgz"
  tar -C "${FRONT_SRC}" -czf "$TAR_FRONT" .
  scp -o StrictHostKeyChecking=no -i "$PEM" "$TAR_FRONT" "ec2-user@${WEB_IP}:/home/ec2-user/front.tgz"
  rm -f "$TAR_FRONT"
  ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
    sudo mkdir -p /opt/ocr-aws/frontend
    sudo tar -xzf /home/ec2-user/front.tgz -C /opt/ocr-aws/frontend
    rm -f /home/ec2-user/front.tgz
    sudo chmod -R a+rX /opt/ocr-aws/frontend
    echo "[frontend] publicado"
  '
else
  echo "[frontend] build local não encontrado; publicando placeholder"
  ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
    sudo mkdir -p /opt/ocr-aws/frontend
    echo "<!doctype html><meta charset=utf-8><title>OCR App</title><h1>OCR App</h1><p>Frontend placeholder.</p>" | sudo tee /opt/ocr-aws/frontend/index.html >/dev/null
    sudo chmod -R a+rX /opt/ocr-aws/frontend
  '
fi

echo "==[3/9] Empacotar e enviar backend=="
TMP_TGZ="$(mktemp).tgz"
tar -C "$BASE" -czf "$TMP_TGZ" \
  --exclude="backend/.venv" \
  --exclude="backend/**/__pycache__" \
  --exclude="backend/dev.sqlite3" \
  --exclude="backend/.git" \
  backend
scp -o StrictHostKeyChecking=no -i "$PEM" "$TMP_TGZ" "ec2-user@${WEB_IP}:/home/ec2-user/backend.tgz"
rm -f "$TMP_TGZ"
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
  mkdir -p /opt/ocr-aws
  tar -xzf /home/ec2-user/backend.tgz -C /opt/ocr-aws
  rm -f /home/ec2-user/backend.tgz
  ls -la /opt/ocr-aws/backend | sed -n "1,80p"
'

echo "==[4/9] Publicar .env do backend=="
scp -o StrictHostKeyChecking=no -i "$PEM" "$BASE/backend/.env" "ec2-user@${WEB_IP}:/home/ec2-user/.env"
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
  sudo mv /home/ec2-user/.env /opt/ocr-aws/backend/.env
  sudo chown ec2-user:ec2-user /opt/ocr-aws/backend/.env
  ls -l /opt/ocr-aws/backend/.env
'

echo "==[5/9] Publicar credenciais AWS (se existirem localmente)=="
if [ -f "$HOME/.aws/credentials" ]; then
  scp -o StrictHostKeyChecking=no -i "$PEM" "$HOME/.aws/credentials" "ec2-user@${WEB_IP}:/home/ec2-user/credentials"
  ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
    mkdir -p /home/ec2-user/.aws
    mv -f /home/ec2-user/credentials /home/ec2-user/.aws/credentials
  '
fi
if [ -f "$HOME/.aws/config" ]; then
  scp -o StrictHostKeyChecking=no -i "$PEM" "$HOME/.aws/config" "ec2-user@${WEB_IP}:/home/ec2-user/config"
  ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
    mkdir -p /home/ec2-user/.aws
    mv -f /home/ec2-user/config /home/ec2-user/.aws/config
  '
fi
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
  [ -d /home/ec2-user/.aws ] && { chown -R ec2-user:ec2-user /home/ec2-user/.aws; chmod 600 /home/ec2-user/.aws/* || true; } || true
  echo "[aws] ~/.aws pronto (se fornecido)"
'

echo "==[6/9] Criar venv, instalar deps e migrar=="
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'bash -lc "
  set -euo pipefail
  cd /opt/ocr-aws/backend
  PY=\$(command -v python3.11 || command -v python3)
  \$PY -m venv .venv
  source .venv/bin/activate
  echo \"[python] \$(python -V); [pip] \$(pip -V)\"
  pip install -U pip
  pip install -r requirements.txt
  python manage.py makemigrations jobs
  python manage.py migrate
  echo \"[django] migrações ok\"
"'

echo "==[7/9] Publicar unit systemd do backend (com ambiente AWS)=="
UNIT_TMP="$(mktemp)"
cat > "$UNIT_TMP" <<'EOF'
[Unit]
Description=OCR Backend (Django/Gunicorn)
After=network-online.target
Wants=network-online.target

[Service]
User=ec2-user
WorkingDirectory=/opt/ocr-aws/backend
EnvironmentFile=/opt/ocr-aws/backend/.env

# Configuração de ambiente/AWS para o backend
Environment=HOME=/home/ec2-user
Environment=AWS_REGION=us-east-1
Environment=AWS_DEFAULT_REGION=us-east-1
Environment=AWS_SHARED_CREDENTIALS_FILE=/home/ec2-user/.aws/credentials
Environment=AWS_CONFIG_FILE=/home/ec2-user/.aws/config
Environment=AWS_PROFILE=default

# Gunicorn ouvindo apenas no loopback (127.0.0.1), acessível apenas pelo Nginx via proxy reverso.
ExecStart=/opt/ocr-aws/backend/.venv/bin/gunicorn app.wsgi:application \
  --bind 127.0.0.1:8000 --workers 2 --access-logfile - --error-logfile -

Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

scp -o StrictHostKeyChecking=no -i "$PEM" "$UNIT_TMP" "ec2-user@${WEB_IP}:/home/ec2-user/ocr-backend.service"
rm -f "$UNIT_TMP"

ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'set -euo pipefail
  sudo mv /home/ec2-user/ocr-backend.service /etc/systemd/system/ocr-backend.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now ocr-backend
  echo "--- status ocr-backend (topo) ---"
  systemctl status --no-pager ocr-backend | sed -n "1,40p" || true
  echo "--- últimos logs ---"
  journalctl -u ocr-backend -n 60 --no-pager || true
'

echo "==[8/9] Smoke tests remotos (localhost da EC2)=="
ssh -o StrictHostKeyChecking=no -i "$PEM" "ec2-user@${WEB_IP}" 'bash -lc "
  set -e
  echo \"[systemd env]\"
  systemctl show -p Environment ocr-backend
  echo \"[gunicorn /health]\"
  curl -sS -i http://127.0.0.1:8000/health | sed -n \"1,2p\"
  echo \"[nginx /health]\"
  curl -sS -i http://127.0.0.1/health | sed -n \"1,2p\"
"'

echo "==[9/9] Health público=="
set +e
curl -sS -i "http://${WEB_IP}/health" | sed -n '1,2p'
EC=$?
set -e
echo "[curl /health exit=$EC]"
echo "WEB pronto: http://${WEB_IP}/"
