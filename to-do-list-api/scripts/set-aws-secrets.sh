#!/usr/bin/env bash
# Actualiza las credenciales temporales del Learner Lab en GitHub Secrets.
#
# Uso:
#   1. En Learner Lab: AWS Details -> AWS CLI -> Show, copia el bloque completo
#      (aws_access_key_id=..., aws_secret_access_key=..., aws_session_token=...)
#   2. Pegalo en un archivo, por ejemplo creds.txt (NO lo subas al repo)
#   3. ./scripts/set-aws-secrets.sh creds.txt
#
# Requiere gh CLI autenticado (gh auth login) y estar dentro del repo.
set -euo pipefail

FILE="${1:?Pasa la ruta del archivo con las credenciales}"

get() {
  grep -E "^$1" "$FILE" | head -1 | cut -d= -f2- | tr -d ' \r'
}

gh secret set AWS_ACCESS_KEY_ID     --body "$(get aws_access_key_id)"
gh secret set AWS_SECRET_ACCESS_KEY --body "$(get aws_secret_access_key)"
gh secret set AWS_SESSION_TOKEN     --body "$(get aws_session_token)"

echo "Listo: credenciales actualizadas en GitHub Secrets."
