#!/usr/bin/env bash
# Creates a project-local, self-signed identity for stable local TCC testing.
# This is intentionally not a distribution signing workflow.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="$ROOT_DIR/.local-signing"
KEYCHAIN="$LOCAL_DIR/agent-controller-signing.keychain-db"
PASSWORD_FILE="$LOCAL_DIR/keychain-password"
IDENTITY_NAME="AgentController Local TCC"
TMP_DIR=""
TMP_PREFIX="${TMPDIR:-/tmp}/agent-controller-signing."
ORIGINAL_KEYCHAINS=()

cleanup() {
  if [[ -n "$TMP_DIR" && "$TMP_DIR" == "$TMP_PREFIX"* && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

restore_search_list() {
  if [[ "${#ORIGINAL_KEYCHAINS[@]}" -gt 0 ]]; then
    /usr/bin/security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
  fi
}

finish() {
  cleanup
  restore_search_list
}
trap finish EXIT HUP INT TERM

fail() {
  echo "error: $*" >&2
  exit 1
}

keychain_password() {
  [[ -s "$PASSWORD_FILE" ]] || fail "missing local keychain password: $PASSWORD_FILE"
  /bin/cat "$PASSWORD_FILE"
}

identity_hash() {
  /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
    | /usr/bin/awk -v name="$IDENTITY_NAME" '$0 ~ "\\\"" name "\\\"" { print $2; exit }'
}

capture_search_list() {
  local line
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | /usr/bin/sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
    [[ -n "$line" ]] && ORIGINAL_KEYCHAINS[${#ORIGINAL_KEYCHAINS[@]}]="$line"
  done < <(/usr/bin/security list-keychains -d user)
  [[ "${#ORIGINAL_KEYCHAINS[@]}" -gt 0 ]] || fail "could not read the user keychain search list"
}

if [[ -e "$KEYCHAIN" || -e "$PASSWORD_FILE" ]]; then
  [[ -f "$KEYCHAIN" && -f "$PASSWORD_FILE" ]] \
    || fail "incomplete local signing state; inspect $LOCAL_DIR before recreating it"

  /usr/bin/security unlock-keychain -p "$(keychain_password)" "$KEYCHAIN"
  EXISTING_IDENTITY="$(identity_hash)"
  [[ -n "$EXISTING_IDENTITY" ]] \
    || fail "local keychain exists but has no usable $IDENTITY_NAME code-signing identity"
  echo "Local signing identity is ready: $EXISTING_IDENTITY"
  exit 0
fi

umask 077
/bin/mkdir -p "$LOCAL_DIR"
# `create-keychain` normally leaves the user search list untouched. Preserve
# and restore it anyway so this setup never leaves a project keychain behind.
capture_search_list
/usr/bin/openssl rand -hex -out "$PASSWORD_FILE" 32

TMP_DIR="$(/usr/bin/mktemp -d "${TMP_PREFIX}XXXXXX")"
PRIVATE_KEY="$TMP_DIR/private-key.pem"
CERTIFICATE="$TMP_DIR/certificate.pem"
P12_FILE="$TMP_DIR/identity.p12"
P12_PASSWORD="$(/usr/bin/openssl rand -hex 32)"

/usr/bin/openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
  -keyout "$PRIVATE_KEY" \
  -out "$CERTIFICATE" \
  -subj "/CN=$IDENTITY_NAME/OU=Local Development/O=AgentController" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

/usr/bin/openssl pkcs12 -export \
  -inkey "$PRIVATE_KEY" \
  -in "$CERTIFICATE" \
  -out "$P12_FILE" \
  -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

/usr/bin/security create-keychain -p "$(keychain_password)" "$KEYCHAIN"
/usr/bin/security set-keychain-settings -lut 21600 "$KEYCHAIN"
/usr/bin/security unlock-keychain -p "$(keychain_password)" "$KEYCHAIN"
/usr/bin/security import "$P12_FILE" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null
/usr/bin/security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$(keychain_password)" \
  "$KEYCHAIN" >/dev/null

# Trust only this self-signed root, only for code signing, and only inside the
# project keychain. No system trust record or global keychain search-list entry
# is created.
/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERTIFICATE"

CREATED_IDENTITY="$(identity_hash)"
[[ -n "$CREATED_IDENTITY" ]] || fail "created keychain but could not verify its code-signing identity"

echo "Created local signing identity: $CREATED_IDENTITY"
echo "Local state is stored only in .local-signing/ (gitignored)."
echo "For local development and TCC stability only; do not distribute this identity or its keychain."
