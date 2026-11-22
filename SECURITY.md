# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT** open a public issue
2. Email the maintainer directly or use GitHub's private vulnerability reporting
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

## Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Fix timeline**: Depends on severity

## Scope

Security issues we care about:
- Authentication/authorization bypasses
- Data leaks (API keys, tokens, personal data)
- Remote code execution
- Injection vulnerabilities

Out of scope:
- Issues requiring physical device access
- Social engineering
- Third-party dependencies (report to them directly)

## Secrets in this repository

This repository is public. Gemini API keys live only in the iOS Keychain (entered in Settings → Gemini),
are sent in the `x-goog-api-key` header, and are never stored in source or commits. The static guard
(`scripts/blueprint/verify_blueprint.py`) fails CI if a key-like string appears in any tracked file.
Debug logs still show the first 6 characters of a key; PLAN.md task T2.4 removes that. Keys that were
committed in the past are still in git history: revoke them in Google AI Studio.

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest `main` and `feature/voice-v2` | Yes |
| Older builds | No |

Thank you for helping keep OpenVision secure!
