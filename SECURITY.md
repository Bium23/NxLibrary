# Security reports

Do not post keys, game files, credentials, private paths or unreviewed logs in
public issues.

When private vulnerability reporting is enabled, use this repository's
**Security → Report a vulnerability**. If that option is unavailable, ask the
maintainer for a private reporting channel without describing the vulnerability
or attaching sensitive data in a public issue. Private reporting must be
configured before a public binary release.

Include the NX Library version, macOS version, the affected operation and a
minimal reproduction using synthetic data. The current development branch is
the supported branch; this early project has no promised response SLA.

NX Library imports a private copy of keys, orchestrates an external engine and
runs without the App Sandbox. Only import and launch game apps and engine
checkouts you trust. Repository checks and diagnostic redaction reduce common
mistakes; they do not replace reviewing what you share.
