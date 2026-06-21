import Foundation
import Observation
import os.log

/// CRUD işlemleri sonrası otomatik senkronizasyon yöneticisi (Android `AutoSyncManager` eşleniği).
///
/// Android'deki `StateFlow` + `Mutex` + `AtomicReference` yapısı, iOS'ta `@MainActor`
/// izolasyonu ile sadeleştirilmiştir: tüm durum tek aktörde olduğundan ayrı kilit gerekmez.
/// Özellikler: debounce (art arda istekleri tek sync'te toplama), ağ hatalarında üstel
/// geri çekilmeli retry, reaktif `syncState`.
@MainActor
@Observable
final class AutoSyncManager {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "AutoSyncManager")

    private static let debounceDelayNanos: UInt64 = 2_000_000_000
    private static let initialRetryDelayNanos: UInt64 = 4_000_000_000
    private static let maxRetryDelayNanos: UInt64 = 25_000_000_000
    private static let retryBackoffMultiplier = 2.0
    private static let maxRetryCount = 3

    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncResult: SyncResult?

    private let syncRepository: any SyncRepository
    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var isSyncing = false
    private var retryCount = 0

    init(syncRepository: any SyncRepository) {
        self.syncRepository = syncRepository
    }

    // MARK: - Public API

    /// Debounce'lu sync isteği. Art arda çağrılar tek sync'te toplanır.
    func requestSync() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceDelayNanos)
            guard !Task.isCancelled else { return }
            await self?.performSync()
        }
    }

    /// Anında sync (debounce'suz). Devam eden sync varsa zorla sıfırlar.
    @discardableResult
    func syncImmediately() async -> SyncResult {
        debounceTask?.cancel()
        if isSyncing {
            Self.logger.warning("Sync already in progress, forcing reset")
            isSyncing = false
            syncState = .idle
            lastSyncResult = nil
        }
        return await performSync()
    }

    func cleanup() {
        debounceTask?.cancel()
        retryTask?.cancel()
        debounceTask = nil
        retryTask = nil
        isSyncing = false
        retryCount = 0
        syncState = .idle
        lastSyncResult = nil
    }

    // MARK: - Core

    @discardableResult
    private func performSync() async -> SyncResult {
        guard !isSyncing else {
            return .error(SyncError.syncInProgress)
        }
        isSyncing = true
        syncState = .syncing
        defer { isSyncing = false }

        let result = await syncRepository.syncWithFirebase()
        lastSyncResult = result
        syncState = result.state
        handleSyncResult(result)
        return result
    }

    private func handleSyncResult(_ result: SyncResult) {
        switch result.state {
        case .success, .conflict:
            retryCount = 0
        case .error:
            if case .networkError = result.error {
                scheduleRetry()
            } else {
                retryCount = 0
            }
        case .idle, .syncing:
            break
        }
    }

    private func scheduleRetry() {
        retryCount += 1
        guard retryCount <= Self.maxRetryCount else {
            retryCount = 0
            return
        }

        let backoff = Double(Self.initialRetryDelayNanos) * pow(Self.retryBackoffMultiplier, Double(retryCount - 1))
        let delay = min(UInt64(backoff), Self.maxRetryDelayNanos)

        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.performSync()
        }
    }
}
