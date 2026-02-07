// ContactPickerView.swift
// SwiftUI wrapper for CNContactPickerViewController

import SwiftUI
import ContactsUI

struct ContactPickerView: UIViewControllerRepresentable {
    let onSelectContact: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }
    
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerView
        
        init(_ parent: ContactPickerView) {
            self.parent = parent
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            
            // Get the first phone number
            var phone = ""
            if let phoneNumber = contact.phoneNumbers.first?.value.stringValue {
                // Clean up phone number - remove spaces and special characters except +
                phone = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if phoneNumber.hasPrefix("+") {
                    phone = "+" + phone
                }
            }
            
            parent.onSelectContact(name, phone)
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            // User cancelled
        }
    }
}

#Preview {
    Text("Contact Picker Preview")
        .sheet(isPresented: .constant(true)) {
            ContactPickerView { name, phone in
                print("Selected: \(name) - \(phone)")
            }
        }
}
