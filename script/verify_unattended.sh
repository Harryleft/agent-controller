#!/usr/bin/env bash
# A bounded, privacy-minimal verification entry point.  It never generates
# GameController input, changes power assertions, or reads Codex content.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="com.harryleft.agent-controller.macos"
COLLECT_SECONDS=""
NO_RELAUNCH=false

usage() {
  cat <<'USAGE'
Usage: ./script/verify_unattended.sh [--no-relaunch] [--collect-logs [seconds]]

  --no-relaunch
      Run only swift test, `swift build --product AgentControllerMac`, and
      git diff --check. This mode never calls pkill, never creates, removes,
      or replaces dist/AgentControllerMac.app, and never starts a GUI.

Runs swift test, package launch/signature verification, and git diff --check.
With --collect-logs, starts a physical-controller evidence window after those
checks. The default is 30 seconds; the allowed range is 5...120 seconds.

The collector outputs only controller connection, bridge phase/gate, and
action-result records. It neither records Codex prompt/reply text nor injects
input, prevents system sleep, or removes any user data.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --collect-logs)
      COLLECT_SECONDS="30"
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        COLLECT_SECONDS="$2"
        shift
      fi
      ;;
    --no-relaunch)
      if [[ "$NO_RELAUNCH" == true ]]; then
        echo "--no-relaunch may be specified only once" >&2
        exit 2
      fi
      NO_RELAUNCH=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -n "$COLLECT_SECONDS" ]] && (( COLLECT_SECONDS < 5 || COLLECT_SECONDS > 120 )); then
  echo "--collect-logs duration must be between 5 and 120 seconds" >&2
  exit 2
fi

if [[ "$NO_RELAUNCH" == true && -n "$COLLECT_SECONDS" ]]; then
  echo "--no-relaunch cannot be combined with --collect-logs" >&2
  exit 2
fi

cd "$ROOT_DIR"

echo "==> swift test"
swift test

if [[ "$NO_RELAUNCH" == true ]]; then
  echo "==> SwiftPM executable build (non-interactive; no app relaunch)"
  swift build --product AgentControllerMac

  echo "==> whitespace validation"
  git diff --check

  echo "Non-interactive verification passed; no app bundle or GUI was touched."
  exit 0
fi

echo "==> app build/signature/launch verification"
./script/build_and_run.sh --verify

echo "==> whitespace validation"
git diff --check

if [[ -z "$COLLECT_SECONDS" ]]; then
  echo "Verification passed. For a bounded physical-controller evidence window:"
  echo "  ./script/verify_unattended.sh --collect-logs 30"
  exit 0
fi

echo "==> collecting privacy-minimal controller evidence for ${COLLECT_SECONDS}s"
echo "Use only physical controller actions during this window; no input is injected."

# Filter before persisting so the temporary evidence contains only the allowed
# operational fields. This intentionally excludes Controller's raw input log
# and all Codex UI/content categories.
EVIDENCE_FILE="$(mktemp "${TMPDIR:-/tmp}/agent-controller-evidence.XXXXXX")"
cleanup() {
  [[ -n "${STREAM_PID:-}" ]] && kill "$STREAM_PID" >/dev/null 2>&1 || true
  [[ -f "$EVIDENCE_FILE" ]] && rm -f "$EVIDENCE_FILE"
}
trap cleanup EXIT INT TERM

/usr/bin/log stream --info --style compact \
  --predicate "subsystem == '$BUNDLE_ID' AND (category == 'Controller' OR category == 'Bridge')" 2>/dev/null |
  /usr/bin/awk '
    / connected / || / disconnected$/ || / phase=/ || / permission postEvent=/ ||
    / action=.* result=/ || / dictation .* result=/ || / sidebar operation=.* result=/ { print }
  ' >"$EVIDENCE_FILE" &
STREAM_PID=$!

sleep "$COLLECT_SECONDS"
kill "$STREAM_PID" >/dev/null 2>&1 || true
wait "$STREAM_PID" 2>/dev/null || true
STREAM_PID=""

echo "==> evidence summary (connection/phase/gate/action result only)"
if [[ -s "$EVIDENCE_FILE" ]]; then
  /usr/bin/awk '
    / connected / { connected++ }
    / disconnected$/ { disconnected++ }
    / phase=/ { phase++ }
    / permission postEvent=/ { gate++ }
    / action=.* result=/ || /dictation .* result=/ || /sidebar operation=.* result=/ { action++ }
    { print }
    END {
      printf "summary connected=%d disconnected=%d phase=%d gate=%d actionResult=%d\\n", connected, disconnected, phase, gate, action
    }
  ' "$EVIDENCE_FILE"
else
  echo "summary connected=0 disconnected=0 phase=0 gate=0 actionResult=0"
  echo "No eligible records observed; this is not physical-controller proof."
fi
