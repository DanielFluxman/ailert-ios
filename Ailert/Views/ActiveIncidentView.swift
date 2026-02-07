// ActiveIncidentView.swift
// View displayed during an active emergency incident

import SwiftUI

struct ActiveIncidentView: View {
    @EnvironmentObject var incidentManager: IncidentSessionManager
    @State private var showCancelSheet = false
    @State private var enteredPIN = ""
    @State private var showCamera = false
    @State private var showClassificationPicker = false
    
    var body: some View {
        ZStack {
            // Emergency red background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.red.opacity(0.9),
                    Color.red.opacity(0.7)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Text("EMERGENCY ACTIVE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.8))
                    
                    // Tappable classification - tap to change
                    Button {
                        showClassificationPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: incidentManager.currentClassification.icon)
                            Text(incidentManager.currentClassification.displayName)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                    }
                    
                    // Timer
                    Text(formatTime(incidentManager.elapsedTime))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.top, 60)
                
                // Escalation level
                EscalationIndicator(level: incidentManager.currentIncident?.escalationLevel ?? .none)

                DocumentationStatusView(incidentManager: incidentManager)
                
                Spacer()
                
                // Video recording controls
                VideoControlsView(incidentManager: incidentManager)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    // Escalate button
                    Button {
                        let currentLevel = incidentManager.currentIncident?.escalationLevel ?? .none
                        let nextLevel: EscalationLevel = currentLevel == .none ? .trustedContacts : 
                                                         currentLevel == .trustedContacts ? .emergencyServices : .nearbyResponders
                        incidentManager.escalate(to: nextLevel)
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("ESCALATE NOW")
                        }
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                    }
                    
                    // Cancel button
                    Button {
                        showCancelSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("I'm Safe - Cancel")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showCancelSheet) {
            CancelSheet(enteredPIN: $enteredPIN) { pin in
                incidentManager.cancelSession(pin: pin)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Change Emergency Type", isPresented: $showClassificationPicker) {
            ForEach(EmergencyClassification.allCases, id: \.self) { classification in
                Button(classification.displayName) {
                    incidentManager.updateClassification(classification)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Escalation Indicator

struct EscalationIndicator: View {
    let level: EscalationLevel
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<4) { index in
                VStack(spacing: 4) {
                    Circle()
                        .fill(index <= level.rawValue ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 12, height: 12)
                    
                    Text(levelName(index))
                        .font(.caption2)
                        .foregroundColor(index <= level.rawValue ? .white : .white.opacity(0.5))
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(12)
    }
    
    private func levelName(_ index: Int) -> String {
        switch index {
        case 0: return "Monitor"
        case 1: return "Contacts"
        case 2: return "911"
        case 3: return "Nearby"
        default: return ""
        }
    }
}

// MARK: - Video Controls

struct VideoControlsView: View {
    @ObservedObject var incidentManager: IncidentSessionManager
    
    var body: some View {
        HStack(spacing: 30) {
            // Photo capture
            Button {
                incidentManager.capturePhoto()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                    Text("Photo")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(width: 70, height: 70)
                .background(Color.white.opacity(0.2))
                .cornerRadius(16)
            }
            
            // Video record button
            Button {
                if incidentManager.isVideoRecording {
                    incidentManager.stopVideoRecording()
                } else {
                    incidentManager.startVideoRecording()
                }
            } label: {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(incidentManager.isVideoRecording ? Color.white : Color.clear)
                            .frame(width: 50, height: 50)
                        
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 60, height: 60)
                        
                        if incidentManager.isVideoRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: 20, height: 20)
                        }
                    }
                    
                    Text(incidentManager.isVideoRecording ? formatDuration(incidentManager.videoRecordingDuration) : "Record")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            
            // Switch camera
            Button {
                incidentManager.switchCamera()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.title2)
                    Text("Flip")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(width: 70, height: 70)
                .background(Color.white.opacity(0.2))
                .cornerRadius(16)
            }
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct DocumentationStatusView: View {
    @ObservedObject var incidentManager: IncidentSessionManager

    var body: some View {
        HStack(spacing: 14) {
            Label(
                incidentManager.isVideoRecording ? "Video On" : "Video Off",
                systemImage: incidentManager.isVideoRecording ? "video.fill" : "video.slash.fill"
            )

            Label(
                "\(Int(incidentManager.liveAudioDecibels)) dB",
                systemImage: "waveform"
            )

            Label(
                "\(incidentManager.sensorSnapshotCount)",
                systemImage: "list.bullet.rectangle.portrait"
            )
        }
        .font(.caption.bold())
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.22))
        .cornerRadius(12)
    }
}

// MARK: - Cancel Sheet

struct CancelSheet: View {
    @Binding var enteredPIN: String
    let onCancel: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Cancel Emergency")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Enter your PIN to confirm you're safe.\nIf you're in danger, enter your duress PIN.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            SecureField("PIN", text: $enteredPIN)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            
            HStack(spacing: 16) {
                Button("Quick Cancel") {
                    onCancel(nil)
                    dismiss()
                }
                .foregroundColor(.secondary)
                
                Button("Confirm") {
                    onCancel(enteredPIN.isEmpty ? nil : enteredPIN)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(false) // Allow empty PIN for quick cancel
            }
        }
        .padding(30)
    }
}

#Preview {
    ActiveIncidentView()
        .environmentObject(IncidentSessionManager())
}
