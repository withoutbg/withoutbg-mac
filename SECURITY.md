# Security Policy

## Reporting a vulnerability

Do not create a public GitHub issue for security vulnerabilities.

Email [contact@withoutbg.com](mailto:contact@withoutbg.com) with:

- A description of the vulnerability
- Steps to reproduce
- Affected version / build (app version, macOS version, Intel vs Apple Silicon)
- Potential impact
- Any suggested fix (optional)

You will receive an acknowledgement within 48 hours and a status update within 7 days.

## Scope

This policy covers:

- **withoutBG** (desktop app)
- **WithoutBG Server** (headless / Local API distribution)
- Shared packages in this repository (`WithoutBGCore` and related)

Out of scope:

- Third-party tools that call the Local API
- The withoutBG Cloud API and website (see [withoutbg.com](https://withoutbg.com) / org repositories for those surfaces)

## Supported versions

Security fixes are applied to the latest released build only. We do not backport to older versions.

## Local processing note

Background removal in this app runs on-device. Images are not uploaded for the open-weights path. Reports that assume cloud upload of user images for local processing are out of scope unless a specific build or setting changes that behavior.

## Disclosure

We follow a 90-day coordinated disclosure timeline. After a fix is released, we will publish a security advisory on GitHub when appropriate.
