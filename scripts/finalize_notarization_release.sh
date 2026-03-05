#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: finalize_notarization_release.sh [options]

Checks the notarization status for a trnscrb DMG. If Apple has accepted the
submission, the script staples the DMG, replaces the GitHub release asset,
updates the Homebrew cask SHA, removes the temporary quarantine workaround,
and commits/pushes the tap repo if requested.

Options:
  --version VERSION         Release version to finalize (default: VERSION file)
  --submission-id ID        Specific notary submission ID to inspect
  --release-tag TAG         GitHub release tag (default: vVERSION)
  --dmg PATH                Path to the DMG (default: build/trnscrb-VERSION.dmg)
  --tap-repo PATH           Path to the local homebrew-tap repo
  --profile NAME            notarytool keychain profile (default: notarytool)
  --commit                  Commit the tap repo changes when finalized
  --push                    Push the tap repo changes after committing
  --help                    Show this help

Examples:
  scripts/finalize_notarization_release.sh --version 0.1.1
  scripts/finalize_notarization_release.sh --submission-id <id> --version 0.1.1 --commit --push
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
DEFAULT_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"
DEFAULT_TAP_REPO="$(cd "${REPO_ROOT}/.." && pwd)/homebrew-tap"

VERSION="${DEFAULT_VERSION}"
SUBMISSION_ID=""
PROFILE="notarytool"
RELEASE_TAG=""
DMG_PATH=""
TAP_REPO="${DEFAULT_TAP_REPO}"
COMMIT_CHANGES=false
PUSH_CHANGES=false

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
    --release-tag)
      RELEASE_TAG="$2"
      shift 2
      ;;
    --dmg)
      DMG_PATH="$2"
      shift 2
      ;;
    --tap-repo)
      TAP_REPO="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --commit)
      COMMIT_CHANGES=true
      shift
      ;;
    --push)
      PUSH_CHANGES=true
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

if [[ "${PUSH_CHANGES}" == true ]]; then
  COMMIT_CHANGES=true
fi

if [[ -z "${RELEASE_TAG}" ]]; then
  RELEASE_TAG="v${VERSION}"
fi

if [[ -z "${DMG_PATH}" ]]; then
  DMG_PATH="${REPO_ROOT}/build/trnscrb-${VERSION}.dmg"
fi

for command in gh git python3 shasum xcrun; do
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

STATUS="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"${submission_json}")"
SUBMISSION_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"${submission_json}")"
CREATED_DATE="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["createdDate"])' <<<"${submission_json}")"

echo "Submission ${SUBMISSION_ID} (${CREATED_DATE}) status: ${STATUS}"

if [[ "${STATUS}" != "Accepted" ]]; then
  echo "No release finalization needed yet."
  exit 0
fi

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "Accepted notarization found, but DMG is missing: ${DMG_PATH}" >&2
  exit 1
fi

if [[ ! -f "${TAP_REPO}/Casks/trnscrb.rb" ]]; then
  echo "Could not find cask file at ${TAP_REPO}/Casks/trnscrb.rb" >&2
  exit 1
fi

if [[ -n "$(git -C "${TAP_REPO}" status --porcelain)" ]]; then
  echo "Tap repo is dirty: ${TAP_REPO}" >&2
  echo "Commit or stash those changes before finalizing notarization." >&2
  exit 1
fi

echo "Stapling ${DMG_PATH}"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

echo "Replacing GitHub release asset for ${RELEASE_TAG}"
gh release upload "${RELEASE_TAG}" "${DMG_PATH}" --clobber

SHA256="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
CASK_PATH="${TAP_REPO}/Casks/trnscrb.rb"

python3 - "${CASK_PATH}" "${SHA256}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
sha = sys.argv[2]
text = path.read_text()

text, replacements = re.subn(
    r'(^\s*sha256\s+")([^"]+)(")',
    rf'\g<1>{sha}\3',
    text,
    flags=re.MULTILINE,
)
if replacements != 1:
    raise SystemExit("Expected to replace exactly one sha256 line in the cask.")

lines = text.splitlines()
out = []
i = 0
removed_postflight = False
while i < len(lines):
    if lines[i].strip() == "postflight do":
      removed_postflight = True
      while out and out[-1].startswith("  #"):
          out.pop()
      i += 1
      while i < len(lines) and lines[i].strip() != "end":
          i += 1
      if i == len(lines):
          raise SystemExit("Found postflight block without a matching end.")
      i += 1
      continue
    out.append(lines[i])
    i += 1

updated = "\n".join(out).rstrip() + "\n"
path.write_text(updated)

print("removed_postflight=" + ("yes" if removed_postflight else "no"))
PY

echo "Updated ${CASK_PATH} with sha256 ${SHA256}"

if [[ -z "$(git -C "${TAP_REPO}" status --porcelain)" ]]; then
  echo "Tap repo already reflected the finalized release."
  exit 0
fi

if [[ "${COMMIT_CHANGES}" == true ]]; then
  git -C "${TAP_REPO}" add Casks/trnscrb.rb
  git -C "${TAP_REPO}" commit -m "Finalize notarization for trnscrb ${VERSION}"
  if [[ "${PUSH_CHANGES}" == true ]]; then
    git -C "${TAP_REPO}" push origin main
  fi
else
  echo "Tap repo updated locally. Re-run with --commit --push to publish it."
fi
