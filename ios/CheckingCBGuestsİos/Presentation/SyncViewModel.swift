import Foundation
import Observation
import os.log
import SwiftUI

private enum SyncUiConstants {
    static let autoClearDelay: Duration = .seconds(3)
}

/// Senkronizasyon ekranı durum yöneticisi (Android `SyncViewModel`).
@MainActor
@Observable
final class SyncViewModel {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "SyncViewModel")

    private let syncRepository: any SyncRepository
    private var autoClearTask: Task<Void, Never>?

    var uiState = SyncUiState()

    init(syncRepository: any SyncRepository) {
        self.syncRepository = syncRepository
    }

    // MARK: - Sync

    /// Manuel veya otomatik senkronizasyonu başlatır (Android `syncWithFirebase`).
    func triggerSync() async {
        guard uiState.syncState != .syncing else { return }

        cancelAutoClear()

        uiState = SyncUiState(
            syncState: .syncing,
            message: "Senkronize ediliyor..."
        )

        do {
            let result = await syncRepository.syncWithFirebase()
            applySyncResult(result)

            if result.state == .success || result.state == .error {
                scheduleAutoClear(expectedState: result.state)
            }
        } catch {
            Self.logger.error("Sync exception: \(error.localizedDescription, privacy: .public)")
            let message = "Beklenmeyen hata: \(error.localizedDescription)"
            uiState = SyncUiState(syncState: .error, message: message)
            scheduleAutoClear(expectedState: .error)
        }
    }

    // MARK: - Reset

    func clearState() {
        cancelAutoClear()
        uiState = SyncUiState()
    }

    // MARK: - Private

    private func applySyncResult(_ result: SyncResult) {
        switch result.state {
        case .success:
            let adminTag = result.isAdmin ? " (Yönetici)" : ""
            let finalMessage = (result.message ?? "") + adminTag
            uiState = SyncUiState(
                syncState: .success,
                message: finalMessage.isEmpty ? nil : finalMessage,
                isAdminSync: result.isAdmin
            )

        case .error:
            uiState = SyncUiState(
                syncState: .error,
                message: result.message ?? "Hata oluştu",
                conflicts: nil
            )

        case .conflict:
            uiState = SyncUiState(
                syncState: .conflict,
                message: result.message,
                conflicts: result.conflicts
            )

        case .syncing, .idle:
            break
        }
    }

    private func scheduleAutoClear(expectedState: SyncState) {
        cancelAutoClear()
        autoClearTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: SyncUiConstants.autoClearDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if self.uiState.syncState == expectedState {
                self.uiState = SyncUiState()
            }
        }
    }

    private func cancelAutoClear() {
        autoClearTask?.cancel()
        autoClearTask = nil
    }
}
