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