// CoordinatorStatusView.swift
// Displays real-time LLM coordinator status during active incidents

import SwiftUI

struct CoordinatorStatusView: View {
    @ObservedObject var sessionManager: IncidentSessionManager
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            if isExpanded {
                // Transcript
                transcriptView

                // Chat composer (text + speech-to-text)
                chatComposerView
                
                // Pending action confirmation
                if let pending = sessionManager.pendingCoordinatorAction {
                    pendingActionView(pending)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                // Status indicator
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: sessionManager.coordinatorState.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(statusColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Coordinator")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(sessionManager.coordinatorState.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Live indicator when analyzing
                if sessionManager.coordinatorState == .analyzing {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.15))
                    .cornerRadius(8)
                }
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Transcript
    
    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sessionManager.coordinatorTranscript.suffix(30)) { entry in
                        TranscriptEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 260)
            .onChange(of: sessionManager.coordinatorTranscript.count) { _ in
                if let lastEntry = sessionManager.coordinatorTranscript.last {
                    withAnimation {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Chat Composer

    private var chatComposerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                Button {
                    sessionManager.toggleCoordinatorSpeechInput()
                } label: {
                    Image(systemName: sessionManager.isCoordinatorSpeechActive ? "waveform.circle.fill" : "mic.circle")
                        .font(.title3)
                        .foregroundColor(sessionManager.isCoordinatorSpeechActive ? .red : .blue)
                }

                TextField("Type or dictate to AI coordinator", text: $sessionManager.coordinatorDraftMessage, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit {
                        sessionManager.sendCoordinatorDraftMessage()
                    }

                Button {
                    sessionManager.sendCoordinatorDraftMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(canSendDraft ? .white : .secondary)
                        .padding(10)
                        .background(canSendDraft ? Color.blue : Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .disabled(!canSendDraft)
            }
            .padding(.horizontal)

            if sessionManager.isCoordinatorSpeechActive {
                Text("Listening and transcribing...")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            } else if let speechError = sessionManager.coordinatorSpeechError, !speechError.isEmpty {
                Text(speechError)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Pending Action
    
    private func pendingActionView(_ decision: LLMDecision) -> some View {
        VStack(spacing: 12) {
            Divider()
            
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Action requires confirmation")
                    .font(.subheadline.bold())
            }
            
            Text(decision.reasoning)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 12) {
                Button {
                    sessionManager.cancelCoordinatorAction()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
                
                Button {
                    sessionManager.confirmCoordinatorAction()
                } label: {
                    HStack {
                        Image(systemName: decision.actionType.icon)
                        Text(decision.actionType.displayName)
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(Color.orange.opacity(0.1))
    }
    
    // MARK: - Helpers
    
    private var statusColor: Color {
        switch sessionManager.coordinatorState {
        case .idle: return .gray
        case .listening: return .blue
        case .analyzing: return .purple
        case .acting: return .green
        case .waitingConfirm: return .orange
        case .error: return .red
        }
    }

    private var canSendDraft: Bool {
        !sessionManager.coordinatorDraftMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}

// MARK: - Transcript Entry Row

struct TranscriptEntryRow: View {
    let entry: LLMTranscriptEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUserMessage {
                Spacer(minLength: 24)
                bubbleContent
                iconView
            } else {
                iconView
                bubbleContent
                Spacer(minLength: 24)
            }
        }
        .padding(10)
    }

    private var iconView: some View {
        Image(systemName: entry.type.icon)
            .font(.caption)
            .foregroundColor(iconColor)
            .frame(width: 20)
            .padding(.top, 2)
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.type.displayName.uppercased())
                .font(.caption2.bold())
                .foregroundColor(iconColor)

            Text(entry.content)
                .font(.caption)
                .foregroundColor(.primary)
            
            Text(timeAgo)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(backgroundColor)
        .cornerRadius(10)
    }

    private var isUserMessage: Bool {
        entry.type == .user
    }
    
    private var iconColor: Color {
        switch entry.type {
        case .user: return .blue
        case .assistant: return .mint
        case .observation: return .blue
        case .analysis: return .purple
        case .decision: return .orange
        case .action: return .green
        case .confirmation: return .green
        case .error: return .red
        }
    }
    
    private var backgroundColor: Color {
        switch entry.type {
        case .user: return .blue.opacity(0.12)
        case .assistant: return .mint.opacity(0.12)
        case .action, .confirmation: return .green.opacity(0.1)
        case .decision: return .orange.opacity(0.1)
        case .error: return .red.opacity(0.1)
        default: return Color(.secondarySystemBackground)
        }
    }
    
    private var timeAgo: String {
        let seconds = Int(-entry.timestamp.timeIntervalSinceNow)
        if seconds < 60 {
            return "\(seconds)s ago"
        } else {
            return "\(seconds / 60)m ago"
        }
    }
}

// MARK: - Compact Coordinator Pill

/// A smaller pill view to show coordinator status in limited space
struct CoordinatorStatusPill: View {
    @ObservedObject var sessionManager: IncidentSessionManager
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: sessionManager.coordinatorState.icon)
                .font(.caption2)
            
            Text(sessionManager.coordinatorState == .analyzing ? "AI Active" : "AI \(sessionManager.coordinatorState.displayName)")
                .font(.caption2.bold())
        }
        .foregroundColor(pillColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(pillColor.opacity(0.15))
        .cornerRadius(12)
    }
    
    private var pillColor: Color {
        switch sessionManager.coordinatorState {
        case .idle: return .gray
        case .listening: return .blue
        case .analyzing: return .purple
        case .acting, .waitingConfirm: return .orange
        case .error: return .red
        }
    }
}

#Preview {
    VStack {
        Text("Preview placeholder")
            .padding()
    }
}
