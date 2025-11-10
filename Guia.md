terraform destroy -auto-approve

terraform apply -auto-approve
terraform output

gen-env.ps1

WEB_IP=54.235.9.7
PEM="infra/keys/labsuser.pem"
bash scripts/deploy-web.sh "$WEB_IP" "$PEM"

# subir o worker
WORKER_IP=3.83.237.26
bash scripts/deploy-worker.sh "$WORKER_IP" "$PEM"

-- Se der erro de espaco em disco, va a aws depois ec2, procure a instancia corretam, vai em disco depois clica no id, depois la em cima em acoes va em modificar.


sudo growpart /dev/nvme0n1 1
sudo xfs_growfs -d /
df -hT

sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab


sudo yum install -y mesa-libGL # precisa disso no worker

