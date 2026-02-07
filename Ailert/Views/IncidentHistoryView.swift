// IncidentHistoryView.swift
// View past incidents and their reports

import SwiftUI

struct IncidentHistoryView: View {
    @State private var incidents: [Incident] = []
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if incidents.isEmpty {
                    // Empty state (iOS 16 compatible)
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Incidents")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Your incident history will appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(incidents) { incident in
                            NavigationLink {
                                IncidentDetailView(incident: incident)
                            } label: {
                                IncidentRow(incident: incident)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                IncidentStore.shared.delete(id: incidents[index].id)
                            }
                            incidents.remove(atOffsets: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("Incident History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                incidents = IncidentStore.shared.loadAll()
            }
        }
    }
}

// MARK: - Incident Row

struct IncidentRow: View {
    let incident: Incident
    
    var body: some View {
        HStack {
            // Icon
            Image(systemName: incident.classification.icon)
                .font(.title2)
                .foregroundColor(colorForStatus(incident.status))
                .frame(width: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(incident.classification.displayName)
                    .font(.headline)
                
                Text(formatDate(incident.sessionStart))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status badge
            Text(incident.status.rawValue.capitalized)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colorForStatus(incident.status).opacity(0.2))
                .foregroundColor(colorForStatus(incident.status))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func colorForStatus(_ status: IncidentStatus) -> Color {
        switch status {
        case .active: return .red
        case .cancelled: return .gray
        case .escalated: return .orange
        case .resolved: return .green
        case .duress: return .purple
        }
    }
}

// MARK: - Incident Detail View

struct IncidentDetailView: View {
    let incident: Incident
    @State private var report: IncidentReport?
    @State private var showingShareSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: incident.classification.icon)
                            .font(.title)
                        Text(incident.classification.displayName)
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    
                    Text("Status: \(incident.status.rawValue.capitalized)")
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Timeline
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timeline")
                        .font(.headline)
                    
                    Text("Started: \(formatDate(incident.sessionStart))")
                    
                    if let end = incident.sessionEnd {
                        Text("Ended: \(formatDate(end))")
                        Text("Duration: \(formatDuration(end.timeIntervalSince(incident.sessionStart)))")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Events
                if !incident.events.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Events")
                            .font(.headline)
                        
                        ForEach(incident.events) { event in
                            HStack(alignment: .top) {
                                Text(formatTime(event.timestamp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                
                                Text(event.description)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Media
                if !incident.mediaCaptures.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Media Captured")
                            .font(.headline)
                        
                        let videos = incident.mediaCaptures.filter { $0.type == .video }
                        let photos = incident.mediaCaptures.filter { $0.type == .photo }
                        
                        if !videos.isEmpty {
                            Text("📹 \(videos.count) video(s)")
                        }
                        if !photos.isEmpty {
                            Text("📷 \(photos.count) photo(s)")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Report
                if let report = report {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Report")
                            .font(.headline)
                        
                        ScrollView(.horizontal) {
                            Text(report.plainTextReport)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("Incident Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            let generator = IncidentReportGenerator()
            report = generator.generateReport(for: incident)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

#Preview {
    IncidentHistoryView()
}
