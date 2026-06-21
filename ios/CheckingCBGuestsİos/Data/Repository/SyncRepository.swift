import Foundation

/// Çevrimdışı / çevrimiçi veri senkronizasyonu (Android `SyncRepository`).
protocol SyncRepository: Sendable {
    /// Firebase ile tam senkronizasyon (Android `syncWithFirebase`).
    func syncWithFirebase() async -> SyncResult

    /// Yerel değişiklikleri uzak sunucuya gönderir.
    func pushLocalChanges() async -> SyncResult

    /// Uzak değişiklikleri çeker; `isAdmin` güvenli misafir koleksiyonları için.
    func pullRemoteChanges(isAdmin: Bool) async -> SyncResult
}

extension SyncRepository {
    func pullRemoteChanges() async -> SyncResult {
        await pullRemoteChanges(isAdmin: false)
    }
}
