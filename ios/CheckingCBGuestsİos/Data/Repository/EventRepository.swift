import Foundation

// MARK: - EventRepository

/// Etkinlik ve misafir verileri için repository sözleşmesi.
///
/// Online-first mimaride Firestore tek kaynak kabul edilir (Android ile aynı).
///
/// **İş parçacığı beklentileri**
/// - `AsyncStream` dönen metodlar: Firestore snapshot dinleyicilerinden beslenir;
///   implementasyonlar callback’leri arka planda alıp `yield` edebilir. UI tüketimi
///   `@MainActor` ViewModel’de `for await` ile yapılmalıdır.
/// - `async` okuma / yazma metodları: Ağ ve disk I/O içerir; belirli bir Actor’a
///   bağlı değildir — implementasyon `nonisolated` veya dahili bir `actor` kullanabilir.
/// - Çağıran katman hata yönetimini `RepoResult` veya boş dönüşlerle yapar;
///   ağ hataları implementasyonda loglanıp uygun sonuç tipine çevrilmelidir.
protocol EventRepository: Sendable {

    // MARK: AsyncStream — reaktif veri

    /// Tüm silinmemiş etkinlikleri dinler.
    func allEvents() -> AsyncStream<[Event]>

    /// Tüm silinmemiş misafirleri dinler.
    func allGuests() -> AsyncStream<[Guest]>

    /// Etkinliğe ait misafirler (kırmızı liste bekleyenler hariç).
    /// Admin cihazlarda `guests` + `guests_secure` birleştirilir.
    func guests(byEventId eventId: String) -> AsyncStream<[Guest]>

    /// Onay bekleyen (kırmızı liste) misafirler.
    func pendingRedListGuests(eventId: String) -> AsyncStream<[Guest]>

    // MARK: async — tek seferlik okuma

    func allGuestsList() async -> [Guest]
    func event(byId eventId: String) async -> Event?
    func guest(byId id: String) async -> Guest?
    func guest(eventId: String, guestId: String) async -> Guest?
    func eventIncludingDeleted(byId eventId: String) async -> Event?
    func guestIncludingDeleted(byId guestId: String) async -> Guest?
    func allEventsIncludingDeleted() async -> [Event]
    func allGuestsByEventIdIncludingDeleted(eventId: String) async -> [Guest]

    // MARK: Bulut senkronizasyonu

    func fetchGuestsFromRemote(eventId: String, isAdminDevice: Bool) async -> [Guest]
    func uploadGuestToRemote(_ guest: Guest) async

    // MARK: Yazma — Event

    func insertEvent(_ event: Event) async
    func updateEvent(_ event: Event) async
    func deleteEvent(eventId: String) async
    func deleteGuestsByEventId(eventId: String) async
    func deleteEventsBatch(eventIds: [String]) async -> BatchDeleteResult

    // MARK: Yazma — Guest

    func insertGuest(_ guest: Guest) async
    func insertGuestLocally(_ guest: Guest) async
    func insertGuests(_ guests: [Guest]) async
    func updateGuest(_ guest: Guest) async
    func updateGuests(_ guests: [Guest]) async
    func deleteGuest(guestId: String, eventId: String?) async
    func deleteGuestsBatch(guestIds: [String]) async -> BatchDeleteResult

    // MARK: Özel işlemler

    func approveGuest(_ guest: Guest) async -> RepoResult<Void>
}
