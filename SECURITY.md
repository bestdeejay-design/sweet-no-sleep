# Security Policy

## Reporting a Vulnerability

Do not open a public issue for security vulnerabilities.

Report vulnerabilities via GitHub Security Advisories on
bestdeejay-design/sweet-no-sleep (Security tab, Report a vulnerability).
If advisories are unavailable, open a minimal private-contact issue asking
the maintainer for a secure channel and do not include exploit details.

Please include:

- Affected version or commit
- macOS version and chip (Apple Silicon or Intel)
- Steps to reproduce and potential impact

We will acknowledge receipt promptly, investigate, and coordinate a fix
and disclosure timeline with you.

## Supported Versions

| Version | Supported |
| ------- | --------- |
| Latest `main` and latest release | Yes |
| Older releases | No |

SweetNoSleep targets macOS 14 and later. Security fixes are provided for
the latest release and `main` only.

## Scope

In scope: the Swift sources, app bundle scripts, and packaged resources
of SweetNoSleep, including the Kiwi pet behavior and menu bar logic.
Out of scope: third-party dependencies, macOS itself, and Xcode tooling.
