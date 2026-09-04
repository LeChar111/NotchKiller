#!/bin/bash
set -euo pipefail

# Crée un certificat de signature auto-signé et durable pour NotchKiller.
#
# Pourquoi : une signature ad hoc (`codesign -s -`) change à chaque compilation.
# macOS classe les autorisations (fichiers, automatisation, accessibilité) sur
# l'identité de signature — une identité qui change à chaque build, ce sont des
# autorisations redemandées à chaque build. Un certificat stable les fait tenir.

NAME="NotchKiller Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | command grep -q "$NAME"; then
  echo "Identité déjà présente : $NAME"
  echo
  echo "Pour l'utiliser :  NK_SIGN_IDENTITY=\"$NAME\" ./build.sh"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $NAME

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CONF

echo "Génération du certificat…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" 2>/dev/null

openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout pass: -name "$NAME" 2>/dev/null

echo "Import dans le trousseau (macOS peut demander votre mot de passe)…"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "Déclaration du certificat comme fiable pour la signature…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

# Évite que macOS redemande l'accès à la clé privée à chaque signature.
security set-key-partition-list -S apple-tool:,apple: -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo
if security find-identity -v -p codesigning | command grep -q "$NAME"; then
  echo "Identité créée : $NAME"
  echo
  echo "Utilisation :"
  echo "  NK_SIGN_IDENTITY=\"$NAME\" ./build.sh"
  echo "  NK_SIGN_IDENTITY=\"$NAME\" ./install.sh"
  echo
  echo "Les autorisations accordées à NotchKiller tiendront alors d'une"
  echo "compilation à l'autre. Réinitialisez-les une dernière fois avec :"
  echo "  tccutil reset All com.flux.notchkiller"
else
  echo "Le certificat n'apparaît pas comme identité de signature."
  echo "Créez-le à la main : Trousseaux d'accès → Assistant de certification →"
  echo "Créer un certificat → type « Signature de code », nom « $NAME »."
  exit 1
fi
