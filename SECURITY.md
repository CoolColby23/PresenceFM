# Security Policy

## Supported versions

Security fixes are provided for the latest published release. During the 1.0
release-candidate period, reports should be checked against both the latest
release and the current `main` branch. Older releases may be asked to upgrade
before a fix is prepared.

## Reporting

Do not open public issues for credential exposure or exploitable vulnerabilities. Use GitHub's private vulnerability reporting for this repository. Include the affected version, reproduction steps, and impact.

The bundled Discord Application ID is public and recoverable from the distributed app. User-provided Last.fm API credentials and authorization tokens remain in an owner-only local file and must never appear in logs, screenshots, or issue attachments.

In-app update archives are published through the official GitHub release workflow and authenticated with Sparkle EdDSA signatures. The private update key is stored as an encrypted repository Actions secret and must never be committed, logged, or attached to a release; only its public key is embedded in PresenceFM.
