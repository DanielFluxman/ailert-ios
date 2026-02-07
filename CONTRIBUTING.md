# Contributing to Ailert

Thank you for your interest in contributing to Ailert! This project aims to help people in emergency situations, so every contribution matters.

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Use the bug report template (`.github/ISSUE_TEMPLATE/bug_report.yml`)
3. Include:
   - iOS version
   - Device model
   - Steps to reproduce
   - Expected vs actual behavior
   - Logs/screenshots if available

### Suggesting Features

1. Open an issue with the feature request template (`.github/ISSUE_TEMPLATE/feature_request.yml`)
2. Describe the use case and benefit
3. Consider privacy implications

### Code Contributions

#### Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ailert-ios.git
   ```
3. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

#### Development Guidelines

- **Swift Style**: Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- **SwiftUI**: Use declarative patterns, avoid UIKit unless necessary
- **Testing**: Add tests for new functionality
- **Privacy**: All data processing must happen on-device by default
- **Accessibility**: Support VoiceOver and Dynamic Type
- **Local checks**: Run `swift package describe`, `swift test`, and an unsigned iOS build before opening a PR

#### Pull Request Process

1. Update documentation for any new features
2. Add/update tests
3. Ensure all checks pass:
   ```bash
   swift package describe
   swift test
   xcodebuild -project Ailert.xcodeproj -scheme Ailert -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
   ```
4. Update CHANGELOG.md
5. Request review from maintainers

### Priority Areas

We especially welcome contributions in:

- [ ] Apple Watch app improvements
- [ ] Accessibility enhancements
- [ ] Localization (translations)
- [ ] ML model improvements
- [ ] Documentation
- [ ] Security hardening

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

If you discover a security vulnerability, please follow our [Security Policy](SECURITY.md). Do NOT open a public issue.

## Questions?

Open a discussion or reach out to maintainers.

---

Thank you for helping make emergency response accessible to everyone! 🆘
