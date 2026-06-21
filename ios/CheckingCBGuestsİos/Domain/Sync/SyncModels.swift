import Foundation

// MARK: - Sync state

enum SyncState: String, Equatable, Sendable, CaseIterable {
    case idle = "IDLE"
    case syncing = "SYNCING"
    case success = "SUCCESS"
    case error = "ERROR"
    case conflict = "CONFLICT"
}

// MARK: - UI state

struct SyncUiState: Equatable, Sendable {
    var syncState: SyncState = .idle
    var message: String?
    var conflicts: [ConflictInfo]?
    var isAdminSync: Bool = false
}

// MARK: - Result

struct SyncResult: Equatable, Sendable {
    let state: SyncState
    let message: String?
    let conflicts: [ConflictInfo]?
    let isAdmin: Bool
    let successCount: Int
    /// Tip güvenli hata bilgisi (Android `SyncResult.error`).
    let error: SyncError?

    init(
        state: SyncState,
        message: String? = nil,
        conflicts: [ConflictInfo]? = nil,
        isAdmin: Bool = false,
        successCount: Int = 0,
        error: SyncError? = nil
    ) {
        self.state = state
        self.message = message
        self.conflicts = conflicts
        self.isAdmin = isAdmin
        self.successCount = successCount
        self.error = error
    }

    var isSuccess: Bool { state == .success }
    var isSyncing: Bool { state == .syncing }
    var isError: Bool { state == .error }
    var hasConflicts: Bool { state == .conflict && !(conflicts?.isEmpty ?? true) }
    var isIdle: Bool { state == .idle }

    static func success(
        _ message: String? = nil,
        isAdmin: Bool = false,
        count: Int = 0
    ) -> SyncResult {
        SyncResult(state: .success, message: message, isAdmin: isAdmin, successCount: count)
    }

    static func error(_ message: String) -> SyncResult {
        SyncResult(state: .error, message: message)
    }

    /// Tip güvenli `SyncError` ile hata sonucu (Android `SyncResult.error(error:)`).
    static func error(_ error: SyncError) -> SyncResult {
        SyncResult(state: .error, message: error.userMessage, error: error)
    }

    /// Hem özel mesaj hem tip güvenli hata ile (Android `SyncResult.error(message:, error:)`).
    static func error(message: String, error: SyncError?) -> SyncResult {
        SyncResult(state: .error, message: message, error: error)
    }

    static func conflict(_ conflicts: [ConflictInfo], message: String? = nil) -> SyncResult {
        let resolvedMessage = message ?? "\(conflicts.count) çakışma tespit edildi"
        return SyncResult(state: .conflict, message: resolvedMessage, conflicts: conflicts)
    }

    static func syncing(_ message: String? = nil) -> SyncResult {
        SyncResult(
            state: .syncing,
            message: message ?? "Senkronizasyon devam ediyor..."
        )
    }

    static var idle: SyncResult { SyncResult(state: .idle) }
}

// MARK: - Conflict

struct ConflictInfo: Equatable, Sendable, Identifiable {
    var id: String { "\(entityType)-\(entityId)" }
    let entityType: String
    let entityId: String
    let localVersion: String
    let remoteVersion: String

    var descriptionText: String {
        switch isLocalNewer {
        case true?:
            return "\(entityType) (\(entityId)): Yerel versiyon daha yeni"
        case false?:
            return "\(entityType) (\(entityId)): Uzak versiyon daha yeni"
        case nil:
            return "\(entityType) (\(entityId)): Zaman damgası karşılaştırılamıyor"
        }
    }

    private var isLocalNewer: Bool? {
        guard
            let local = parseISO8601(localVersion),
            let remote = parseISO8601(remoteVersion)
        else { return nil }
        return local > remote
    }

    private func parseISO8601(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
