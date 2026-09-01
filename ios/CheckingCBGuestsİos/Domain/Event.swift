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

    /// Firestore'daki `eventDayKey` alanı — sunucu tarafı görünürlük kısıtının anahtarı.
    ///
    /// `date` alanı Türkçe metindir ("25 Ocak 2025"); güvenlik kuralları bu biçimi
    /// ayrıştıramaz. Bu yüzden aynı gün, sıralanabilir bir tam sayı olarak (20250125)
    /// ayrıca yazılır ve hem sorgu (`whereField >=`) hem kural bu alandan okur.
    ///
    /// Tarih ayrıştırılamazsa `computedStatus` ile AYNI geri düşüş uygulanır: kayıt
    /// "geçmiş" değilse görünür kalır. Aksi hâlde tarihi bozuk tek bir kayıt, yönetici
    /// olmayan tüm cihazlarda sessizce kaybolurdu.
    var dayKey: Int {
        guard let eventDay = parsedEventDay else {
            return status == .past ? Self.oldestDayKey : Self.unknownDateDayKey
        }
        return Self.dayKey(for: eventDay)
    }

    /// Tarihi ayrıştırılamayan kayıtlar için üst sınır — her zaman görünür kalır.
    static let unknownDateDayKey = 99_999_999
    /// Tarihi ayrıştırılamayan ama "geçmiş" işaretli kayıtlar için alt sınır.
    static let oldestDayKey = 0

    /// Firestore alan adı; sorgu ve kural aynı ismi kullanır.
    static let dayKeyField = "eventDayKey"

    /// Cihazın bugünü — yönetici olmayan sorgunun alt sınırı.
    ///
    /// `computedStatus`/`isExpired` ile aynı takvimi kullanır ki "bugün hâlâ görünür"
    /// kuralı arayüz ve sorgu tarafında ayrışmasın.
    static func todayDayKey() -> Int {
        dayKey(for: Calendar(identifier: .gregorian).startOfDay(for: Date()))
    }

    static func dayKey(for date: Date) -> Int {
        let components = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return unknownDateDayKey }
        return year * 10_000 + month * 100 + day
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
