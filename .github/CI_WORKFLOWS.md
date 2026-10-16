# GitHub Actions execution policy

Keep release and platform delivery automatic, but run historical feature-specific
regression workflows only when they are relevant. Their Dart tests remain in the
repository and are not removed by this CI change.

## Automatic workflows

- `build-apk.yaml`: pushes to `main` touching Android app inputs, plus manual
  dispatch. Successful APK builds update the `nightly` Release. Version tags do
  **not** trigger it; `build.yaml` handles tagged multi-platform releases.
- `build.yaml`: `v*` tags and manual dispatch; do not weaken release checks.
- `account-runtime-switch.yaml`, `direct-login.yaml`,
  `discourse-compat-pr-check.yml`, and `webview-cookie-manager.yaml`:
  path-scoped pull request regression checks. There is no duplicate `main` push
  run for account switching or direct login.
- `flatpak-wpe-layer.yaml`: relevant Flatpak WPE manifest/build changes or
  manual dispatch; publishes a release artifact needed by Flatpak packaging.
- `cleanup-actions-runs.yml`: weekly maintenance (Sunday 03:17 UTC),
  with manual dry-run support.

## Run on demand

In the GitHub **Actions** tab, select the workflow and choose **Run workflow**
on the branch whose behavior needs verification:

- `blob-image-cache.yaml` — image blob/cache integration
- `emoji-reaction-rendering.yaml` — emoji and reaction regressions
- `image-provider-cache-keys.yaml` — shared image provider/cache keys
- `preload-startup.yaml` — startup/preload contracts
- `request-cache.yaml` — Discourse network request caches
- `stevessr.yaml` — StevesSR composer / asset / export tests

These checks do not run automatically on unrelated PRs or after merge.
Run relevant ones before merging changes to these subsystems. The blob cache
workflow is deliberately read-only: CI must not commit formatting fixes
back to a contributor's branch.

Other manual tools such as `cliff-dryrun.yaml` remain available.
`temp-pr132-https-verify.yml` remains until HTTPS PR #132 is resolved;
remove the temporary launcher after its purpose has ended.

When replacing a path-scoped check, verify repository branch protection/ruleset
required check names, since the GitHub App may not have access to those settings.
