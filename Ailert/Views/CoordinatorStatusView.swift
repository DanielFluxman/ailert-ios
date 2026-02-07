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
                    ForEach(sessionManager.coordinatorTranscript.suffix(20)) { entry in
                        TranscriptEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 200)
            .onChange(of: sessionManager.coordinatorTranscript.count) { _ in
                if let lastEntry = sessionManager.coordinatorTranscript.last {
                    withAnimation {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
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
}

// MARK: - Transcript Entry Row

struct TranscriptEntryRow: View {
    let entry: LLMTranscriptEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Icon
            Image(systemName: entry.type.icon)
                .font(.caption)
                .foregroundColor(iconColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.content)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Text(timeAgo)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(10)
        .background(backgroundColor)
        .cornerRadius(8)
    }
    
    private var iconColor: Color {
        switch entry.type {
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
