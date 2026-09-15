# Security Policy

## Supported Versions

Operator SDK makes a constant stream of releases. In general, this means that security
updates will be made in minor releases for the most recent major release only.

## Reporting a Vulnerability

To report a vulnerability, please follow the instructions at
https://access.redhat.com/security/team/contact

## Additional Resources

- [THREAT_MODEL.md](THREAT_MODEL.md) — Assets, trust boundaries, threats, and mitigations
- [docs/security-guidelines.md](docs/security-guidelines.md) — RBAC, TLS, container security patterns
- [docs/security-exceptions.md](docs/security-exceptions.md) — Reviewed and accepted findings
- CI security scanning is handled by OpenShift Prow (downstream) and `make test-sanity` checks
