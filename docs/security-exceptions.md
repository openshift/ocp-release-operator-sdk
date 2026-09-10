# Security Exceptions

This file documents known security findings that have been reviewed and accepted.

## Process

1. Identify the finding (CVE, GHSA, or tool-specific ID).
2. Document it in this file with rationale.
3. Suppress it in the relevant tool:
   - **Trivy**: add an entry to `.trivyignore` (create the file if it does not yet exist).
   - **govulncheck**: govulncheck has no suppression/ignore-list config file. Document the exception here only; the finding will continue to surface in CI output until the underlying dependency is updated or the vulnerable code path is removed. Track follow-up remediation in a linked issue.
4. Get approval from a reviewer listed in `OWNERS`.

## Active Exceptions

*No active exceptions at this time.*

## Format

| ID | Tool | Package | Rationale | Reviewer | Date |
|---|---|---|---|---|---|
| *(example)* CVE-YYYY-NNNNN | govulncheck | example/pkg | Not reachable in our code paths | @reviewer | YYYY-MM-DD |
