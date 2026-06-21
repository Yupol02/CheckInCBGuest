import Foundation

/// Etkinlik veri modeli.
struct Event: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let date: String
    let location: String
    let startTime: String
    let status: EventStatus
    let deletedAt: String?
    let participatedCount: Int
    let totalGuestCount: Int

    init(
        id: String = UUID().uuidString,
        title: String,
        date: String,
        location: String,
        startTime: String,
        status: EventStatus,
        deletedAt: String? = nil,
        participatedCount: Int = 0,
        totalGuestCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.location = location
        self.startTime = startTime
        self.status = status
        self.deletedAt = deletedAt
        self.participatedCount = participatedCount
        self.totalGuestCount = totalGuestCount
    }

    /// Etkinlik silinmiş mi?
    var isDeleted: Bool { deletedAt != nil }

    /// Silinmemiş ve durumu aktif mi?
    var isActive: Bool { computedStatus == .active && !isDeleted }

    /// Tarihe göre güncel durum (Firestore `status` alanından bağımsız; Android `EventCard` ile aynı).
    var computedStatus: EventStatus {
        guard let eventDay = parsedEventDay else { return status }
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        if eventDay < today { return .past }
        if eventDay == today { return .active }
        return .upcoming
    }

    /// Etkinlik tarihi geçmiş mi? Tarih formatı: `d MMMM yyyy` (ör. `25 Ocak 2025`, `tr_TR`).
    var isExpired: Bool {
        guard let eventDay = parsedEventDay else { return false }
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        return eventDay < today
    }

    private var parsedEventDay: Date? {
        guard let eventDate = Self.turkishDateFormatter.date(from: date) else { return nil }
        return Calendar(identifier: .gregorian).startOfDay(for: eventDate)
    }

    private static let turkishDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()
}

// MARK: - Preview

extension Event {
    static var previewActive: Event {
        Event(
            id: "preview-event-active",
            title: "Cumhurbaşkanlığı Resepsiyonu",
            date: "15 Haziran 2026",
            location: "Beştepe Millet Kongre ve Kültür Merkezi",
            startTime: "19:00",
            status: .active,
            participatedCount: 42,
            totalGuestCount: 120
        )
    }

    static var previewUpcoming: Event {
        Event(
            id: "preview-event-upcoming",
            title: "Protokol Yemeği",
            date: "20 Temmuz 2026",
            location: "Ankara",
            startTime: "20:30",
            status: .upcoming
        )
    }

    static var previewPast: Event {
        Event(
            id: "preview-event-past",
            title: "Geçmiş Etkinlik",
            date: "1 Ocak 2020",
            location: "İstanbul",
            startTime: "18:00",
            status: .past,
            participatedCount: 80,
            totalGuestCount: 80
        )
    }

    static var previewList: [Event] {
        [previewActive, previewUpcoming, previewPast]
    }
}
