# File Size Exceptions

Files listed here are exempt from the 600-line limit enforced by `hack/check-file-size.sh`. Each exception requires justification and a tracking issue or plan for eventual refactoring.

## Active Exceptions

| File | Lines | Justification | Tracking |
|---|---|---|---|
| `internal/generate/clusterserviceversion/clusterserviceversion_updaters.go` | ~695 | CSV update logic is tightly coupled; splitting would fragment the update transaction boundary. Upstream sync risk. | Defer refactor to upstream sync |
| `internal/olm/operator/registry/index_image.go` | ~680 | Registry index operations form a single workflow; refactor deferred to avoid upstream merge conflicts. | Defer refactor to upstream sync |
| `hack/generate/samples/internal/go/memcached-with-customization/memcached_with_customization.go` | ~1313 | Sample generator with embedded Go templates; splitting would fragment template coherence and break `make generate`. | Defer refactor to upstream sync |
| `hack/generate/samples/internal/go/memcached-with-customization/e2e_test_code.go` | ~876 | Scaffolded e2e test source embedded as a Go template string for `make generate`; splitting the template would fragment test coherence and break generation. | OAPE-965 |
| `internal/olm/operator/registry/operator_installer_test.go` | ~688 | Table-driven installer test suite covering install/upgrade/uninstall flows; splitting would separate tightly related test fixtures and setup helpers. | OAPE-965 |
