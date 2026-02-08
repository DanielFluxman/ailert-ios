# Changelog

All notable changes to Ailert will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project structure
- Core emergency trigger system (SOS button, shake, volume button)
- Sensor fusion engine (motion, audio, location)
- Video and photo capture during incidents
- Privacy-first escalation ladder
- Trusted contacts management
- Duress detection and safe cancel
- Audit logging system
- Settings and onboarding UI
- Incident history and reporting
- AI coordinator dashboard transcript entries for sensor observations and candidate actions
- Live incident context syncing between incident session and AI coordinator
- Expanded coordinator status feed labels and transcript capacity

### Changed
- Improved AI coordinator decision parsing for fenced JSON and normalized action names
- Updated README and security docs to reflect on-device-first processing with optional cloud LLM coordinator
- Corrected repository clone URL in README

### Security
- On-device-first processing for core safety workflows
- Coarse location option for privacy
- Anti-doxxing data sanitization
- Tamper-evident audit logs
- Clarified optional cloud LLM boundary for AI coordinator usage

## [1.0.0] - TBD

- Initial public release
