## Summary

- Describe the change and why it is needed.

## Checklist

- [ ] I ran `swift package describe`.
- [ ] I ran `swift test`.
- [ ] I built the app unsigned with:
  `xcodebuild -project Ailert.xcodeproj -scheme Ailert -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- [ ] I updated docs if behavior changed.
- [ ] I added or updated tests.
- [ ] I considered privacy and safety impacts.

## Testing Notes

- Include test scenarios and outcomes.

## Privacy/Safety Review

- State any data handling, escalation, or alerting changes.
