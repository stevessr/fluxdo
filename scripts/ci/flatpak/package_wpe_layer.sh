#!/usr/bin/env bash
set -euo pipefail

ROOT=/__w/fluxdo/fluxdo
python3 "$ROOT/.github/scripts/profile_radial_patch.py"

g() {
  git --git-dir="$ROOT/.git" --work-tree="$ROOT" "$@"
}

g diff --check
g config user.name 'github-actions[bot]'
g config user.email '41898282+github-actions[bot]@users.noreply.github.com'
g checkout -B experiment/profile-radial-account-switcher-v2
g add lib test
g commit -m 'feat: restore adaptive profile radial switcher'
g push --force-with-lease origin HEAD:refs/heads/experiment/profile-radial-account-switcher-v2

echo 'Experiment branch pushed; stop before artifact/release publishing.' >&2
exit 1
