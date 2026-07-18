#!/usr/bin/env bash
# Signs one app bundle with a stable project-local identity when available.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 APP_PATH" >&2
  exit 2
fi

APP_PATH="$1"
[[ -d "$APP_PATH" ]] || { echo "error: app bundle not found: $APP_PATH" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="$ROOT_DIR/.local-signing"
KEYCHAIN="$LOCAL_DIR/agent-controller-signing.keychain-db"
PASSWORD_FILE="$LOCAL_DIR/keychain-password"
IDENTITY_NAME="AgentController Local TCC"
ORIGINAL_KEYCHAINS=()
SEARCH_LIST_CHANGED=0

restore_search_list() {
  if [[ "$SEARCH_LIST_CHANGED" -eq 1 && "${#ORIGINAL_KEYCHAINS[@]}" -gt 0 ]]; then
    /usr/bin/security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
  fi
}
trap restore_search_list EXIT HUP INT TERM

capture_search_list() {
  local line
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | /usr/bin/sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
    [[ -n "$line" ]] && ORIGINAL_KEYCHAINS[${#ORIGINAL_KEYCHAINS[@]}]="$line"
  done < <(/usr/bin/security list-keychains -d user)
  [[ "${#ORIGINAL_KEYCHAINS[@]}" -gt 0 ]] || {
    echo "error: could not read the user keychain search list" >&2
    exit 1
  }
}

local_identity_hash() {
  /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
    | /usr/bin/awk -v name="$IDENTITY_NAME" '$0 ~ "\\\"" name "\\\"" { print $2; exit }'
}

SIGNER="${SIGNING_IDENTITY:-}"
if [[ -n "$SIGNER" ]]; then
  echo "Signing with explicit SIGNING_IDENTITY."
elif [[ -f "$KEYCHAIN" && -s "$PASSWORD_FILE" ]]; then
  capture_search_list
  /usr/bin/security unlock-keychain -p "$(/bin/cat "$PASSWORD_FILE")" "$KEYCHAIN"
  /usr/bin/security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$KEYCHAIN"
  SEARCH_LIST_CHANGED=1

  SIGNER="$(local_identity_hash)"
  [[ -n "$SIGNER" ]] || {
    echo "error: project keychain has no usable $IDENTITY_NAME identity" >&2
    exit 1
  }
  echo "Signing with project-local identity: $SIGNER"
else
  SIGNER="-"
  echo "warning: no local signing identity found; using ad-hoc signing. TCC grants will not survive rebuilds." >&2
fi

# Do not use --deep while signing. This bundle has no nested code, and Apple
# recommends signing nested code explicitly rather than deep-signing it.
/usr/bin/codesign --force --sign "$SIGNER" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
