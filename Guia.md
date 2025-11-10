# 🧱 Infraestrutura Terraform

## ⚙️ Criar, aplicar ou destruir infraestrutura

```bash
terraform destroy -auto-approve
terraform apply -auto-approve
terraform output
```
---
## ⚙️ Script de Configuração de Ambiente – `gen-env.ps1`

Este script define variáveis locais para facilitar o deploy manual via scripts Bash.  
Ele configura os IPs públicos das instâncias, o caminho da chave `.pem` e executa os comandos necessários para iniciar os serviços **Web (Backend)** e **Worker**.

```powershell
# Definir variáveis de ambiente
$WEB_IP=54.235.9.7
$PEM="infra/keys/labsuser.pem"

# Deploy da aplicação Web (Backend)
bash scripts/deploy-web.sh "$WEB_IP" "$PEM"

# Deploy do Worker
WORKER_IP=3.83.237.26
bash scripts/deploy-worker.sh "$WORKER_IP" "$PEM"
```

#### ⚠️ Dica – Problemas de Espaço em Disco (EC2)

Caso ocorra erro de **espaço em disco insuficiente** durante o deploy, siga os passos abaixo para corrigir:

1. Acesse o **Console AWS EC2**.  
2. Localize a **instância** que apresentou o problema.  
3. Vá até a aba **Armazenamento** ou **Volumes**.  
4. Clique no **ID do volume** associado à instância.  
5. No topo da tela, clique em **Ações → Modificar volume**.  
6. Aumente o tamanho conforme necessário (por exemplo, de 8 GB para 16 GB).  
7. Aguarde o status do volume atualizar para “available” antes de prosseguir.

Depois, acesse a instância via SSH e execute os seguintes comandos para expandir o sistema de arquivos:

```bash
sudo growpart /dev/nvme0n1 1
sudo xfs_growfs -d /
df -hT
```