# Security Policy

## Reporting a Vulnerability

**⚠️ Do NOT open a public issue for security vulnerabilities.**

If you discover a security vulnerability in Ailert, please report it responsibly:

1. **Email**: Send details to [security contact - add your email here]
2. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Any suggested fixes

## Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 7 days
- **Fix Target**: Based on severity (critical: 7 days, high: 30 days, medium: 90 days)

## Scope

### In Scope
- iOS app vulnerabilities
- Data exposure risks
- Authentication/authorization bypasses
- Privacy violations
- Abuse potential (false alerts, doxxing)

### Out of Scope
- Social engineering attacks
- Physical device access attacks
- Denial of service (unless causing safety risk)
- Third-party dependencies (report to upstream)

## Safe Harbor

We will not pursue legal action against researchers who:
- Act in good faith
- Avoid privacy violations and data destruction
- Report findings promptly and confidentially
- Allow reasonable time for fixes before disclosure

## Security Design Principles

Ailert is built with these security principles:

1. **On-device processing**: AI and sensor analysis happen locally
2. **Minimal data collection**: Only essential emergency data
3. **User control**: Users decide what to share and with whom
4. **Audit logging**: All safety-critical actions are logged
5. **Secure storage**: Sensitive data encrypted at rest

Thank you for helping keep Ailert users safe.
