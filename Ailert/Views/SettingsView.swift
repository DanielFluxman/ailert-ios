// SettingsView.swift
// Configuration screen for all app settings

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Emergency Profile
                Section {
                    NavigationLink {
                        EmergencyProfileEditor()
                    } label: {
                        HStack {
                            Image(systemName: "person.text.rectangle.fill")
                                .foregroundColor(.blue)
                            Text("Emergency Profile")
                        }
                    }
                } header: {
                    Text("Medical Info")
                } footer: {
                    Text("Your medical information can be shared with first responders")
                }
                
                // Trusted Contacts
                Section {
                    NavigationLink {
                        TrustedContactsView()
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.green)
                            Text("Trusted Contacts")
                            Spacer()
                            Text("\(settingsManager.trustedContacts.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Contacts")
                }
                
                // Trigger Settings
                Section {
                    Toggle(isOn: $settingsManager.enableShakeTrigger) {
                        HStack {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .foregroundColor(.orange)
                            Text("Shake Trigger")
                        }
                    }
                    
                    Toggle(isOn: $settingsManager.enableVolumeButtonTrigger) {
                        HStack {
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundColor(.purple)
                            Text("Volume Button Trigger")
                        }
                    }
                    
                    if settingsManager.enableVolumeButtonTrigger {
                        Stepper(value: $settingsManager.volumeButtonPressCount, in: 3...10) {
                            Text("Press \(settingsManager.volumeButtonPressCount) times")
                        }
                    }
                } header: {
                    Text("Discrete Triggers")
                } footer: {
                    Text("Alternative ways to trigger an emergency alert")
                }
                
                // Escalation Settings
                Section {
                    Stepper(value: $settingsManager.cancelWindowSeconds, in: 10...120, step: 10) {
                        Text("Cancel window: \(settingsManager.cancelWindowSeconds)s")
                    }
                    
                    Stepper(value: $settingsManager.autoEscalateSeconds, in: 30...300, step: 30) {
                        Text("Auto-escalate: \(settingsManager.autoEscalateSeconds)s")
                    }
                    
                    Toggle(isOn: $settingsManager.enableNearbyResponders) {
                        HStack {
                            Image(systemName: "person.wave.2.fill")
                                .foregroundColor(.teal)
                            Text("Nearby Responders")
                        }
                    }
                } header: {
                    Text("Escalation")
                } footer: {
                    Text("Nearby responders are other Ailert users who have opted in to help others")
                }
                
                // Recording Settings
                Section {
                    Toggle(isOn: $settingsManager.autoRecordVideo) {
                        HStack {
                            Image(systemName: "video.fill")
                                .foregroundColor(.red)
                            Text("Auto-Record Video")
                        }
                    }
                    
                    Picker("Default Camera", selection: $settingsManager.defaultCamera) {
                        Text("Back").tag(CameraPosition.back)
                        Text("Front").tag(CameraPosition.front)
                    }
                } header: {
                    Text("Recording")
                }
                
                // AI Coordinator
                Section {
                    Toggle(isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "llmCoordinatorEnabled") },
                        set: { UserDefaults.standard.set($0, forKey: "llmCoordinatorEnabled") }
                    )) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.purple)
                            Text("AI Coordinator")
                        }
                    }
                    
                    NavigationLink {
                        APIKeySetupView()
                    } label: {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.orange)
                            Text("OpenAI API Key")
                            Spacer()
                            if UserDefaults.standard.string(forKey: "openai_api_key")?.isEmpty == false {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Text("Not Set")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("AI Coordinator")
                } footer: {
                    Text("AI analyzes your situation during emergencies and can automatically share location, notify contacts, or recommend calling 911 based on confidence level")
                }
                
                // Security
                Section {
                    NavigationLink {
                        PINSetupView()
                    } label: {
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.gray)
                            Text("Cancel & Duress PINs")
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Set up a cancel PIN and a separate duress PIN that silently alerts contacts")
                }
                
                // Privacy
                Section {
                    Toggle(isOn: $settingsManager.shareLocationWithContacts) {
                        Text("Share Location with Contacts")
                    }
                    
                    if settingsManager.shareLocationWithContacts {
                        Toggle(isOn: $settingsManager.sharePreciseLocation) {
                            Text("Share Precise Location")
                        }
                    }
                    
                    Toggle(isOn: $settingsManager.shareMediaWithContacts) {
                        Text("Share Media with Contacts")
                    }

                    Toggle(isOn: $settingsManager.shareLiveTrackerWithContacts) {
                        Text("Share Live Tracker with Contacts")
                    }

                    if settingsManager.shareLiveTrackerWithContacts {
                        Toggle(isOn: $settingsManager.autoNotifyContactsOnLiveShare) {
                            Text("Auto-Notify Contacts on Live Share")
                        }

                        Toggle(isOn: $settingsManager.includeLiveMediaMetadata) {
                            Text("Include Live Media Status")
                        }
                    }
                } header: {
                    Text("Privacy")
                }
                
                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/ailert/ailert-ios")!) {
                        HStack {
                            Text("Open Source")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                settingsManager.saveTriggerSettings()
                settingsManager.saveEscalationSettings()
                settingsManager.saveRecordingSettings()
                settingsManager.savePrivacySettings()
            }
        }
    }
}

