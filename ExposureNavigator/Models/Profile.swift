import Foundation

enum ProfileSource: String, Codable, CaseIterable { case manual, synthetic }
enum ProfileRelationship: String, Codable, CaseIterable, Identifiable {
    case myself, child, careRecipient, other
    var id: String { rawValue }
    var label: String { switch self { case .myself: "Myself"; case .child: "My child"; case .careRecipient: "Someone I care for"; case .other: "Other" } }
}
enum AgeCategory: String, Codable {
    case child, adult, olderAdult, unknown
    var label: String { switch self { case .child: "Under 18"; case .adult: "18–64"; case .olderAdult: "65+"; case .unknown: "Age not provided" } }
    static func from(age: Int?) -> Self { guard let age, (0...120).contains(age) else { return .unknown }; return age < 18 ? .child : (age < 65 ? .adult : .olderAdult) }
}

struct UserProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var relationship: ProfileRelationship
    var age: Int?
    var homeZipCode: String?
    var medicalConditions: [String] = []
    var mentalConditions: [String] = []
    var medications: [String] = []
    var source: ProfileSource = .manual
    var createdAt = Date()
    var updatedAt = Date()

    var ageCategory: AgeCategory { .from(age: age) }
    var hasHealthContext: Bool { !medicalConditions.isEmpty || !mentalConditions.isEmpty || !medications.isEmpty }

    init(id: UUID = UUID(), name: String, relationship: ProfileRelationship, age: Int? = nil, homeZipCode: String? = nil, medicalConditions: [String] = [], mentalConditions: [String] = [], medications: [String] = [], source: ProfileSource = .manual, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id=id; self.name=name; self.relationship=relationship; self.age=age; self.homeZipCode=homeZipCode; self.medicalConditions=medicalConditions; self.mentalConditions=mentalConditions; self.medications=medications; self.source=source; self.createdAt=createdAt; self.updatedAt=updatedAt
    }

    enum CodingKeys: String, CodingKey { case id,name,relationship,age,homeZipCode,medicalConditions,mentalConditions,medications,healthConsiderations,source,createdAt,updatedAt }
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy: CodingKeys.self)
        id=try c.decodeIfPresent(UUID.self,forKey:.id) ?? UUID(); name=try c.decode(String.self,forKey:.name); relationship=try c.decode(ProfileRelationship.self,forKey:.relationship); age=try c.decodeIfPresent(Int.self,forKey:.age); homeZipCode=try c.decodeIfPresent(String.self,forKey:.homeZipCode)
        medicalConditions=try c.decodeIfPresent([String].self,forKey:.medicalConditions) ?? (try c.decodeIfPresent([HealthCondition].self,forKey:.healthConsiderations)?.map(\.label) ?? [])
        mentalConditions=try c.decodeIfPresent([String].self,forKey:.mentalConditions) ?? []; medications=try c.decodeIfPresent([String].self,forKey:.medications) ?? []; source=try c.decodeIfPresent(ProfileSource.self,forKey:.source) ?? .manual; createdAt=try c.decodeIfPresent(Date.self,forKey:.createdAt) ?? Date(); updatedAt=try c.decodeIfPresent(Date.self,forKey:.updatedAt) ?? Date()
    }
}
