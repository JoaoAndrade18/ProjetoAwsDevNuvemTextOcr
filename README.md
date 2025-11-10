# ☁️ Projeto AWS OCR – Desenvolvimento de Software para Nuvem

Este projeto implementa uma **aplicação distribuída em nuvem (AWS)** que realiza **processamento de imagens com OCR (Optical Character Recognition)**, utilizando diversos serviços gerenciados para garantir escalabilidade, persistência e desacoplamento de componentes.

O sistema foi desenvolvido como parte do **Trabalho Prático da disciplina de Desenvolvimento de Software para Nuvem**, integrando **EC2, RDS, S3, DynamoDB, SQS e IAM**.

---

## 🧱 Arquitetura Geral

A aplicação é composta por três principais componentes executados em instâncias EC2:

- **Backend (Django + DRF)** → expõe uma API REST que gerencia jobs e interage com RDS, S3, DynamoDB e SQS.  
- **Worker (Python)** → consome mensagens da SQS, processa imagens (OCR) e grava resultados no RDS.  
- **Frontend (opcional)** → interface web para visualização dos jobs e seus resultados.

### 🧩 Serviços AWS Utilizados

| Serviço AWS | Função no Projeto |
|--------------|------------------|
| **EC2** | Hospeda o backend e o worker. |
| **RDS (MySQL)** | Armazena informações relacionais sobre jobs e itens. |
| **S3** | Armazena arquivos de imagem enviados para OCR. |
| **DynamoDB** | Armazena logs das ações (CRUD e processamento). |
| **SQS** | Fila de mensagens para comunicação assíncrona entre backend e worker. |
| **IAM** | Controle de acesso e autenticação das instâncias. |
| **VPC (default)** | Rede padrão para simplificar o provisionamento. |

---

## 🗃️ Modelo de Dados (RDS)

### **Tabela: jobs**

| Campo | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID (PK) | Identificador único do job |
| `name` | string | Nome do job |
| `created_at` | timestamp | Data de criação |
| `status` | enum | PENDING, PROCESSING, DONE, ERROR, EXPIRED |
| `sqs_retention_deadline` | timestamp | Tempo limite na fila (agora + 2 dias) |
| **Relacionamento:** | 1–N → job_items | |

### **Tabela: job_items**

| Campo | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID (PK) | Identificador único do item |
| `job_id` | UUID (FK → jobs.id) | Job ao qual pertence |
| `s3_key` | string | Caminho do arquivo no S3 (`jobs/{job_id}/{uuid}.jpg`) |
| `created_at` | timestamp | Data de criação |
| `status` | enum | PENDING, PROCESSING, DONE, ERROR |
| `ocr_text` | text | Texto reconhecido |
| `error_msg` | text | Mensagem de erro (nullable) |

---

## 📡 Exemplo de Mensagem na Fila (SQS)

```json
{
  "job_id": "<uuid>",
  "item_id": "<uuid>",
  "s3_bucket": "ocr-jobs-bucket",
  "s3_key": "jobs/<job_id>/<item_uuid>.jpg",
  "created_at": "<iso8601>"
}
```

## 🌐 Endpoints da API (Backend – Django REST Framework)

| Método | Endpoint | Descrição |
|:--------|:-----------|:-----------|
| **POST** `/api/jobs/` | Cria um novo job e envia N imagens para o S3; registra logs no DynamoDB; publica mensagens na SQS. |
| **GET** `/api/jobs/` | Lista paginada de jobs com resumo e contagem de itens. |
| **GET** `/api/jobs/{id}/` | Retorna os detalhes completos do job, incluindo status de cada item e texto OCR quando disponível. |
| **PATCH** `/api/jobs/{id}/` | Atualiza o nome do job e registra a ação no DynamoDB. |
| **DELETE** `/api/jobs/{id}/` | Remove itens do S3, registros do RDS e logs associados. |

---

## 📦 Estrutura de Armazenamento (S3)

Os arquivos de cada job são organizados por prefixo:

jobs/{job_id}/{item_id}.jpg


---

## ⚙️ Infraestrutura e Configurações

- **Instâncias EC2:** `t3.micro` (educacional)  
- **Banco de dados RDS:** `db.t3.micro`  
- **VPC:** rede padrão (`default`)  
- **Credenciais:** configuradas localmente em `~/.aws/credentials`  
- **Logs:** tanto o backend quanto o worker registram todas as ações (IDs, tempos, S3 keys, mensagens da SQS, etc.)

---

## 🔧 Comandos Úteis (Backend Django)

```bash
python manage.py makemigrations jobs
python manage.py migrate
python manage.py runserver 0.0.0.0:8000

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

scp -i ../infra/keys/labsuser.pem ../scripts/systemd/ocr-backend.service ec2-user@34.201.111.201:/tmp/
ssh -i ../infra/keys/labsuser.pem ec2-user@34.201.111.201 \
"sudo mv /tmp/ocr-backend.service /etc/systemd/system/ && \
 sudo systemctl daemon-reload && \
 sudo systemctl enable --now ocr-backend && \
 sudo systemctl status ocr-backend --no-pager"

ssh -i ../infra/keys/labsuser.pem ec2-user@54.227.192.9 \
"sudo mkdir -p /opt/ocr-aws/backend && sudo chown -R ec2-user:ec2-user /opt/ocr-aws"
```
## 🌍 Endereços de Instâncias

| Componente | IP Público |
|-------------|------------|
| **Backend (Web)** | `34.201.111.201` |
| **Worker** | `54.227.192.9` |

---

## 🧠 Observações Técnicas

- OCR inicial implementado como **mock (`OK_<hash>`)** para validação do pipeline.  
- Pode ser substituído futuramente por OCR real (ex: Tesseract ou AWS Textract).  
- **IAM Policies** restritas por conta educacional; credenciais configuradas manualmente.  
- **Logs detalhados** no backend e worker permitem rastrear o fluxo completo de processamento.

---

## 📚 Referências AWS

- [AWS EC2 – Getting Started](https://aws.amazon.com/pt/ec2/getting-started/)
- [AWS S3 – Documentação](https://aws.amazon.com/pt/s3/)
- [AWS RDS – Guia de Uso](https://aws.amazon.com/pt/rds/getting-started/)
- [AWS DynamoDB – Introdução](https://aws.amazon.com/pt/dynamodb/getting-started/)
- [AWS SQS – Documentação](https://aws.amazon.com/pt/sqs/)
- [AWS IAM – Conceitos](https://aws.amazon.com/pt/iam/)

---

## ✅ Requisitos Atendidos do Trabalho – Parte 01

| Requisito | Implementação | Descrição |
|------------|----------------|------------|
| **EC2** | ✅ | Duas instâncias: backend (API Django) e worker (consumo de fila SQS). |
| **RDS** | ✅ | Banco MySQL hospedado na AWS, armazenando jobs e itens. |
| **S3** | ✅ | Armazenamento das imagens enviadas para OCR. |
| **SQS** | ✅ | Fila de mensagens entre backend e worker. |
| **DynamoDB** | ✅ | Registro de logs de processamento e operações CRUD. |
| **IAM** | ✅ | Controle de permissões e autenticação entre serviços. |

---

✳️ **Observação final:**  
A arquitetura foi projetada para demonstrar **integração prática de múltiplos serviços AWS** dentro de um fluxo real de processamento distribuído.  
Cada componente (EC2, SQS, S3, RDS, DynamoDB) cumpre um papel definido e mostra o domínio dos conceitos de **desenvolvimento para nuvem** exigidos na disciplina.

---

## 👥 Equipe

- João Andrade  
- Joel Sousa  
