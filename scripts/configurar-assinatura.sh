#!/usr/bin/env bash
# Envia certificado, chave e perfis de provisionamento para os segredos do GitHub Actions.
# Os arquivos nunca entram no repositório.
#
#   scripts/configurar-assinatura.sh [diretório]   (padrão: ~/.config/prumo/assinatura)
#
# Espera no diretório:
#   distribution.cer               certificado Apple Distribution (DER)
#   prumo-distribution.key         chave privada (PEM, PKCS#8 sem senha)
#   Prumo_app.mobileprovision      perfil do app        (br.prumo.app)
#   Prumo_widget.mobileprovision   perfil da extensão   (br.prumo.app.widget)
set -euo pipefail

DIR="${1:-$HOME/.config/prumo/assinatura}"
REPO="${REPO:-Dric0s/prumo}"
GRUPO="${PRUMO_APP_GROUP:-group.br.prumo.app}"

cer="$DIR/distribution.cer"
key="$DIR/prumo-distribution.key"
app="$DIR/Prumo_app.mobileprovision"
widget="$DIR/Prumo_widget.mobileprovision"

for f in "$cer" "$key" "$app" "$widget"; do
  [ -f "$f" ] || { echo "Arquivo ausente: $f" >&2; exit 1; }
done

# A chave precisa corresponder ao certificado.
if [ "$(openssl x509 -inform der -in "$cer" -noout -pubkey | openssl sha256)" != \
     "$(openssl pkey -in "$key" -pubout | openssl sha256)" ]; then
  echo "A chave privada não corresponde ao certificado." >&2
  exit 1
fi

# Os perfis precisam carregar o App Group, senão a assinatura falha no CI.
for perfil in "$app" "$widget"; do
  plist="$(openssl smime -inform der -verify -noverify -in "$perfil" 2>/dev/null || true)"
  if ! grep -q "$GRUPO" <<<"$plist"; then
    echo "Aviso: $(basename "$perfil") não inclui o App Group $GRUPO." >&2
    echo "       Ative App Groups no identificador, associe o grupo e baixe o perfil de novo." >&2
    falta_grupo=1
  fi
done

b64() { base64 < "$1" | tr -d '\n'; }

b64 "$cer"    | gh secret set IOS_DIST_CERT_BASE64      --repo "$REPO"
b64 "$key"    | gh secret set IOS_DIST_KEY_BASE64       --repo "$REPO"
b64 "$app"    | gh secret set IOS_PROFILE_APP_BASE64    --repo "$REPO"
b64 "$widget" | gh secret set IOS_PROFILE_WIDGET_BASE64 --repo "$REPO"

echo "Segredos atualizados em $REPO."
if [ "${falta_grupo:-0}" = 1 ]; then
  echo "Rode este script de novo depois de baixar os perfis com o App Group." >&2
  exit 2
fi
