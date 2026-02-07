// SOSButtonView.swift
// Prominent emergency trigger button with haptic feedback

import SwiftUI

struct SOSButtonView: View {
    let onActivate: () -> Void
    
    @State private var isPressed = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?
    @State private var pulseAnimation = false
    
    private let holdDuration: TimeInterval = 1.5
    private let buttonSize: CGFloat = 200
    
    var body: some View {
        ZStack {
            // Outer pulse rings
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.red.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                    .frame(width: buttonSize + CGFloat(index) * 40, height: buttonSize + CGFloat(index) * 40)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0 : 1)
                    .animation(
                        Animation.easeOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.3),
                        value: pulseAnimation
                    )
            }
            
            // Progress ring
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color.white, lineWidth: 6)
                .frame(width: buttonSize + 10, height: buttonSize + 10)
                .rotationEffect(.degrees(-90))
            
            // Main button
            ZStack {
                // Background
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.red,
                                Color.red.opacity(0.8)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: buttonSize / 2
                        )
                    )
                    .shadow(color: .red.opacity(0.5), radius: isPressed ? 30 : 20)
                
                // Inner highlight
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.3),
                                Color.clear
                            ]),
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .padding(10)
                
                // SOS Text
                VStack(spacing: 4) {
                    Text("SOS")
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(isPressed ? "Hold..." : "Press & Hold")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .onAppear {
            pulseAnimation = true
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        startHold()
                    }
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
    }
    
    private func startHold() {
        isPressed = true
        holdProgress = 0
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Start progress timer
        let startTime = Date()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            withAnimation(.linear(duration: 0.02)) {
                holdProgress = min(CGFloat(elapsed / holdDuration), 1.0)
            }
            
            if elapsed >= holdDuration {
                timer.invalidate()
                activateSOS()
            }
        }
    }
    
    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        
        withAnimation(.spring()) {
            isPressed = false
            holdProgress = 0
        }
    }
    
    private func activateSOS() {
        holdTimer?.invalidate()
        holdTimer = nil
        
        // Success haptic
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)
        
        withAnimation(.spring()) {
            isPressed = false
            holdProgress = 0
        }
        
        onActivate()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SOSButtonView {
            print("SOS Activated!")
        }
    }
}
