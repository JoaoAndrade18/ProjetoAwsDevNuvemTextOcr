# Infraestrutura Terraform

## Criar, aplicar ou destruir infraestrutura

```bash
terraform destroy -auto-approve
terraform apply -auto-approve
terraform output
```
---
## Script de Configuração de Ambiente – `gen-env.ps1`

Este script define variáveis locais para facilitar o deploy manual via scripts Bash.  
Ele configura os IPs públicos das instâncias, o caminho da chave `.pem` e executa os comandos necessários para iniciar os serviços **Web (Backend)** e **Worker**.

```powershell
# Definir variáveis de ambiente
$WEB_IP=<IP_PUBLIC_WEB>
$PEM="/labsuser.pem"

# Deploy da aplicação Web (Backend)
bash scripts/deploy-web.sh "$WEB_IP" "$PEM"

# Deploy do Worker
WORKER_IP=<IP_PUBLIC_WORKER>
```

Abra a URL da aplicação em seu navegador: http://$WEB_IP

O backend e o frontend estão em execução e prontos para receber requisições.

-- Ec2-web: OK
-- DynamoDB: OK

Agora vamos subir o Worker:

#### Dica – Problemas de Espaço em Disco (EC2)

Vai ocorrer erro de **espaço em disco insuficiente** durante o deploy, siga os passos abaixo para corrigir:

1. Acesse o **Console AWS EC2**.  
2. Localize a **instância** que apresentou o problema: Worker.  
3. Vá até a aba **Armazenamento** ou **Volumes**.  
4. Clique no **ID do volume** associado à instância.  
5. No topo da tela, clique em **Ações → Modificar volume**.  
6. Aumente o tamanho conforme necessário (Minimo: 30GB).  
7. Aguarde uns segundos.

Depois, acesse a instância via SSH: `ssh -i $PEM ec2-user@<IP_PUBLIC_WORKER>` e execute os seguintes comandos para expandir o sistema de arquivos:

```bash
sudo growpart /dev/nvme0n1 1
sudo xfs_growfs -d /
df -hT
```

Depois adicione um swapfile:

```bash
sudo fallocate -l 4G /swapfile sudo chmod 600 /swapfile sudo mkswap /swapfile sudo swapon /swapfile echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Depois dê deploy no worker:

```bash
bash scripts/deploy-worker.sh "$WORKER_IP" "$PEM"
```

-- Ec2-worker: OK
-- RDS: OK
-- SQS: OK

A aplicação está pronta para receber novas imagens para processamento.