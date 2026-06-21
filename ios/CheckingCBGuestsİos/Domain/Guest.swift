import Foundation

/// Misafir veri modeli.
struct Guest: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var eventId: String
    var name: String
    var title: String
    var arrivalMethod: ArrivalMethod
    var plate: String?
    var model: String?
    var securityCheck: Bool
    var status: GuestStatus
    var entryTime: String?
    var exitTime: String?
    var photoUri: String?
    var deletedAt: String?
    var isRedListPending: Bool
    var note: String?
    var expectedTime: String?
    var sectionTitle: String?
    var participationCategory: ParticipationCategory?

    init(
        id: String = UUID().uuidString,
        eventId: String,
        name: String,
        title: String,
        arrivalMethod: ArrivalMethod,
        plate: String? = nil,
        model: String? = nil,
        securityCheck: Bool = true,
        status: GuestStatus = .pending,
        entryTime: String? = nil,
        exitTime: String? = nil,
        photoUri: String? = nil,
        deletedAt: String? = nil,
        isRedListPending: Bool = false,
        note: String? = nil,
        expectedTime: String? = nil,
        sectionTitle: String? = nil,
        participationCategory: ParticipationCategory? = nil
    ) {
        self.id = id
        self.eventId = eventId
        self.name = name
        self.title = title
        self.arrivalMethod = arrivalMethod
        self.plate = plate
        self.model = model
        self.securityCheck = securityCheck
        self.status = status
        self.entryTime = entryTime
        self.exitTime = exitTime
        self.photoUri = photoUri
        self.deletedAt = deletedAt
        self.isRedListPending = isRedListPending
        self.note = note
        self.expectedTime = expectedTime
        self.sectionTitle = sectionTitle
        self.participationCategory = participationCategory
    }

    var isDeleted: Bool { deletedAt != nil }

    var hasEntered: Bool { entryTime != nil && status == .checkedIn }

    var hasExited: Bool { exitTime != nil && status == .exited }

    var isInside: Bool { hasEntered && !hasExited }

    /// Araçla gelen misafirlerde plaka zorunluluğunu doğrular.
    func validateVehicleFields() -> Bool {
        switch arrivalMethod {
        case .vehicle:
            guard let plate else { return false }
            return !plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .pedestrian:
            return true
        }
    }

    /// Misafir listesinde gösterilecek geliş etiketi (araçlıysa plaka; Android `GuestCard`).
    var listArrivalLabel: String {
        switch arrivalMethod {
        case .pedestrian:
            return arrivalMethod.displayName
        case .vehicle:
            let trimmed = plate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Araçlı Giriş" : trimmed
        }
    }
}

// MARK: - Preview

extension Guest {
    static var previewPending: Guest {
        Guest(
            id: "preview-guest-pending",
            eventId: Event.previewActive.id,
            name: "Ahmet Yılmaz",
            title: "Büyükelçi",
            arrivalMethod: .pedestrian,
            status: .pending,
            sectionTitle: "Türk Heyeti",
            participationCategory: .protokolDavetli
        )
    }

    static var previewCheckedIn: Guest {
        Guest(
            id: "preview-guest-checked-in",
            eventId: Event.previewActive.id,
            name: "Ayşe Demir",
            title: "Protokol Sorumlusu",
            arrivalMethod: .vehicle,
            plate: "06 ABC 123",
            model: "Mercedes-Benz S-Class",
            status: .checkedIn,
            entryTime: "2026-06-15T18:05:00Z",
            participationCategory: .protokolDavetli
        )
    }

    static var previewPendingApproval: Guest {
        Guest(
            id: "preview-guest-approval",
            eventId: Event.previewActive.id,
            name: "Mehmet Özkan",
            title: "Misafir",
            arrivalMethod: .pedestrian,
            status: .pendingApproval,
            isRedListPending: true,
            note: "Kırmızı liste kontrolü gerekli"
        )
    }

    static var previewList: [Guest] {
        [previewPending, previewCheckedIn, previewPendingApproval]
    }
}
