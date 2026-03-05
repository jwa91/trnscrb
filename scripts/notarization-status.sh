#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: notarization-status.sh [options]

Read-only notarization status checker for trnscrb releases.

Options:
  --version VERSION         Release version to inspect (default: VERSION file)
  --submission-id ID        Specific notary submission ID to inspect
  --profile NAME            notarytool keychain profile (default: notarytool)
  --json                    Print raw JSON instead of a human-readable summary
  --help                    Show this help

Examples:
  scripts/notarization-status.sh --version 0.1.1
  scripts/notarization-status.sh --submission-id 1e4e39c3-9080-47ac-a880-a3c8229e8776
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
SUBMISSION_ID=""
PROFILE="notarytool"
OUTPUT_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --submission-id)
      SUBMISSION_ID="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for command in python3 xcrun; do
  require_command "${command}"
done

resolve_submission_json() {
  if [[ -n "${SUBMISSION_ID}" ]]; then
    xcrun notarytool info "${SUBMISSION_ID}" \
      --keychain-profile "${PROFILE}" \
      --output-format json
    return
  fi

  local history_json
  history_json="$(xcrun notarytool history \
    --keychain-profile "${PROFILE}" \
    --output-format json)"

  VERSION="${VERSION}" python3 -c '
import json
import os
import sys

target_name = f"trnscrb-{os.environ['"'"'VERSION'"'"']}.dmg"
history = json.load(sys.stdin).get("history", [])

for item in history:
    if item.get("name") == target_name:
        print(json.dumps(item))
        raise SystemExit(0)

raise SystemExit(1)
' <<<"${history_json}"
}

if ! submission_json="$(resolve_submission_json)"; then
  echo "Could not find a notarization submission for trnscrb-${VERSION}.dmg" >&2
  exit 1
fi

if [[ "${OUTPUT_JSON}" == true ]]; then
  printf '%s\n' "${submission_json}"
  exit 0
fi

STATUS="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"${submission_json}")"
SUBMISSION_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"${submission_json}")"
CREATED_DATE="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["createdDate"])' <<<"${submission_json}")"
NAME="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' <<<"${submission_json}")"

echo "Submission ID: ${SUBMISSION_ID}"
echo "Created: ${CREATED_DATE}"
echo "Asset: ${NAME}"
echo "Status: ${STATUS}"

if [[ "${STATUS}" == "Accepted" ]]; then
  cat <<EOF

Next manual steps:
  1. xcrun stapler staple "${REPO_ROOT}/build/${NAME}"
  2. gh release upload "v${VERSION}" "${REPO_ROOT}/build/${NAME}" --clobber
  3. shasum -a 256 "${REPO_ROOT}/build/${NAME}"
  4. Update ${REPO_ROOT%/trnscrb}/homebrew-tap/Casks/trnscrb.rb:
     - replace sha256
     - remove the temporary postflight quarantine workaround
EOF
fi
