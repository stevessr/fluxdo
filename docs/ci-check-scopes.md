# CI check scopes

Feature checks use GitHub event paths plus the shared `_check-scope.yml` gate.
A PR path filter sees the accumulated merge-base diff, not just the latest push.
The gate uses the last completed successful run of the same workflow and PR,
with a small artifact recording the exact tested head and base. An ancestor
comparison of the previous successful head and current head decides whether
feature-specific files have changed. Renames consider both paths. A skipped
suite can carry its proven baseline forward only after the whole run succeeds.

First runs, failed/cancelled prior runs, changed base, rewrites, missing or
expired artifacts, incomplete comparisons and API errors run conservatively.
Explicit workflow dispatch and rerun always execute checks. Push and release
builds retain their original behavior. The network workflow keeps its existing
required aggregate result and uses the proven incremental base for its planner.
Shared UI, SDK, dependencies, localization and preparation code are explicit
inputs to feature checks. Keep event patterns and the gate patterns aligned
when adding feature dependencies. The gate records its reason in the job summary.
