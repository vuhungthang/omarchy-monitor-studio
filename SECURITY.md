# Security Policy

## Scope

Monitor Studio is an unsandboxed Omarchy shell plugin. When enabled, it runs
with the current user's permissions and can execute local commands and write
user-owned state. Review the source and dependencies before installation.

The plugin does not require root privileges, install packages, download code,
or access network services. Its intentional write surfaces are documented in
`docs/security-and-operations.md`.

## Reporting a vulnerability

After the repository becomes public, report vulnerabilities through GitHub's
private security-advisory form for the repository. Do not include sensitive
system information in a public issue.

Include the affected commit or release, reproduction steps, expected impact,
and any suggested mitigation. Hardware and monitor identifiers may be redacted
unless they are necessary to reproduce the issue.

## Supported versions

Until a second release exists, only the latest tagged release is supported.
Security fixes will be released as a new immutable tag and documented in the
changelog.
