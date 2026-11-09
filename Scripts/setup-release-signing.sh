#!/bin/bash
# One-time release signing setup. Run on your Mac:
#
#   Scripts/setup-release-signing.sh [output-dir]
#
# It creates, or reuses when they already exist in output-dir:
#   1. A self-signed code signing certificate (20 years). Every release is signed
#      with it, so macOS keeps Accessibility access when AlwaysOn updates.
#   2. A Sparkle EdDSA key pair. Sparkle installs only updates signed with it.
#
# Then it can store both as GitHub Actions secrets and variables with `gh`.
#
# Keep output-dir backed up (a password manager works) and out of git. Losing
# the certificate means the next release resets every user's Accessibility
# access once; losing the EdDSA key means users must update by hand once.
set -euo pipefail

SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
CERT_NAME="AlwaysOn Release Signing"
SPARKLE_ACCOUNT="alwayson-release"
OPENSSL=/usr/bin/openssl
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Run this on macOS." >&2
  exit 1
fi

OUT="${1:-$HOME/AlwaysOn-release-signing}"
mkdir -p "$OUT"
chmod 700 "$OUT"
umask 077
cd "$OUT"

# MARK: Certificate

if [[ -f cert.p12 && -f cert.pem && -f cert-password.txt ]]; then
  echo "Reusing the certificate in $OUT"
else
  echo "Creating a self-signed code signing certificate in $OUT"
  cat > cert.cnf <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF
  "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 7300 \
    -config cert.cnf -keyout key.pem -out cert.pem
  "$OPENSSL" rand -hex 24 > cert-password.txt
  # SHA1-3DES keeps the .p12 readable by `security import` on every macOS version
  "$OPENSSL" pkcs12 -export -inkey key.pem -in cert.pem -name "$CERT_NAME" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    -passout file:cert-password.txt -out cert.p12
  rm -f key.pem cert.cnf
fi

CERT_SHA1="$("$OPENSSL" x509 -in cert.pem -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' | tr '[:lower:]' '[:upper:]')"
base64 -i cert.p12 > cert.p12.base64

# MARK: Sparkle keys

ed25519_openssl() {
  local candidate
  for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl "$(command -v openssl || true)"; do
    if [[ -x "$candidate" ]] && "$candidate" genpkey -algorithm ed25519 >/dev/null 2>&1; then
      echo "$candidate"
      return
    fi
  done
}

if [[ -f sparkle-private-key.txt && -f sparkle-public-key.txt ]]; then
  echo "Reusing the Sparkle keys in $OUT"
elif ED_OPENSSL="$(ed25519_openssl)" && [[ -n "$ED_OPENSSL" ]]; then
  # Keychain-free, so this also works over SSH. Sparkle's key files hold the
  # raw 32-byte seed and public key, base64 encoded: the last 32 bytes of the
  # PKCS#8 and SubjectPublicKeyInfo DER encodings.
  echo "Creating the Sparkle EdDSA key pair with $ED_OPENSSL"
  "$ED_OPENSSL" genpkey -algorithm ed25519 -out sparkle-key.pem
  "$ED_OPENSSL" pkey -in sparkle-key.pem -outform DER | tail -c 32 | base64 > sparkle-private-key.txt
  "$ED_OPENSSL" pkey -in sparkle-key.pem -pubout -outform DER | tail -c 32 | base64 > sparkle-public-key.txt
  rm -f sparkle-key.pem
else
  TOOLS="$(mktemp -d)"
  trap 'rm -rf "$TOOLS"' EXIT
  ARCHIVE="$TOOLS/Sparkle.tar.xz"
  echo "Downloading Sparkle $SPARKLE_VERSION tools"
  curl -fsSL -o "$ARCHIVE" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_SHA256  $ARCHIVE" | shasum -a 256 -c - >/dev/null
  tar -xJf "$ARCHIVE" -C "$TOOLS" ./bin/generate_keys

  # Stores the key in your login keychain too (account: alwayson-release), or
  # reuses the one already there
  "$TOOLS/bin/generate_keys" --account "$SPARKLE_ACCOUNT" >/dev/null
  rm -f sparkle-private-key.txt
  "$TOOLS/bin/generate_keys" --account "$SPARKLE_ACCOUNT" -x sparkle-private-key.txt
  "$TOOLS/bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p > sparkle-public-key.txt
fi

SPARKLE_PUBLIC_KEY="$(tr -d '[:space:]' < sparkle-public-key.txt)"

cat <<EOF

Release signing material is in $OUT
  Certificate SHA-1:   $CERT_SHA1
  Sparkle public key:  $SPARKLE_PUBLIC_KEY

GitHub Actions configuration (Settings > Secrets and variables > Actions):
  secret    MACOS_SIGNING_CERT_P12        contents of cert.p12.base64
  secret    MACOS_SIGNING_CERT_PASSWORD   contents of cert-password.txt
  secret    SPARKLE_ED_PRIVATE_KEY        contents of sparkle-private-key.txt
  variable  SPARKLE_PUBLIC_ED_KEY         $SPARKLE_PUBLIC_KEY
  variable  SIGNING_CERT_SHA1             $CERT_SHA1

EOF

ask() {
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" == [yY]* ]]
}

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  REPO_ARGS=()
  if [[ -n "${GH_REPO:-}" ]]; then
    REPO_ARGS=(--repo "$GH_REPO")
  fi
  REPO_NAME="${GH_REPO:-$(cd "$SCRIPT_DIR" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "the current repository")}"
  if ask "Store these in $REPO_NAME with gh now?"; then
    (
      cd "$SCRIPT_DIR"
      gh secret set MACOS_SIGNING_CERT_P12 ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} < "$OUT/cert.p12.base64"
      gh secret set MACOS_SIGNING_CERT_PASSWORD ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} < "$OUT/cert-password.txt"
      gh secret set SPARKLE_ED_PRIVATE_KEY ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} < "$OUT/sparkle-private-key.txt"
      gh variable set SPARKLE_PUBLIC_ED_KEY ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --body "$SPARKLE_PUBLIC_KEY"
      gh variable set SIGNING_CERT_SHA1 ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --body "$CERT_SHA1"
    )
    echo "Stored."
  fi
else
  echo "Install and log in to the GitHub CLI (gh) to store these automatically, or add them by hand."
fi

if ! security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_SHA1"; then
  if ask "Import the certificate into your login keychain to sign local builds with it?"; then
    security import "$OUT/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
      -f pkcs12 -P "$(cat "$OUT/cert-password.txt")" -T /usr/bin/codesign
    echo "Sign local builds with: SIGN_IDENTITY=$CERT_SHA1 SPARKLE_PUBLIC_ED_KEY=$SPARKLE_PUBLIC_KEY Scripts/build-app.sh"
  fi
fi
