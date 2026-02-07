// TrustedContact.swift
// Model for emergency contacts

import Foundation

struct TrustedContact: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var phone: String
    var relationship: String
    var priority: Int  // 1 = first to contact
    var notifyVia: Set<NotificationMethod>
    var isEnabled: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        phone: String,
        relationship: String = "",
        priority: Int = 1,
        notifyVia: Set<NotificationMethod> = [.sms],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.relationship = relationship
        self.priority = priority
        self.notifyVia = notifyVia
        self.isEnabled = isEnabled
    }
}

enum NotificationMethod: String, Codable, CaseIterable {
    case sms
    case call
    case pushNotification
    
    var displayName: String {
        switch self {
        case .sms: return "SMS"
        case .call: return "Phone Call"
        case .pushNotification: return "Push Notification"
        }
    }
    
    var icon: String {
        switch self {
        case .sms: return "message.fill"
        case .call: return "phone.fill"
        case .pushNotification: return "bell.fill"
        }
    }
}
