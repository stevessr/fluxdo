#!/usr/bin/env bash

set -euo pipefail

readonly BASE_SHA="2182bed86b8e6d319cd0e3b0285bd7be35829169"
readonly SOURCE_BRANCH="experiment/profile-radial-account-switcher"
readonly TARGET_BRANCH="experiment/profile-radial-account-switcher-v2"
readonly PATCH_SCRIPT="/tmp/profile_radial_patch.py"

echo "[profile-radial] load patch helper"
git fetch --no-tags --depth=1 origin "${SOURCE_BRANCH}"
git show "FETCH_HEAD:.github/scripts/profile_radial_patch.py" > "${PATCH_SCRIPT}"

echo "[profile-radial] create clean experiment from ${BASE_SHA}"
git fetch --no-tags --depth=1 origin "${BASE_SHA}"
git checkout -b "${TARGET_BRANCH}" "${BASE_SHA}"

python3 "${PATCH_SCRIPT}"
git diff --check

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add lib test
if git diff --cached --quiet; then
  echo "[profile-radial] patch produced no changes" >&2
  exit 31
fi

git commit -m "feat: restore adaptive profile radial switcher"
git push origin "HEAD:${TARGET_BRANCH}"

echo "[profile-radial] experiment branch updated"
# This temporary invocation is only a branch-preparation job. Failing here
# deliberately skips the WPE artifact/release steps below it.
exit 42
