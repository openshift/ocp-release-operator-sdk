# Review Instructions

## Must fix before merge

- Flag CLI behavior regressions, incorrect error handling, and unsafe execution paths.
- Flag Helm lifecycle changes that lose resources or prevent deletion.
- Flag downstream build changes that omit required carried patches.
- Treat style and naming as suggestion-only unless they change behavior.

## Minor issue volume

Report at most five minor issues; summarize additional similar items.
If all findings are minor, lead with “No blocking issues.”

## Do not report

- `vendor/**`: vendored implementation; review dependency-manifest changes separately.
- `internal/bindata/olm/manifests.go`: generated embedded assets.
- `internal/generate/packagemanifest/packagemanifestfakes/**`: generated fake.
- `internal/generate/clusterserviceversion/bases/definitions/zz_generated.markerhelp.go`: generated marker help.
- `go.sum`: do not comment on individual checksum lines; investigate unexplained churn.
- Formatting and lint findings already covered by `make test-sanity` (`Makefile:152`).

Keep `go.mod` reviewable: dependencies, replacements, exclusions, and Go directives matter.
The sidecar explicitly excludes the vendor tree and local generated paths above; it loads REVIEW.md for the remaining review policy.

## Always check

- Use “OpenShift,” not “Openshift,” in user-facing text ([conventions](https://github.com/openshift/enhancements/blob/master/CONVENTIONS.md)).
- Identify compatibility impact when changing stable API consumers ([breaking changes](https://github.com/openshift/enhancements/blob/master/dev-guide/breaking-changes.md)).
- Apply API rules only to APIs actually changed, not unrelated mirrored code ([API conventions](https://github.com/openshift/enhancements/blob/master/dev-guide/api-conventions.md)).
- Check declared behavior against code, not only historical examples.

## Verification Bar

Every comment must cite file:line evidence in the diff or linked implementation.
Read the enclosing function and relevant call sites before reporting a defect.
Distinguish confirmed failures from missing validation; do not invent support claims.
For docs, verify commands against the actual target and references against source.

## Re-review

Review changed lines since the previous review; do not introduce new nits on unchanged code.
Do not repeat resolved findings without new evidence.
Converge toward approval when blocking findings are resolved.

## Path-specific Rules

### `internal/helm/**`

Check CR updates separately from chart-resource writes.
For patch behavior inspect the returned patch type, not only helper names.
Preserve loader defaults and duplicate-GVK rejection when changing watches.
Use the existing watch, controller, and release tests as regression starting points.

### `ci/**`

Check patch application ordering and the selected downstream build target.
Do not assume the root Makefile and downstream wrapper build the same binary set.

### `release/helm/**`

Keep the copied Helm binary path consistent with the build output and entrypoint.
Check vendored build settings when changing the builder stage.

### `ai-docs/**`

Keep claims source-backed and distinguish local facts from support guarantees.
Preserve links to existing repository documentation instead of duplicating it.
Do not include review caches or temporary source backups.
