#!/usr/bin/env bash
set -euo pipefail

python3 .github/scripts/profile_radial_patch.py
git diff --check

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git checkout -B experiment/profile-radial-account-switcher-v2
git add lib test
git commit -m 'feat: restore adaptive profile radial switcher'
git push --force-with-lease origin HEAD:refs/heads/experiment/profile-radial-account-switcher-v2

echo 'Experiment branch pushed; stop before artifact/release publishing.' >&2
exit 1
