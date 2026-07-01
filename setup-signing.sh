#!/bin/bash
# One-time: create a stable self-signed code-signing identity so macOS keeps
# Accessibility/Mic permission across rebuilds (ad-hoc signatures change every
# build and reset TCC permissions). Run this ONCE, then use ./build.sh.
set -e

IDENTITY="Kotha Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "$IDENTITY"; then
  echo "✓ Identity '$IDENTITY' already exists. Nothing to do."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

# Use the system LibreSSL (not Homebrew OpenSSL 3, whose PKCS12 MAC Apple rejects).
SSL=/usr/bin/openssl

echo "→ Generating self-signed code-signing certificate…"
"$SSL" req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null
P12PASS="kotha"
"$SSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout "pass:$P12PASS" 2>/dev/null

echo "→ Importing into your login keychain (allowing codesign to use it)…"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign

echo
echo "✓ Created code-signing identity '$IDENTITY'."
echo "  The FIRST build that signs with it may show a keychain prompt —"
echo "  click 'Always Allow'. After that, Accessibility/Mic permission will"
echo "  persist across rebuilds. Now run ./build.sh."
