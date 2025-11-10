#!/bin/bash
set -euxo pipefail
dnf update -y
dnf install -y python3.11 python3.11-pip git tmux nginx
systemctl enable --now nginx || true

mkdir -p /opt/ocr-aws/backend /opt/ocr-aws/frontend
echo "BOOTSTRAP web ok" > /opt/ocr-aws/BOOTSTRAP_WEB_OK
