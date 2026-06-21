import Foundation
import Observation
import os.log
import UIKit

/// Kırmızı liste operasyon paneli (Android `RedListViewModel`).
@MainActor
@Observable
final class RedListViewModel {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "RedListViewModel")

    private let redListRepository: any RedListRepository
    private let authorizedDeviceRepository: any AuthorizedDeviceRepository

    private var membersObservationTask: Task<Void, Never>?
    private var isAdminDevice = false

    // MARK: - UI state

    var members: [RedListMember] = []
    var searchQuery = ""
    private(set) var isLoading = false
    private(set) var isAuthorized = false
    private(set) var errorMessage: String?
    var selectedMemberIds: Set<String> = []

    // MARK: - Filtering

    /// `searchQuery` ile isim, not ve sebep üzerinde Türkçe uyumlu arama (Android paritesi).
    var filteredMembers: [RedListMember] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return members }
        return members.filter { member in
            member.guestName.localizedCaseInsensitiveContains(query)
                || (member.notes?.localizedCaseInsensitiveContains(query) ?? false)
                || member.reason.rawValue.localizedCaseInsensitiveContains(query)
                || member.reason.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    /// Panel erişim yetkisi: yetkili cihaz veya geçerli PIN oturumu (Android `hasPermission`).
    var hasPermission: Bool {
        isAuthorized || RedListPermissionManager.hasValidLocalPermission()
    }

    /// PIN ile kırmızı liste oturumu açar; başarılıysa `true`.
    @discardableResult
    func grantPermissionWithPin(_ pin: String) -> Bool {
        RedListPermissionManager.grantPermissionWithPin(pin)
    }

    // MARK: - Init

    init(
        redListRepository: any RedListRepository,
        authorizedDeviceRepository: any AuthorizedDeviceRepository
    ) {
        self.redListRepository = redListRepository
        self.authorizedDeviceRepository = authorizedDeviceRepository

        Task {
            await checkDeviceAuthorization()
            await refreshAdminStatus()
            loadRedListMembers()
        }
    }

    // MARK: - Authorization

    /// Cihazın kırmızı liste paneline erişim yetkisini doğrular.
    func checkDeviceAuthorization() async {
        let deviceId = Self.currentDeviceId
        isAuthorized = await authorizedDeviceRepository.isDeviceAuthorized(deviceId: deviceId)
    }

    private func refreshAdminStatus() async {
        let deviceId = Self.currentDeviceId
        isAdminDevice = await authorizedDeviceRepository.isAdminDevice(deviceId: deviceId)
    }

    private static var currentDeviceId: String {
        DeviceIdentifier.getDeviceId()
    }

    // MARK: - Members stream

    func loadRedListMembers() {
        membersObservationTask?.cancel()
        membersObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await refreshAdminStatus()

            do {
                let stream = redListRepository.allRedListMembers(isAdmin: isAdminDevice)
                for await snapshot in stream {
                    guard !Task.isCancelled else { break }
                    members = snapshot
                    errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Red list members load error: \(error.localizedDescription, privacy: .public)")
                errorMessage = "Liste yüklenirken hata: \(error.localizedDescription)"
            }
        }
    }

    func searchMembers(query: String) {
        searchQuery = query
    }

    // MARK: - Add

    /// Mevcut misafiri kırmızı listeye ekler (Android `addToRedList`).
    func addGuestToRedList(
        guestId: String,
        reason: RedListEntryReason,
        notes: String? = nil
    ) async -> RedListResult<RedListMember> {
        await withLoadingState {
            await refreshAdminStatus()
            let addedBy = isAdminDevice ? "ADMIN" : nil
            let result = await redListRepository.addToRedList(
                guestId: guestId,
                reason: reason,
                notes: notes,
                addedBy: addedBy
            )
            handleRepositoryResult(result)
            return result
        }
    }

    /// Manuel isimle kırmızı listeye ekler (Android `addManuallyToRedList`).
    func addMemberToRedList(
        guestName: String,
        reason: RedListEntryReason,
        notes: String? = nil
    ) async -> RedListResult<RedListMember> {
        await withLoadingState {
            await refreshAdminStatus()
            let addedBy = isAdminDevice ? "ADMIN" : nil
            let result = await redListRepository.addManuallyToRedList(
                guestName: guestName,
                reason: reason,
                notes: notes,
                addedBy: addedBy
            )
            handleRepositoryResult(result)
            return result
        }
    }

    // MARK: - Remove

    func removeFromRedList(guestId: String) {
        Task {
            await withLoadingState {
                let result = await redListRepository.removeFromRedList(guestId: guestId)
                handleRepositoryResult(result)
            }
        }
    }

    func removeFromRedListByMemberId(memberId: String) {
        Task {
            await withLoadingState {
                let result = await redListRepository.removeFromRedList(byMemberId: memberId)
                handleRepositoryResult(result)
            }
        }
    }

    // MARK: - Selection

    func toggleMemberSelection(memberId: String) {
        if selectedMemberIds.contains(memberId) {
            selectedMemberIds.remove(memberId)
        } else {
            selectedMemberIds.insert(memberId)
        }
    }

    func selectAllMembers() {
        selectedMemberIds = Set(filteredMembers.map(\.id))
    }

    func clearSelection() {
        selectedMemberIds = []
    }

    // MARK: - Batch delete

    func deleteSelectedMembers() {
        let ids = Array(selectedMemberIds)
        guard !ids.isEmpty else { return }

        Task {
            await performBatchDelete(memberIds: ids)
        }
    }

    private func performBatchDelete(memberIds: [String]) async {
        isLoading = true
        clearError()
        defer { isLoading = false }

        var successCount = 0
        var errorCount = 0
        var errors: [String] = []

        let repository = redListRepository

        await withTaskGroup(of: (memberId: String, result: RedListResult<Void>).self) { group in
            for memberId in memberIds {
                group.addTask {
                    do {
                        let result = await repository.removeFromRedList(byMemberId: memberId)
                        return (memberId, result)
                    } catch {
                        let message = "Üye silinirken hata: \(error.localizedDescription)"
                        return (memberId, .error(message: message))
                    }
                }
            }

            for await outcome in group {
                switch outcome.result {
                case .success:
                    successCount += 1
                case .error(let message, _, _):
                    errorCount += 1
                    errors.append(message)
                }
            }
        }

        selectedMemberIds = []

        if errorCount == 0 {
            clearError()
        } else if successCount > 0 {
            errorMessage = "\(successCount) üye silindi, \(errorCount) üye silinirken hata oluştu"
        } else {
            errorMessage = errors.first ?? "Tüm üyeler silinirken hata oluştu"
        }
    }

    // MARK: - Error

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Helpers

    private func handleRepositoryResult<T: Sendable>(_ result: RedListResult<T>) {
        switch result {
        case .success:
            clearError()
        case .error(let message, _, _):
            errorMessage = message
        }
    }

    private func withLoadingState<T>(
        operation: () async throws -> T
    ) async rethrows -> T {
        isLoading = true
        clearError()
        defer { isLoading = false }
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            errorMessage = "Beklenmeyen hata: \(error.localizedDescription)"
            throw error
        }
    }
}
