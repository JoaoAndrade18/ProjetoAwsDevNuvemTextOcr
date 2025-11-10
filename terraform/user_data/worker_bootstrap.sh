#!/bin/bash
set -euxo pipefail
dnf update -y
dnf install -y python3.11 python3.11-pip git tmux
mkdir -p /opt/ocr-aws/worker
echo "BOOTSTRAP worker ok" > /opt/ocr-aws/BOOTSTRAP_WORKER_OK
