// MediaViewer.swift
// Full-screen media viewer for incident recordings

import SwiftUI
import AVKit

struct MediaViewer: View {
    let mediaCaptures: [MediaCapture]
    @State private var selectedIndex: Int = 0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if mediaCaptures.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No media captured")
                            .foregroundColor(.gray)
                    }
                } else {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(mediaCaptures.enumerated()), id: \.element.id) { index, capture in
                            MediaItemView(capture: capture)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .principal) {
                    if !mediaCaptures.isEmpty {
                        Text("\(selectedIndex + 1) of \(mediaCaptures.count)")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !mediaCaptures.isEmpty {
                        ShareLink(item: mediaCaptures[selectedIndex].localFileURL) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Media Item View

struct MediaItemView: View {
    let capture: MediaCapture
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                
                switch capture.type {
                case .video:
                    VideoPlayerView(url: capture.localFileURL)
                        .frame(maxWidth: geometry.size.width)
                        .cornerRadius(12)
                    
                case .photo:
                    PhotoView(url: capture.localFileURL)
                        .frame(maxWidth: geometry.size.width)
                    
                case .audio:
                    AudioPlayerView(url: capture.localFileURL)
                        .frame(maxWidth: geometry.size.width)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Timestamp
                Text(capture.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Video Player

struct VideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    
    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(9/16, contentMode: .fit)
            .onAppear {
                player = AVPlayer(url: url)
            }
            .onDisappear {
                player?.pause()
            }
    }
}

// MARK: - Photo View

struct PhotoView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = value
                            }
                            .onEnded { _ in
                                withAnimation(.spring()) {
                                    scale = max(1.0, min(scale, 3.0))
                                }
                            }
                    )
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded {
                                withAnimation(.spring()) {
                                    scale = scale > 1.0 ? 1.0 : 2.0
                                }
                            }
                    )
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        DispatchQueue.global().async {
            if let data = try? Data(contentsOf: url),
               let loaded = UIImage(data: data) {
                DispatchQueue.main.async {
                    image = loaded
                }
            }
        }
    }
}

// MARK: - Audio Player

struct AudioPlayerView: View {
    let url: URL
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 20) {
            // Waveform visualization placeholder
            HStack(spacing: 3) {
                ForEach(0..<40, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(Double(index) / 40.0 < progress ? 1.0 : 0.3))
                        .frame(width: 4, height: CGFloat.random(in: 10...50))
                }
            }
            .frame(height: 60)
            
            // Time indicator
            HStack {
                Text(formatTime(progress * duration))
                    .font(.caption)
                    .foregroundColor(.white)
                Spacer()
                Text(formatTime(duration))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Progress slider
            Slider(value: $progress, in: 0...1) { editing in
                if !editing, let player = player {
                    player.currentTime = progress * duration
                }
            }
            .tint(.white)
            
            // Play/Pause button
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }
        }
        .padding(30)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
        .onAppear {
            setupAudioPlayer()
        }
        .onDisappear {
            player?.stop()
            timer?.invalidate()
        }
    }
    
    private func setupAudioPlayer() {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            print("Error loading audio: \(error)")
        }
    }
    
    private func togglePlayback() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            timer?.invalidate()
        } else {
            player.play()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                progress = player.currentTime / duration
                if !player.isPlaying {
                    isPlaying = false
                    timer?.invalidate()
                }
            }
        }
        isPlaying.toggle()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Media Thumbnail Grid

struct MediaThumbnailGrid: View {
    let mediaCaptures: [MediaCapture]
    @State private var selectedCapture: MediaCapture?
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(mediaCaptures) { capture in
                MediaThumbnail(capture: capture)
                    .onTapGesture {
                        selectedCapture = capture
                    }
            }
        }
        .sheet(item: $selectedCapture) { capture in
            if let index = mediaCaptures.firstIndex(where: { $0.id == capture.id }) {
                MediaViewer(mediaCaptures: mediaCaptures)
            }
        }
    }
}

struct MediaThumbnail: View {
    let capture: MediaCapture
    @State private var thumbnail: UIImage?
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            
            // Type indicator
            VStack {
                Spacer()
                HStack {
                    Image(systemName: iconForType)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(4)
            }
        }
        .frame(height: 120)
        .clipped()
        .cornerRadius(8)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private var iconForType: String {
        switch capture.type {
        case .video: return "video.fill"
        case .photo: return "photo.fill"
        case .audio: return "waveform"
        }
    }
    
    private func loadThumbnail() {
        DispatchQueue.global().async {
            var thumb: UIImage?
            
            switch capture.type {
            case .photo:
                if let data = try? Data(contentsOf: capture.localFileURL),
                   let image = UIImage(data: data) {
                    thumb = image
                }
                
            case .video:
                let asset = AVAsset(url: capture.localFileURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    thumb = UIImage(cgImage: cgImage)
                }
                
            case .audio:
                // Use a waveform placeholder
                thumb = nil
            }
            
            DispatchQueue.main.async {
                thumbnail = thumb
            }
        }
    }
}

#Preview {
    MediaViewer(mediaCaptures: [])
}
