#!/usr/bin/env bash
# setup_signing.sh — Run this ONCE before your first build.
#
# Creates a persistent self-signed code-signing certificate so that macOS
# remembers Contexto's Accessibility permission across every future rebuild.
# Without this, macOS treats each new build as a different app and revokes
# the permission every time.

set -e

CERT_NAME="Contexto Developer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo ""
echo "==========================================="
echo "  Contexto — One-time signing setup"
echo "==========================================="
echo ""

# ── Already done? ─────────────────────────────────────────────────────────────
if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
        | grep -q "\"$CERT_NAME\""; then
    echo "Signing certificate already exists — nothing to do."
    echo "You can now run:  ./build.sh && ./install.sh"
    exit 0
fi

echo "This runs once and takes about 10 seconds."
echo "You will be asked for your Mac login password once to trust the certificate."
echo ""

# ── Temp files ────────────────────────────────────────────────────────────────
CFG=$(mktemp /tmp/ctx_cfg_XXXX.cnf)
KEY=$(mktemp /tmp/ctx_key_XXXX.pem)
CRT=$(mktemp /tmp/ctx_crt_XXXX.pem)
P12=$(mktemp /tmp/ctx_p12_XXXX.p12)

cleanup() { rm -f "$CFG" "$KEY" "$CRT" "$P12"; }
trap cleanup EXIT

# ── Write OpenSSL config ──────────────────────────────────────────────────────
cat > "$CFG" << EOF
[req]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[dn]
CN = $CERT_NAME
[ext]
keyUsage         = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = CA:false
EOF

# ── Generate key + self-signed certificate ────────────────────────────────────
echo "Generating certificate..."
openssl req -x509 -newkey rsa:2048 \
    -keyout "$KEY" \
    -out    "$CRT" \
    -days   3650 \
    -nodes \
    -config "$CFG" 2>/dev/null

# ── Export as PKCS12 ──────────────────────────────────────────────────────────
# Try with -legacy first (required on macOS Ventura+ / OpenSSL 3.x)
if ! openssl pkcs12 -export -legacy \
        -out "$P12" -inkey "$KEY" -in "$CRT" \
        -passout pass: 2>/dev/null; then
    openssl pkcs12 -export \
        -out "$P12" -inkey "$KEY" -in "$CRT" \
        -passout pass: 2>/dev/null
fi

# ── Import into login keychain ────────────────────────────────────────────────
echo "Importing into keychain..."
security import "$P12" \
    -k "$KEYCHAIN" \
    -P "" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    2>/dev/null || true

# ── Trust the certificate for code signing ────────────────────────────────────
# This is the step that asks for your Mac password — it happens only once ever.
echo "Trusting certificate (you may be prompted for your Mac password)..."
security add-trusted-cert \
    -d \
    -r trustRoot \
    -k "$KEYCHAIN" \
    "$CRT"

# ── Allow codesign to use the key without prompting each build ────────────────
echo ""
echo "One more step: enter your Mac login password so codesign can"
echo "use this key automatically on every future build (no more popups)."
echo ""
printf "Mac login password: "
read -rs KPASS
echo ""

security set-key-partition-list \
    -S "apple-tool:,apple:,codesign:" \
    -s \
    -k "$KPASS" \
    "$KEYCHAIN" > /dev/null 2>&1 && echo "  Done." || \
    echo "  (If this failed, Keychain may ask once during the first build — click Always Allow.)"

echo ""
echo "==========================================="
echo "  Setup complete!"
echo "==========================================="
echo ""
echo "Next steps (do these once):"
echo "  1.  ./build.sh      <- compiles the app"
echo "  2.  ./install.sh    <- installs and launches it"
echo ""
echo "After that, Contexto lives in your menu bar."
echo "You never need to open Terminal again unless you change the code."
