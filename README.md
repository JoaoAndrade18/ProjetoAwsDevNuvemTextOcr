# Modelo de dados (RDS)

## jobs
- id: UUID (PK)
- name: string
- created_at: timestamp
- status: enum — PENDING, PROCESSING, DONE, ERROR, EXPIRED
- sqs_retention_deadline: timestamp (agora + 2 dias)
- relacionamento: 1-N → job_items

## job_items
- id: UUID (PK)
- job_id: UUID (FK → jobs.id)
- s3_key: string (ex: `jobs/{job_id}/{uuid}.jpg`)
- created_at: timestamp
- status: enum — PENDING, PROCESSING, DONE, ERROR
- ocr_text: text (pode ser grande)
- error_msg: text (nullable)


{
  "job_id":"<uuid>",
  "item_id":"<uuid>",
  "s3_bucket":"ocr-jobs-bucket",
  "s3_key":"jobs/<job_id>/<item_uuid>.jpg",
  "created_at":"<iso8601>"
}

endpoints do backend (DRF)

POST /api/jobs/ multipart: { name, images[] } → cria job + N itens, sobe imagens no S3, loga no DynamoDB, enfileira N mensagens no SQS.

GET /api/jobs/ → lista paginada (id, name, status, created_at, total_itens, done_itens, expires_at).

GET /api/jobs/{id}/ → detalhes (contagem, itens, status, datas, cada ocr_text quando pronto).

PATCH /api/jobs/{id}/ body: { name } → renomeia (loga).

DELETE /api/jobs/{id}/ → apaga itens (S3), apaga linhas (RDS), marca deleted (ou remove), loga.



Um bucket S3 com prefixo por job: jobs/{job_id}/...

OCR: começamos com “mock OCR” (extrai “OK_<hash>”) para validar pipeline; depois plugar o seu OCR real.

IAM: como sua conta educacional é restrita, vamos priorizar credenciais estáticas configuradas nas EC2 (arquivo ~/.aws/credentials) e policies geradas só se possível.

VPC: usar default VPC para reduzir atrito.

RDS micro (db.t3.micro) com senha em .env (não versionar).

MUITOS logs: backend e worker imprimem tudo (ação, IDs, tempos, S3 key, SQS msgId, etc.).


python manage.py makemigrations jobs
python manage.py migrate 
dir .\dev.sqlite3 
python manage.py runserver


ssh -i ../infra/keys/labsuser.pem ec2-user@34.201.111.201 \
"printf '%s\n' \
'server {' \
'    listen 80 default_server;' \
'    server_name _;' \
'    location / {' \
'        proxy_pass http://127.0.0.1:8000;' \
'        proxy_set_header Host \$host;' \
'        proxy_set_header X-Real-IP \$remote_addr;' \
'    }' \
'}' \
| sudo tee /etc/nginx/conf.d/ocr.conf >/dev/null && \
sudo nginx -t && sudo systemctl restart nginx"



scp -i ../infra/keys/labsuser.pem ../scripts/systemd/ocr-backend.service ec2-user@34.201.111.201:/tmp/ocr-backend.service


ssh -i ../infra/keys/labsuser.pem ec2-user@34.201.111.201 \
"sudo sed -i 's/\r$//' /tmp/ocr-backend.service && \
 sudo mv /tmp/ocr-backend.service /etc/systemd/system/ocr-backend.service && \
 sudo systemctl daemon-reload && \
 sudo systemctl enable --now ocr-backend && \
 sudo systemctl status --no-pager ocr-backend | sed -n '1,50p'"



---------------------------- WORKER ------------------------------
ssh -o StrictHostKeyChecking=no -i "$PEM" ec2-user@"$WORKER_IP" \
  'sudo mkdir -p /opt/ocr-aws/backend && sudo chown -R ec2-user:ec2-user /opt/ocr-aws'

  



web_public_ip = "34.201.111.201"
worker_public_ip = "54.227.192.9"