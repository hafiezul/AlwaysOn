#!/bin/bash
# Imports the release signing certificate into a throwaway keychain on a CI
# runner and exports SIGN_IDENTITY and SIGN_KEYCHAIN for Scripts/build-app.sh.
#
#   MACOS_SIGNING_CERT_P12           base64 of the .p12 from setup-release-signing.sh
#   MACOS_SIGNING_CERT_PASSWORD      its password
#   EXPECTED_SIGNING_CERT_SHA1       optional pin; the import fails if the
#                                    certificate in the secret has another SHA-1
#
# Delete the keychain afterwards with: security delete-keychain "$SIGN_KEYCHAIN"
set -euo pipefail

: "${MACOS_SIGNING_CERT_P12:?MACOS_SIGNING_CERT_P12 is not set}"
: "${MACOS_SIGNING_CERT_PASSWORD:?MACOS_SIGNING_CERT_PASSWORD is not set}"

WORK_DIR="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$WORK_DIR/alwayson-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
P12="$WORK_DIR/alwayson-signing.p12"

umask 077
printf '%s' "$MACOS_SIGNING_CERT_P12" | base64 --decode > "$P12"
trap 'rm -f "$P12"' EXIT

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -f pkcs12 -P "$MACOS_SIGNING_CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

# codesign looks identities up through the search list
EXISTING_KEYCHAINS=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line#\"}"
  line="${line%\"}"
  [[ -n "$line" ]] && EXISTING_KEYCHAINS+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN" ${EXISTING_KEYCHAINS[@]+"${EXISTING_KEYCHAINS[@]}"}

# A self-signed certificate isn't trusted, so skip -v (valid only) here;
# codesign signs with it all the same.
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/^ *[0-9]+\)/ { print $2; exit }')"
if [[ -z "$IDENTITY" ]]; then
  echo "No code signing identity found in the imported certificate." >&2
  security find-identity -p codesigning "$KEYCHAIN" >&2
  exit 1
fi

if [[ -n "${EXPECTED_SIGNING_CERT_SHA1:-}" ]]; then
  expected="$(printf '%s' "$EXPECTED_SIGNING_CERT_SHA1" | tr -d ': ' | tr '[:lower:]' '[:upper:]')"
  if [[ "$IDENTITY" != "$expected" ]]; then
    echo "Signing certificate $IDENTITY does not match the pinned $expected." >&2
    echo "Shipping a new certificate resets every user's Accessibility access." >&2
    exit 1
  fi
fi

echo "Signing identity: $IDENTITY"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "SIGN_IDENTITY=$IDENTITY"
    echo "SIGN_KEYCHAIN=$KEYCHAIN"
  } >> "$GITHUB_ENV"
fi
