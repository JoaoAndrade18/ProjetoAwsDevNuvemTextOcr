#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Script para ajustar as permissões de uma chave PEM usada no SSH da AWS.
# Uso:
#   ./fix_pem.sh caminho/para/sua_chave.pem
#
# O Terraform ou AWS CLI exigem que o arquivo .pem tenha permissão 600,
# ou seja, apenas o dono pode ler ou escrever (nenhum outro usuário do sistema).
# Este script automatiza essa permissão.
# ------------------------------------------------------------------------------

# Valida se o caminho do arquivo foi de fato informado
if [ $# -lt 1 ]; then
  echo "uso: $0 <path_pem>"
  exit 1
fi

# Aplica a permissão correta ao arquivo PEM
chmod 600 "$1"

# Confirma que a permissão foi bem sucedida
echo "ok: permissão 600 aplicada em $1"