// MARK: - Emergency Profile Editor

struct EmergencyProfileEditor: View {
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        Form {
            Section("Personal") {
                TextField("Full Name", text: $settingsManager.emergencyProfile.fullName)
                
                DatePicker("Date of Birth", 
                          selection: Binding(
                            get: { settingsManager.emergencyProfile.dateOfBirth ?? Date() },
                            set: { settingsManager.emergencyProfile.dateOfBirth = $0 }
                          ),
                          displayedComponents: .date)
                
                Picker("Blood Type", selection: $settingsManager.emergencyProfile.bloodType) {
                    Text("Not Set").tag(nil as BloodType?)
                    ForEach(BloodType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as BloodType?)
                    }
                }
            }
            
            Section("Medical") {
                NavigationLink {
                    ListEditor(title: "Allergies", items: $settingsManager.emergencyProfile.allergies)
                } label: {
                    HStack {
                        Text("Allergies")
                        Spacer()
                        Text("\(settingsManager.emergencyProfile.allergies.count)")
                            .foregroundColor(.secondary)
                    }
                }
                
                NavigationLink {
                    ListEditor(title: "Medications", items: $settingsManager.emergencyProfile.medications)
                } label: {
                    HStack {
                        Text("Medications")
                        Spacer()
                        Text("\(settingsManager.emergencyProfile.medications.count)")
                            .foregroundColor(.secondary)
                    }
                }
                
                NavigationLink {
                    ListEditor(title: "Medical Conditions", items: $settingsManager.emergencyProfile.medicalConditions)
                } label: {
                    HStack {
                        Text("Medical Conditions")
                        Spacer()
                        Text("\(settingsManager.emergencyProfile.medicalConditions.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Notes") {
                TextEditor(text: Binding(
                    get: { settingsManager.emergencyProfile.emergencyNotes ?? "" },
                    set: { settingsManager.emergencyProfile.emergencyNotes = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 100)
            }
        }
        .navigationTitle("Emergency Profile")
        .onDisappear {
            settingsManager.saveEmergencyProfile()
        }
    }
}

// MARK: - List Editor

struct ListEditor: View {
    let title: String
    @Binding var items: [String]
    @State private var newItem = ""
    
    var body: some View {
        List {
            Section {
                ForEach(items, id: \.self) { item in
                    Text(item)
                }
                .onDelete { indexSet in
                    items.remove(atOffsets: indexSet)
                }
            }
            
            Section {
                HStack {
                    TextField("Add \(title.lowercased().dropLast())", text: $newItem)
                    
                    Button {
                        if !newItem.isEmpty {
                            items.append(newItem)
                            newItem = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(newItem.isEmpty)
                }
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Trusted Contacts View

struct TrustedContactsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showAddContact = false
    
    var body: some View {
        List {
            ForEach(settingsManager.trustedContacts) { contact in
                NavigationLink {
                    ContactEditor(contact: contact)
                } label: {
                    HStack {
                        Text(contact.name)
                        Spacer()
                        Text(contact.phone)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    settingsManager.removeContact(settingsManager.trustedContacts[index])
                }
            }
            .onMove { from, to in
                settingsManager.reorderContacts(from: from, to: to)
            }
        }
        .navigationTitle("Trusted Contacts")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddContact = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddContact) {
            ContactEditor(contact: nil)
        }
    }
}

// MARK: - Contact Editor

struct ContactEditor: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    
    let contact: TrustedContact?
    
    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""
    @State private var notifySMS = true
    @State private var notifyCall = false
    @State private var showContactPicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Import from Contacts button (only for new contacts)
                if contact == nil {
                    Section {
                        Button {
                            showContactPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundColor(.blue)
                                Text("Import from Contacts")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    } footer: {
                        Text("Select a contact from your phone to auto-fill")
                    }
                }
                
                Section {
                    TextField("Name", text: $name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Relationship", text: $relationship)
                }
                
                Section("Notification Method") {
                    Toggle("SMS", isOn: $notifySMS)
                    Toggle("Phone Call", isOn: $notifyCall)
                }
            }
            .navigationTitle(contact == nil ? "Add Contact" : "Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveContact()
                        dismiss()
                    }
                    .disabled(name.isEmpty || phone.isEmpty)
                }
            }
            .onAppear {
                if let contact = contact {
                    name = contact.name
                    phone = contact.phone
                    relationship = contact.relationship
                    notifySMS = contact.notifyVia.contains(.sms)
                    notifyCall = contact.notifyVia.contains(.call)
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerView { selectedName, selectedPhone in
                    name = selectedName
                    phone = selectedPhone
                }
            }
        }
    }
    
    private func saveContact() {
        var methods: Set<NotificationMethod> = []
        if notifySMS { methods.insert(.sms) }
        if notifyCall { methods.insert(.call) }
        
        if let existing = contact {
            var updated = existing
            updated.name = name
            updated.phone = phone
            updated.relationship = relationship
            updated.notifyVia = methods
            settingsManager.updateContact(updated)
        } else {
            let newContact = TrustedContact(
                name: name,
                phone: phone,
                relationship: relationship,
                priority: settingsManager.trustedContacts.count + 1,
                notifyVia: methods
            )
            settingsManager.addContact(newContact)
        }
    }
}

// MARK: - PIN Setup View

struct PINSetupView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var cancelPIN = ""
    @State private var duressPIN = ""
    
    var body: some View {
        Form {
            Section {
                SecureField("Cancel PIN", text: $cancelPIN)
                    .keyboardType(.numberPad)
            } header: {
                Text("Cancel PIN")
            } footer: {
                Text("Enter this PIN to safely cancel an emergency")
            }
            
            Section {
                SecureField("Duress PIN", text: $duressPIN)
                    .keyboardType(.numberPad)
            } header: {
                Text("Duress PIN")
            } footer: {
                Text("If someone forces you to cancel, use this PIN. It will appear to cancel but silently alert your contacts.")
            }
        }
        .navigationTitle("Security PINs")
        .onAppear {
            cancelPIN = settingsManager.cancelPIN
            duressPIN = settingsManager.duressPIN
        }
        .onDisappear {
            settingsManager.cancelPIN = cancelPIN
            settingsManager.duressPIN = duressPIN
            settingsManager.savePINs()
        }
    }
}

// MARK: - API Key Setup View

struct APIKeySetupView: View {
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                HStack {
                    if showKey {
                        TextField("sk-proj-...", text: $apiKey)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("sk-proj-...", text: $apiKey)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Your key is stored securely on this device only. Get your key from platform.openai.com")
            }
            
            Section {
                Button {
                    UserDefaults.standard.set(apiKey, forKey: "openai_api_key")
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if saved {
                            Label("Saved!", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Text("Save API Key")
                        }
                        Spacer()
                    }
                }
                .disabled(apiKey.isEmpty)
                
                if !apiKey.isEmpty {
                    Button(role: .destructive) {
                        apiKey = ""
                        UserDefaults.standard.removeObject(forKey: "openai_api_key")
                    } label: {
                        HStack {
                            Spacer()
                            Text("Clear API Key")
                            Spacer()
                        }
                    }
                }
            }
            
            Section {
                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("Get API Key from OpenAI")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("API Key")
        .onAppear {
            apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}
