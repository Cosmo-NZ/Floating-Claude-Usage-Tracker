#!/usr/bin/env bash
# One-time: create a local self-signed code-signing identity so rebuilds keep a
# stable code signature (Keychain items and login-item registration survive rebuilds).
set -euo pipefail

IDENTITY="ClaudeUsageTracker Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "Signing identity '$IDENTITY' already present."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cs.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = ClaudeUsageTracker Dev
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/cs.key" -out "$TMP/cs.crt" \
    -days 3650 -config "$TMP/cs.cnf" >/dev/null 2>&1

openssl pkcs12 -export -inkey "$TMP/cs.key" -in "$TMP/cs.crt" \
    -out "$TMP/cs.p12" -passout pass:cut -name "$IDENTITY" >/dev/null 2>&1

security import "$TMP/cs.p12" -k "$KEYCHAIN" -P cut -T /usr/bin/codesign -A >/dev/null 2>&1

echo "Created signing identity '$IDENTITY'."
security find-identity -v -p codesigning | grep "$IDENTITY" || true
