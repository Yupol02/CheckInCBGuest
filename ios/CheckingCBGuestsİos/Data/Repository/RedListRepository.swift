import Foundation

// MARK: - RedListRepository

/// Kırmızı liste (VIP / güvenlik) işlemleri sözleşmesi.
///
/// **İş parçacığı beklentileri**
/// - `AsyncStream` metodları: Firestore dinleyicilerinden beslenir; UI `@MainActor`’da tüketilir.
/// - `async` metodlar: Ağ / önbellek I/O; `RedListResult` ile iş kuralı hataları açık döner.
/// - İsim eşlemesi için `normalizeGuestName` → `String.normalizeGuestName()` (Firestore doküman ID).
protocol RedListRepository: Sendable {

    func fetchRedListDirectlyFromCloud() async -> Set<String>

    func allRedListMembers(isAdmin: Bool) -> AsyncStream<[RedListMember]>
    func getAllActiveRedListNames() async -> Set<String>
    func forceUpdateFromFirebase() async
    func getAdminRedListMember(byName guestName: String) async -> RedListMember?
    func getActiveRedListMember(byName guestName: String) async -> RedListMember?
    func allRedListGuestIds() -> AsyncStream<Set<String>>
    func adminRedListGuestIds() -> AsyncStream<Set<String>>
    func hiddenRedListGuestIds() -> AsyncStream<Set<String>>
    func getRedListMember(byGuestId guestId: String) async -> RedListMember?
    func areGuestsInRedList(guestIds: [String]) async -> [String: Bool]

    func addToRedList(
        guestId: String,
        reason: RedListEntryReason,
        notes: String?,
        addedBy: String?
    ) async -> RedListResult<RedListMember>

    func addManuallyToRedList(
        guestName: String,
        reason: RedListEntryReason,
        notes: String?,
        addedBy: String?
    ) async -> RedListResult<RedListMember>

    /// Firestore doküman anahtarı ile uyumlu isim normalizasyonu.
    func normalizeGuestName(_ guestName: String) -> String

    func removeFromRedList(guestId: String) async -> RedListResult<Void>
    func removeFromRedList(byMemberId memberId: String) async -> RedListResult<Void>
    func searchRedListMembers(query: String) -> AsyncStream<[RedListMember]>
    func updateGuestNameInRedList(guestId: String, newName: String) async
    func linkManualEntryToRealGuest(
        guestName: String,
        realGuestId: String,
        realGuestName: String
    ) async -> Bool
}

// MARK: - Varsayılan normalizasyon

extension RedListRepository {
    /// Android `RedListRepository.normalizeGuestName` varsayılan uygulaması.
    func normalizeGuestName(_ guestName: String) -> String {
        guestName.normalizeGuestName()
    }
}

extension RedListRepository {
    /// Android `getAllRedListMembers(isAdmin = true)` varsayılanı.
    func allRedListMembers() -> AsyncStream<[RedListMember]> {
        allRedListMembers(isAdmin: true)
    }

    func addToRedList(
        guestId: String,
        reason: RedListEntryReason
    ) async -> RedListResult<RedListMember> {
        await addToRedList(guestId: guestId, reason: reason, notes: nil, addedBy: nil)
    }

    func addManuallyToRedList(
        guestName: String,
        reason: RedListEntryReason
    ) async -> RedListResult<RedListMember> {
        await addManuallyToRedList(guestName: guestName, reason: reason, notes: nil, addedBy: nil)
    }
}
