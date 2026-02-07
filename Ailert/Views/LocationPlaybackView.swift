// LocationPlaybackView.swift
// Map view for playing back incident route (iOS 16 compatible)

import SwiftUI
import MapKit

struct LocationPlaybackView: View {
    let incident: Incident
    @Environment(\.dismiss) private var dismiss
    
    @State private var region: MKCoordinateRegion = MKCoordinateRegion()
    @State private var playbackProgress: Double = 0
    @State private var isPlaying: Bool = false
    @State private var playbackTimer: Timer?
    @State private var currentPointIndex: Int = 0
    @State private var routeSummary: RouteSummary?
    
    private var sortedSnapshots: [LocationSnapshot] {
        incident.locationSnapshots.sorted { $0.timestamp < $1.timestamp }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Map with UIKit wrapper for iOS 16 compatibility
                RouteMapView(
                    snapshots: sortedSnapshots,
                    currentIndex: currentPointIndex,
                    region: $region
                )
                .ignoresSafeArea(edges: .top)
                
                // Overlay controls
                VStack {
                    Spacer()
                    
                    // Route summary card
                    if let summary = routeSummary {
                        RouteInfoCard(summary: summary, incident: incident)
                            .padding(.horizontal)
                    }
                    
                    // Playback controls
                    if sortedSnapshots.count >= 2 {
                        PlaybackControls(
                            progress: $playbackProgress,
                            isPlaying: $isPlaying,
                            onPlay: startPlayback,
                            onPause: pausePlayback,
                            onScrub: scrubTo
                        )
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .padding()
                    }
                }
            }
            .navigationTitle("Route Playback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: generateShareText()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .onAppear {
                setupMap()
                calculateSummary()
            }
            .onDisappear {
                playbackTimer?.invalidate()
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupMap() {
        guard !sortedSnapshots.isEmpty else { return }
        
        let latitudes = sortedSnapshots.map { $0.latitude }
        let longitudes = sortedSnapshots.map { $0.longitude }
        
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.01,
            longitudeDelta: (maxLon - minLon) * 1.5 + 0.01
        )
        
        region = MKCoordinateRegion(center: center, span: span)
    }
    
    private func calculateSummary() {
        routeSummary = LiveLocationService.shared.generateRouteSummary(for: sortedSnapshots)
    }
    
    // MARK: - Playback
    
    private func startPlayback() {
        isPlaying = true
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let increment = 1.0 / Double(max(sortedSnapshots.count * 10, 1))
            playbackProgress += increment
            
            if playbackProgress >= 1.0 {
                playbackProgress = 1.0
                pausePlayback()
            }
            
            updateCurrentPoint()
        }
    }
    
    private func pausePlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func scrubTo(_ progress: Double) {
        playbackProgress = progress
        updateCurrentPoint()
    }
    
    private func updateCurrentPoint() {
        let index = Int(playbackProgress * Double(sortedSnapshots.count - 1))
        currentPointIndex = min(max(index, 0), sortedSnapshots.count - 1)
    }
    
    // MARK: - Sharing
    
    private func generateShareText() -> String {
        guard let summary = routeSummary else {
            return "Incident Route - No location data"
        }
        
        return """
        📍 Incident Route Summary
        
        Start: \(formatTime(summary.startTime))
        End: \(formatTime(summary.endTime))
        Duration: \(summary.formattedDuration)
        Distance: \(summary.formattedDistance)
        
        Start: https://maps.apple.com/?ll=\(summary.startCoordinate.latitude),\(summary.startCoordinate.longitude)
        End: https://maps.apple.com/?ll=\(summary.endCoordinate.latitude),\(summary.endCoordinate.longitude)
        """
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - UIKit Map Wrapper (iOS 16 Compatible)

struct RouteMapView: UIViewRepresentable {
    let snapshots: [LocationSnapshot]
    let currentIndex: Int
    @Binding var region: MKCoordinateRegion
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update region
        mapView.setRegion(region, animated: false)
        
        // Clear existing overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        
        guard snapshots.count >= 2 else { return }
        
        // Add route polyline
        let coordinates = snapshots.map { $0.coordinate }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)
        
        // Add start marker
        if let first = snapshots.first {
            let startAnnotation = RouteAnnotation(
                coordinate: first.coordinate,
                title: "Start",
                type: .start
            )
            mapView.addAnnotation(startAnnotation)
        }
        
        // Add end marker
        if let last = snapshots.last {
            let endAnnotation = RouteAnnotation(
                coordinate: last.coordinate,
                title: "End",
                type: .end
            )
            mapView.addAnnotation(endAnnotation)
        }
        
        // Add current position marker
        if currentIndex > 0 && currentIndex < snapshots.count {
            let currentAnnotation = RouteAnnotation(
                coordinate: snapshots[currentIndex].coordinate,
                title: "Current",
                type: .current
            )
            mapView.addAnnotation(currentAnnotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let routeAnnotation = annotation as? RouteAnnotation else { return nil }
            
            let identifier = "RouteMarker"
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            
            switch routeAnnotation.type {
            case .start:
                view.markerTintColor = .systemGreen
                view.glyphImage = UIImage(systemName: "flag.fill")
            case .end:
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "flag.checkered")
            case .current:
                view.markerTintColor = .systemOrange
                view.glyphImage = UIImage(systemName: "location.fill")
            }
            
            return view
        }
    }
}

// MARK: - Route Annotation

class RouteAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let type: AnnotationType
    
    enum AnnotationType {
        case start, end, current
    }
    
    init(coordinate: CLLocationCoordinate2D, title: String, type: AnnotationType) {
        self.coordinate = coordinate
        self.title = title
        self.type = type
    }
}

// MARK: - Route Info Card

struct RouteInfoCard: View {
    let summary: RouteSummary
    let incident: Incident
    
    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text(summary.formattedDistance)
                    .font(.headline)
                Text("Distance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider().frame(height: 50)
            
            VStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text(summary.formattedDuration)
                    .font(.headline)
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider().frame(height: 50)
            
            VStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("\(summary.pointCount)")
                    .font(.headline)
                Text("Points")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

// MARK: - Playback Controls

struct PlaybackControls: View {
    @Binding var progress: Double
    @Binding var isPlaying: Bool
    let onPlay: () -> Void
    let onPause: () -> Void
    let onScrub: (Double) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Slider(value: $progress, in: 0...1) { editing in
                if !editing {
                    onScrub(progress)
                }
            }
            .tint(.blue)
            
            HStack {
                Button {
                    progress = 0
                    onScrub(0)
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }
                
                Spacer()
                
                Button {
                    if isPlaying {
                        onPause()
                    } else {
                        if progress >= 1.0 { progress = 0 }
                        onPlay()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
        }
    }
}

#Preview {
    LocationPlaybackView(incident: Incident())
}
