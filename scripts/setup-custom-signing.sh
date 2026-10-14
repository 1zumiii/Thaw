#!/usr/bin/env bash
# Reuses one local certificate across custom builds. Never silently rotates it.
set -euo pipefail
umask 077

SIGNING_DIR="$HOME/Library/Application Support/Thaw-Custom/Signing"
CERTIFICATE="$SIGNING_DIR/certificate.pem"
KEYCHAIN=$(security default-keychain -d user | tr -d '"' | sed 's/^ *//')
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

fingerprint() {
    openssl x509 -in "$1" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g'
}

# Recover the public certificate from the keychain if its on-disk copy was
# removed. Never create a different key just because that copy is missing.
if [[ ! -f "$CERTIFICATE" ]]; then
    RECOVERED=$(security find-certificate -c 'Thaw Custom Local Code Signing' -p "$KEYCHAIN" 2>/dev/null || true)
    if [[ -n "$RECOVERED" ]]; then
        printf '%s\n' "$RECOVERED" > "$CERTIFICATE"
    fi
fi
if [[ -f "$CERTIFICATE" ]]; then
    openssl x509 -in "$CERTIFICATE" -noout -checkend 0 > /dev/null
    IDENTITY=$(fingerprint "$CERTIFICATE")
    if ! security find-identity -p codesigning "$KEYCHAIN" | grep -Fq "$IDENTITY"; then
        echo "The saved signing certificate has no usable private key in $KEYCHAIN." >&2
        echo "Restore its keychain identity; creating a replacement would reset permissions." >&2
        exit 1
    fi
    printf '%s\n' "$IDENTITY"
    exit 0
fi

WORK=$(mktemp -d "$SIGNING_DIR/.setup.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
openssl req -x509 -newkey rsa:3072 -sha256 -days 7300 -noenc \
    -subj '/CN=Thaw Custom Local Code Signing/' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=critical,codeSigning' \
    -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2> "$WORK/openssl.log"

# This random password protects only the short-lived import bundle. The key
# is kept non-extractable in the login keychain, accessible to codesign only.
THAW_IMPORT_PASSWORD=$(openssl rand -hex 24)
export THAW_IMPORT_PASSWORD
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" \
    -in "$WORK/certificate.pem" -name 'Thaw Custom Local Code Signing' \
    -out "$WORK/identity.p12" -passout env:THAW_IMPORT_PASSWORD
security import "$WORK/identity.p12" -k "$KEYCHAIN" -f pkcs12 \
    -P "$THAW_IMPORT_PASSWORD" -x -T /usr/bin/codesign >&2
unset THAW_IMPORT_PASSWORD
cp "$WORK/certificate.pem" "$CERTIFICATE"
fingerprint "$CERTIFICATE"
