# Ailert

**Open-source iOS emergency assistant** - Press one button and your phone immediately does what it can to help in any emergency.

![iOS 16+](https://img.shields.io/badge/iOS-16%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

### 🆘 One-Button Activation
- Large, accessible SOS button with hold-to-activate
- Discrete triggers: shake gesture, volume button combo
- Planned: Home screen widget for instant access
- Planned: Apple Watch support for wrist-based triggers

### 🧠 On-Device AI + Sensor Fusion
- **Motion Analysis**: Fall detection, impact detection, sudden stops
- **Audio Monitoring**: Ambient sound levels, distress detection
- **Location Tracking**: GPS coordinates, speed, heading
- **Device Context**: Battery, network status, time

### 📋 Incident Documentation
- **Video Recording**: Front/back camera, background recording
- **Photo Capture**: One-tap evidence photos
- **Timestamped Events**: Complete incident timeline
- **Reports**: Plain English + JSON formats

### 🔔 Privacy-First Escalation Ladder
1. **Monitoring** - Initial detection with cancel window
2. **Trusted Contacts** - SMS/call to your designated people
3. **Emergency Services** - CallKit integration for 911
4. **Nearby Responders** - Opt-in alerts with coarse location

### 🛡️ Safety & Anti-Abuse
- **Cancel PIN** - Safely cancel accidental triggers
- **Duress PIN** - Silent alert if forced to cancel
- **Coarse Location** - Privacy-protective location sharing
- **No Doxxing** - Sanitized data for public alerts
- **Audit Logging** - Tamper-evident action logs

## Getting Started

### Requirements
- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

### Installation

1. Clone the repository:
```bash
git clone https://github.com/ailert/ailert-ios.git
cd ailert-ios
```

2. Open in Xcode:
```bash
open Ailert.xcodeproj
```

3. Configure signing with your team

4. Build and run on device (simulator lacks some sensors)

### Permissions
The app requires these permissions for full functionality:
- **Location** - Always access for background tracking
- **Camera** - Video/photo evidence capture
- **Microphone** - Audio recording and detection
- **Motion** - Fall and impact detection
- **Notifications** - Critical emergency alerts

## Architecture

```
Ailert/
├── Models/           # Data models (Incident, Contact, Profile)
├── Services/         # Core logic (Session, Sensor, Escalation)
├── Views/            # SwiftUI views
├── Triggers/         # Discrete activation methods
└── Safety/           # Duress detection, privacy, audit
```

### Key Components

| Component | Purpose |
|-----------|---------|
| `IncidentSessionManager` | Central coordinator for active emergencies |
| `SensorFusionEngine` | Combines motion, audio, location data |
| `EscalationEngine` | Handles progressive alert escalation |
| `VideoRecorder` | AVFoundation-based evidence capture |
| `DuressDetector` | Identifies coerced cancellations |
| `PrivacyManager` | Data minimization and anti-doxxing |

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Priority Areas
- [ ] Apple Watch companion app
- [ ] Improved fall detection ML model
- [ ] RapidSOS integration for 911
- [ ] Localization
- [ ] Accessibility improvements

## Privacy & Security

Ailert is designed with privacy as a core principle:

- **On-device AI**: All inference runs locally, never uploaded
- **User-controlled sharing**: You decide what to share and with whom
- **Data minimization**: Only essential data is collected
- **Secure storage**: Encrypted local storage for sensitive data
- **Open source**: Full transparency, auditable code

## License

MIT License - see [LICENSE](LICENSE) for details.

## Disclaimer

Ailert is an emergency assistance tool, but it is not a replacement for professional emergency services. Always call 911 or your local emergency number in life-threatening situations. The developers are not responsible for any outcomes resulting from use of this app.

---

**Built with ❤️ for community safety**
