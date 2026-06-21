import Foundation

/// Kırmızı listede bulunan misafir.
struct RedListMember: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let guestId: String
    /// Cache için — guest değişirse güncellenmeli.
    let guestName: String
    let reason: RedListEntryReason
    /// ISO 8601 (ör. `2024-10-15T14:30:00`)
    let addedDate: String
    let addedBy: String?
    let notes: String?
    let requiresSpecialPermission: Bool
    /// Soft delete için.
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case guestId
        case guestName
        case reason
        case addedDate
        case addedAt
        case addedBy
        case notes
        case requiresSpecialPermission
        case isActive
    }

    init(
        id: String = UUID().uuidString,
        guestId: String,
        guestName: String,
        reason: RedListEntryReason,
        addedDate: String,
        addedBy: String? = nil,
        notes: String? = nil,
        requiresSpecialPermission: Bool = true,
        isActive: Bool = true
    ) {
        self.id = id
        self.guestId = guestId
        self.guestName = guestName
        self.reason = reason
        self.addedDate = addedDate
        self.addedBy = addedBy
        self.notes = notes
        self.requiresSpecialPermission = requiresSpecialPermission
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        guestId = try container.decode(String.self, forKey: .guestId)
        guestName = try container.decode(String.self, forKey: .guestName)
        reason = try container.decode(RedListEntryReason.self, forKey: .reason)
        if let date = try container.decodeIfPresent(String.self, forKey: .addedDate), !date.isEmpty {
            addedDate = date
        } else if let at = try container.decodeIfPresent(String.self, forKey: .addedAt), !at.isEmpty {
            addedDate = at
        } else {
            addedDate = ISO8601DateFormatter().string(from: Date())
        }
        addedBy = try container.decodeIfPresent(String.self, forKey: .addedBy)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        requiresSpecialPermission = try container.decodeIfPresent(Bool.self, forKey: .requiresSpecialPermission) ?? true
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(guestId, forKey: .guestId)
        try container.encode(guestName, forKey: .guestName)
        try container.encode(reason, forKey: .reason)
        try container.encode(addedDate, forKey: .addedDate)
        try container.encode(addedDate, forKey: .addedAt)
        try container.encodeIfPresent(addedBy, forKey: .addedBy)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(requiresSpecialPermission, forKey: .requiresSpecialPermission)
        try container.encode(isActive, forKey: .isActive)
    }
}

// MARK: - Preview

extension RedListMember {
    static var previewVIP: RedListMember {
        RedListMember(
            id: "preview-redlist-vip",
            guestId: Guest.previewCheckedIn.id,
            guestName: "AYŞE DEMİR",
            reason: .vip,
            addedDate: "2024-10-15T14:30:00",
            addedBy: "admin@checkingcbguests",
            notes: "Protokol önceliği",
            requiresSpecialPermission: true,
            isActive: true
        )
    }

    static var previewSecurity: RedListMember {
        RedListMember(
            id: "preview-redlist-security",
            guestId: "manual-synced-entry",
            guestName: "MEHMET ÖZKAN",
            reason: .security,
            addedDate: "2025-01-20T09:15:00",
            notes: "Manuel ekleme",
            isActive: true
        )
    }

    static var previewList: [RedListMember] {
        [previewVIP, previewSecurity]
    }
}
