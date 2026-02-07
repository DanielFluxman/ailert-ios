// EmergencyProfile.swift
// User's medical and emergency information

import Foundation

struct EmergencyProfile: Codable {
    var fullName: String
    var dateOfBirth: Date?
    var bloodType: BloodType?
    var allergies: [String]
    var medications: [String]
    var medicalConditions: [String]
    var emergencyNotes: String?
    var organDonor: Bool?
    var primaryLanguage: String?
    
    init() {
        self.fullName = ""
        self.dateOfBirth = nil
        self.bloodType = nil
        self.allergies = []
        self.medications = []
        self.medicalConditions = []
        self.emergencyNotes = nil
        self.organDonor = nil
        self.primaryLanguage = nil
    }
    
    var isEmpty: Bool {
        fullName.isEmpty && 
        dateOfBirth == nil && 
        bloodType == nil && 
        allergies.isEmpty && 
        medications.isEmpty && 
        medicalConditions.isEmpty
    }
    
    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: dob, to: Date())
        return components.year
    }
}

enum BloodType: String, Codable, CaseIterable {
    case aPositive = "A+"
    case aNegative = "A-"
    case bPositive = "B+"
    case bNegative = "B-"
    case abPositive = "AB+"
    case abNegative = "AB-"
    case oPositive = "O+"
    case oNegative = "O-"
    case unknown = "Unknown"
}
