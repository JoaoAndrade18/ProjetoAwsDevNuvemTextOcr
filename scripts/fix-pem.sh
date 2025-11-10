#!/usr/bin/env bash
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "uso: $0 <path_pem>"
  exit 1
fi
chmod 600 "$1"
echo "ok: permissão 600 aplicada em $1"
