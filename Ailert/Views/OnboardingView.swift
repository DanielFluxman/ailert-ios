// OnboardingView.swift
// First-launch setup flow

import SwiftUI
import CoreLocation
import AVFoundation
import UserNotifications

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.05, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack {
                TabView(selection: $currentPage) {
                    WelcomePage()
                        .tag(0)
                    
                    PermissionsPage()
                        .tag(1)
                    
                    ContactsSetupPage()
                        .tag(2)
                    
                    SafetyInfoPage()
                        .tag(3)
                    
                    ReadyPage(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
        }
    }
}

// MARK: - Welcome Page

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "shield.checkered")
                .font(.system(size: 80))
                .foregroundColor(.red)
            
            Text("Welcome to Ailert")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Your personal emergency assistant.\nPrivacy-first. On-device AI.\nAlways ready to help.")
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Text("Swipe to continue →")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 50)
        }
        .padding()
    }
}

// MARK: - Permissions Page

struct PermissionsPage: View {
    @StateObject private var locationManager = LocationPermissionManager()
    @State private var cameraGranted = false
    @State private var microphoneGranted = false
    @State private var notificationsGranted = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("Permissions")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Ailert needs these permissions to help you in emergencies")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 16) {
                PermissionRow(
                    icon: "location.fill",
                    title: "Location",
                    description: "Share your location with responders",
                    isGranted: .constant(locationManager.isAuthorized)
                ) {
                    locationManager.requestPermission()
                }
                
                PermissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    description: "Record evidence during incidents",
                    isGranted: $cameraGranted
                ) {
                    requestCamera()
                }
                
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Audio recording and detection",
                    isGranted: $microphoneGranted
                ) {
                    requestMicrophone()
                }
                
                PermissionRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Critical alerts and updates",
                    isGranted: $notificationsGranted
                ) {
                    requestNotifications()
                }
            }
            .padding()
            
            Spacer()
        }
        .padding()
        .onAppear {
            checkCurrentPermissions()
        }
    }
    
    private func checkCurrentPermissions() {
        // Check camera
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraGranted = true
        default: cameraGranted = false
        }
        
        // Check microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneGranted = true
        default: microphoneGranted = false
        }
        
        // Check notifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsGranted = settings.authorizationStatus == .authorized
            }
        }
    }
    
    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraGranted = granted
            }
        }
    }
    
    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                microphoneGranted = granted
            }
        }
    }
    
    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert]) { granted, _ in
            DispatchQueue.main.async {
                notificationsGranted = granted
            }
        }
    }
}

// MARK: - Location Permission Manager

class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var isAuthorized = false
    
    override init() {
        super.init()
        manager.delegate = self
        checkStatus()
    }
    
    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }
    
    private func checkStatus() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
        default:
            isAuthorized = false
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkStatus()
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Allow") {
                    action()
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Contacts Setup Page

struct ContactsSetupPage: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showAddContact = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("Trusted Contacts")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Add people who will be notified in an emergency")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            if settingsManager.trustedContacts.isEmpty {
                Button {
                    showAddContact = true
                } label: {
                    VStack {
                        Image(systemName: "person.badge.plus")
                            .font(.largeTitle)
                        Text("Add Contact")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(settingsManager.trustedContacts) { contact in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.green)
                            Text(contact.name)
                                .foregroundColor(.white)
                            Spacer()
                            Text(contact.phone)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Button {
                        showAddContact = true
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Another")
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.top)
                }
            }
            
            Spacer()
            
            Text("You can add more contacts later in Settings")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 50)
        }
        .padding()
        .sheet(isPresented: $showAddContact) {
            ContactEditor(contact: nil)
        }
    }
}

// MARK: - Safety Info Page

struct SafetyInfoPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("Stay Safe")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 20) {
                SafetyTip(
                    icon: "hand.tap.fill",
                    title: "One Button Activation",
                    description: "Press and hold the SOS button to start an emergency session"
                )
                
                SafetyTip(
                    icon: "clock.fill",
                    title: "Cancel Window",
                    description: "You have 30 seconds to cancel if triggered accidentally"
                )
                
                SafetyTip(
                    icon: "exclamationmark.triangle.fill",
                    title: "Duress Code",
                    description: "If forced to cancel, use your duress PIN for silent alert"
                )
                
                SafetyTip(
                    icon: "lock.shield.fill",
                    title: "Privacy First",
                    description: "Core safety detection is on-device. Optional AI coordinator uses your configured provider."
                )
            }
            .padding()
            
            Spacer()
        }
        .padding()
    }
}

struct SafetyTip: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Ready Page

struct ReadyPage: View {
    @Binding var hasCompletedOnboarding: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("You're Ready")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Ailert is set up and ready to help\nkeep you safe.")
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button {
                hasCompletedOnboarding = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding()
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(SettingsManager())
}
