#!/usr/bin/env bash
# Envia certificado, chave, perfis e a chave da API do App Store Connect para os
# segredos do GitHub Actions. Os arquivos nunca entram no repositório.
#
#   scripts/configurar-assinatura.sh [diretório]   (padrão: ~/.config/prumo/assinatura)
#
# Espera no diretório:
#   distribution.cer                       certificado Apple Distribution (DER)
#   prumo-distribution.key                 chave privada (PEM, PKCS#8 sem senha)
#   Prumo_app.mobileprovision              perfil Ad Hoc do app        (br.prumo.app)
#   Prumo_widget.mobileprovision           perfil Ad Hoc da extensão   (br.prumo.app.widget)
#   Prumo_app_connect.mobileprovision      perfil App Store do app
#   Prumo_widget_connect.mobileprovision   perfil App Store da extensão
#   AuthKey_<KEYID>.p8                     chave da API do App Store Connect
#   asc.env                                ASC_ISSUER_ID=<issuer id>
set -euo pipefail

DIR="${1:-$HOME/.config/prumo/assinatura}"
REPO="${REPO:-Dric0s/prumo}"
GRUPO="${PRUMO_APP_GROUP:-group.br.prumo.app}"

cer="$DIR/distribution.cer"
key="$DIR/prumo-distribution.key"
declare -A perfis=(
  [IOS_PROFILE_APP_BASE64]="$DIR/Prumo_app.mobileprovision"
  [IOS_PROFILE_WIDGET_BASE64]="$DIR/Prumo_widget.mobileprovision"
  [IOS_PROFILE_APP_STORE_BASE64]="$DIR/Prumo_app_connect.mobileprovision"
  [IOS_PROFILE_WIDGET_STORE_BASE64]="$DIR/Prumo_widget_connect.mobileprovision"
)

for f in "$cer" "$key" "${perfis[@]}" "$DIR/asc.env"; do
  [ -f "$f" ] || { echo "Arquivo ausente: $f" >&2; exit 1; }
done

shopt -s nullglob
p8s=("$DIR"/AuthKey_*.p8)
[ "${#p8s[@]}" -eq 1 ] || { echo "Esperava exatamente um AuthKey_*.p8 em $DIR" >&2; exit 1; }
p8="${p8s[0]}"
ASC_KEY_ID="$(basename "$p8" .p8)"; ASC_KEY_ID="${ASC_KEY_ID#AuthKey_}"
# shellcheck disable=SC1091
source "$DIR/asc.env"
[ -n "${ASC_ISSUER_ID:-}" ] || { echo "ASC_ISSUER_ID ausente em asc.env" >&2; exit 1; }

# A chave precisa corresponder ao certificado.
if [ "$(openssl x509 -inform der -in "$cer" -noout -pubkey | openssl sha256)" != \
     "$(openssl pkey -in "$key" -pubout | openssl sha256)" ]; then
  echo "A chave privada não corresponde ao certificado." >&2
  exit 1
fi

# Os perfis precisam carregar o App Group, senão a assinatura falha no CI.
for perfil in "${perfis[@]}"; do
  plist="$(openssl smime -inform der -verify -noverify -in "$perfil" 2>/dev/null || true)"
  if ! grep -q "$GRUPO" <<<"$plist"; then
    echo "$(basename "$perfil") não inclui o App Group $GRUPO." >&2
    exit 1
  fi
done

b64() { base64 < "$1" | tr -d '\n'; }

b64 "$cer" | gh secret set IOS_DIST_CERT_BASE64 --repo "$REPO"
b64 "$key" | gh secret set IOS_DIST_KEY_BASE64  --repo "$REPO"
for nome in "${!perfis[@]}"; do
  b64 "${perfis[$nome]}" | gh secret set "$nome" --repo "$REPO"
done
b64 "$p8" | gh secret set ASC_KEY_BASE64 --repo "$REPO"
printf '%s' "$ASC_KEY_ID"    | gh secret set ASC_KEY_ID    --repo "$REPO"
printf '%s' "$ASC_ISSUER_ID" | gh secret set ASC_ISSUER_ID --repo "$REPO"

echo "Segredos atualizados em $REPO (chave da API: $ASC_KEY_ID)."
