# Projeto AWS OCR – Desenvolvimento de Software para Nuvem

Este projeto implementa uma **aplicação distribuída em nuvem (AWS)** que realiza **processamento de imagens com OCR (Optical Character Recognition)**, utilizando diversos serviços gerenciados para garantir persistência e desacoplamento de componentes.

O sistema foi desenvolvido como parte do **Trabalho Prático da disciplina de Desenvolvimento de Software para Nuvem**, integrando **EC2, RDS, S3, DynamoDB e SQS**.

---

## Arquitetura Geral

A aplicação é composta por três principais componentes executados em instâncias EC2:

- **Backend (Django)** → expõe uma API REST que gerencia jobs e interage com RDS, S3, DynamoDB e SQS.  
- **Worker (Python)** → consome mensagens da SQS, processa imagens (OCR) e grava resultados no RDS.  
- **Frontend (html + js + css)** → interface web para visualização dos jobs e seus resultados.

### Serviços AWS Utilizados

| Serviço AWS | Função no Projeto |
|--------------|------------------|
| **EC2** | Hospeda o backend e o worker. |
| **RDS (PostgreeSQL)** | Armazena informações relacionais sobre jobs e itens. |
| **S3** | Armazena arquivos de imagem enviados para OCR. |
| **DynamoDB** | Armazena logs das ações (CRUD e processamento). |
| **SQS** | Fila de mensagens para comunicação assíncrona entre backend e worker. |
| **VPC (default)** | Rede padrão para simplificar o provisionamento. |

---

## Modelo de Dados (RDS)

### **Tabela: job_items**

| Campo | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID  | Identificador único do item |
| `job_id` | UUID ( jobs.id) | Job ao qual pertence |
| `s3_key` | string | Caminho do arquivo no S3 (`jobs/{job_id}/{uuid}.jpg`) |
| `created_at` | timestamp | Data de criação |
| `status` | enum | PENDING, PROCESSING, DONE, ERROR |
| `ocr_text` | text | Texto reconhecido |
| `error_msg` | text | Mensagem de erro (nullable) |

---

## Exemplo de Mensagem na Fila (SQS)

```json
{
  "job_id": "<uuid>",
  "item_id": "<uuid>",
  "s3_bucket": "ocr-jobs-bucket",
  "s3_key": "jobs/<job_id>/<item_uuid>.jpg",
  "created_at": "<iso8601>"
}
```

## Endpoints da API (Backend – Django REST Framework)

| Método | Endpoint |
|:--------|:-----------|
| **POST** `/api/jobs/` | Cria um novo job e envia N imagens para o S3; registra logs no DynamoDB; publica mensagens na SQS. |
| **GET** `/api/jobs/` | Lista paginada de jobs com resumo e contagem de itens. |
| **GET** `/api/jobs/{id}/` | Retorna os detalhes completos do job, incluindo status de cada item e texto OCR quando disponível. |
| **DELETE** `/api/jobs/{id}/` | Remove itens do S3, registros do RDS e logs associados. |

---

## Estrutura de Armazenamento (S3)

Os arquivos de cada job são organizados por prefixo:

jobs/{job_id}/{item_id}.jpg


---

## Infraestrutura e Configurações

- **Instâncias EC2:** `t3.micro` (educacional)  
- **Banco de dados RDS:** `db.t3.micro`  
- **VPC:** rede padrão (`default`)  
- **Credenciais:** configuradas localmente em `~/.aws/credentials`  
- **Logs:** tanto o backend quanto o worker registram todas as ações (IDs, tempos, S3 keys, mensagens da SQS, etc.)

---

## Endereços de Instâncias

| Componente | IP Público |
|-------------|------------|
| **Backend (Web)** | `xxx.xxx.xxx.xxx` |
| **Worker** | `xxx.xxx.xxx.xxx` |

---

## Referências AWS

- [AWS EC2 – Getting Started](https://aws.amazon.com/pt/ec2/getting-started/)
- [AWS S3 – Documentação](https://aws.amazon.com/pt/s3/)
- [AWS RDS – Guia de Uso](https://aws.amazon.com/pt/rds/getting-started/)
- [AWS DynamoDB – Introdução](https://aws.amazon.com/pt/dynamodb/getting-started/)
- [AWS SQS – Documentação](https://aws.amazon.com/pt/sqs/)

---


**Observação final:**  
A arquitetura foi projetada para demonstrar **integração prática de múltiplos serviços AWS** dentro de um fluxo real de processamento distribuído.  
Cada componente (EC2, SQS, S3, RDS, DynamoDB) cumpre um papel definido e mostra o domínio dos conceitos de **desenvolvimento para nuvem** exigidos na disciplina.

---

## Observações

Não foi implementado o **IAM** para acesso aos serviços.
O usuário deverá configurar as credenciais de acesso no ~/.aws/credentials
E região em ~/.aws/config

-- Esses arquivos serão enviados para as instâncias, o que permitirá que elas acessem os serviços.

## Equipe

- João Andrade  
- Joel Sousa  
