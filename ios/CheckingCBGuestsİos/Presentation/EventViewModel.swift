import FirebaseFirestore
import Foundation
import Observation
import os.log
import UIKit

// MARK: - UI events

enum UiEvent: Equatable, Sendable {
    case idle
    case showSuccess(String)
    case showError(String)
    case clearMessage
    case showRedListPermissionRequired(guestId: String)
    case showRedListAddPermissionRequired(guest: Guest)
}

// MARK: - Permission

protocol RedListPermissionChecking: Sendable {
    func canCheckInRedListGuest() -> Bool
}

/// Varsayılan: PIN doğrulaması yoksa tüm işlemlere izin verilir (geliştirilebilir).
struct PermissiveRedListPermissionChecker: RedListPermissionChecking {
    func canCheckInRedListGuest() -> Bool { true }
}

// MARK: - Internal result

private enum VmResult<T: Sendable>: Sendable {
    case success(T)
    case error(Error)

    func fold<R>(onError: (Error) -> R, onSuccess: (T) -> R) -> R {
        switch self {
        case .success(let value): return onSuccess(value)
        case .error(let error): return onError(error)
        }
    }
}

// MARK: - EventViewModel

/// Etkinlik ve misafir ekranları için ana koordinatör (Android `EventViewModel`).
@MainActor
@Observable
final class EventViewModel {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "EventViewModel")
    private static let refreshDelayNanoseconds: UInt64 = 500_000_000
    private static let optimisticClearDelayNanoseconds: UInt64 = 2_000_000_000
    private static let adminRedListCollection = "admin_red_list_names"
    private static let turkishLocale = Locale(identifier: "tr_TR")

    private let eventRepository: any EventRepository
    private let redListRepository: any RedListRepository
    private let authorizedDeviceRepository: any AuthorizedDeviceRepository
    private let redListPermissionChecker: any RedListPermissionChecking
    private let autoSyncManager: AutoSyncManager?

    @ObservationIgnored
    private nonisolated let observationTasks = ObservationTaskHolder()

    // MARK: Published state

    private(set) var events: [Event] = []
    private(set) var guests: [Guest] = []
    var searchQuery = ""
    var activeFilterTab: GuestStatus?
    private(set) var isLoading = false
    /// İlk Firestore snapshot gelene kadar ana liste boş/beyaz görünmesin.
    private(set) var isBootstrapping = true
    private(set) var isAdminDevice = false

    var isSelectionMode = false
    var selectedGuestIds: Set<String> = []

    var isEventSelectionMode = false
    var selectedEventIds: Set<String> = []

    private(set) var uiEvent: UiEvent = .idle
    private(set) var redListGuestIds: Set<String> = []
    private(set) var hiddenRedListGuestIds: Set<String> = []

    private var optimisticGuestUpdates: [String: Guest] = [:]
    private var pendingGuestsStreams: [String: AsyncStream<[Guest]>] = [:]

    // MARK: Init

    init(
        eventRepository: any EventRepository,
        redListRepository: any RedListRepository,
        authorizedDeviceRepository: any AuthorizedDeviceRepository,
        redListPermissionChecker: any RedListPermissionChecking = PermissiveRedListPermissionChecker(),
        autoSyncManager: AutoSyncManager? = nil
    ) {
        self.eventRepository = eventRepository
        self.redListRepository = redListRepository
        self.authorizedDeviceRepository = authorizedDeviceRepository
        self.redListPermissionChecker = redListPermissionChecker
        self.autoSyncManager = autoSyncManager

        startObservationTasks()
        observationTasks.add(Task { [weak self] in
            await self?.checkAdminStatus()
        })
        startBootstrapTimeoutWatchdog()
    }

    /// Firestore ilk snapshot vermezse liste ekranında sonsuz yükleme göstergesini engeller.
    private func startBootstrapTimeoutWatchdog() {
        observationTasks.add(Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, self.isBootstrapping else { return }
            Self.logger.warning("Etkinlik bootstrap timeout — isBootstrapping kapatılıyor")
            self.isBootstrapping = false
        })
    }

    deinit {
        observationTasks.cancelAll()
    }

    // MARK: - Computed

    private var normalizedSearchQuery: String {
        searchQuery.lowercased(with: Self.turkishLocale)
    }

    /// Misafir akışı + iyimser güncellemeler.
    var mergedGuests: [Guest] {
        guests.map { optimisticGuestUpdates[$0.id] ?? $0 }
    }

    /// Etkinlik listesi — katılımcı / toplam sayılar misafirlerden hesaplanır.
    var eventsWithCounts: [Event] {
        let guestsByEvent = Dictionary(grouping: mergedGuests, by: \.eventId)
        return events.map { event -> Event in
            let eventGuests: [Guest] = guestsByEvent[event.id] ?? []
            let total = eventGuests.count
            let participated = eventGuests.filter { guest in
                guest.status == .checkedIn || guest.status == .exited
            }.count
            return Event(
                id: event.id,
                title: event.title,
                date: event.date,
                location: event.location,
                startTime: event.startTime,
                status: event.status,
                deletedAt: event.deletedAt,
                participatedCount: participated,
                totalGuestCount: total
            )
        }
    }

    /// Belirli etkinlik için filtrelenmiş misafir listesi (Android `getFilteredGuests`).
    func filteredGuests(for eventId: String, currentEvent: Event?) -> [Guest] {
        let eventGuests = mergedGuests.filter { $0.eventId == eventId }
        let query = normalizedSearchQuery
        let isExpired = isEventPast(currentEvent)

        return eventGuests
            .filter { guest in
                let isNotRedList = !guest.isRedListPending && guest.status != .pendingApproval
                let matchesQuery = query.isEmpty || matchesSearchQuery(guest, normalizedQuery: query)

                let matchesFilter: Bool
                if isExpired, activeFilterTab == .checkedIn {
                    matchesFilter = guest.status == .checkedIn || guest.status == .exited
                } else {
                    matchesFilter = activeFilterTab == nil || guest.status == activeFilterTab
                }

                return isNotRedList && matchesQuery && matchesFilter
            }
            .sorted { lhs, rhs in
                let lhsSectionEmpty = lhs.sectionTitle?.isEmpty ?? true
                let rhsSectionEmpty = rhs.sectionTitle?.isEmpty ?? true
                if lhsSectionEmpty != rhsSectionEmpty { return !lhsSectionEmpty }
                switch (lhs.sectionTitle, rhs.sectionTitle) {
                case let (left?, right?) where left != right: return left < right
                default: break
                }
                switch (lhs.expectedTime, rhs.expectedTime) {
                case let (left?, right?) where left != right: return left < right
                case (nil, _?): return false
                case (_?, nil): return true
                default: break
                }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
    }

    func pendingRedListGuestsStream(for eventId: String) -> AsyncStream<[Guest]> {
        if let cached = pendingGuestsStreams[eventId] {
            return cached
        }
        let stream = eventRepository.pendingRedListGuests(eventId: eventId)
        pendingGuestsStreams[eventId] = stream
        return stream
    }

    // MARK: - Search & filter UI

    func onSearchQueryChanged(_ query: String) {
        searchQuery = query
    }

    func onFilterTabChanged(_ status: GuestStatus?) {
        activeFilterTab = status
    }

    func clearMessage() {
        uiEvent = .clearMessage
    }

    // MARK: - Refresh

    func refreshEvents() async {
        isLoading = true
        defer {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.refreshDelayNanoseconds)
                isLoading = false
            }
        }
        await syncAfterOperation()
    }

    // MARK: - Guest status

    func updateGuestStatus(
        guestId: String,
        eventId: String? = nil,
        requirePermission: Bool = true,
        currentEvent: Event? = nil
    ) async {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return
        }

        guard checkInternetConnectivity() else {
            uiEvent = .showError("İnternet bağlantısı gerekli.")
            return
        }

        let effectiveEventId = eventId ?? currentEvent?.id
        let guestFromRepo: Guest?
        if let effectiveEventId, !effectiveEventId.isEmpty {
            guestFromRepo = await eventRepository.guest(eventId: effectiveEventId, guestId: guestId)
        } else {
            guestFromRepo = await eventRepository.guest(byId: guestId)
        }

        guard let guest = optimisticGuestUpdates[guestId] ?? guestFromRepo else {
            uiEvent = .showError("Misafir bulunamadı. Lütfen sayfayı yenileyin.")
            return
        }

        let isRedList = guest.isRedListPending || redListGuestIds.contains(guestId)
        if !isAdminDevice && isRedList {
            uiEvent = .showError("Bu işlem için yetkiniz yok!")
            return
        }

        if isRedList, requirePermission, !redListPermissionChecker.canCheckInRedListGuest() {
            uiEvent = .showRedListPermissionRequired(guestId: guestId)
            return
        }

        switch guestAndToggleStatus(guest) {
        case .error(let error):
            uiEvent = .showError("Hata: \(error.localizedDescription)")
        case .success(let updatedGuest):
            optimisticGuestUpdates[updatedGuest.id] = updatedGuest
            if activeFilterTab != nil {
                activeFilterTab = updatedGuest.status
            }
            uiEvent = .showSuccess(statusChangeMessage(for: updatedGuest))
            await persistGuestUpdate(updatedGuest)
        }
    }

    // MARK: - Insert / approve / red list

    func insertGuest(_ guest: Guest, currentEvent: Event?) async -> Bool {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return false
        }

        guard checkInternetConnectivity() else {
            uiEvent = .showError("İnternet bağlantısı yok.")
            return false
        }

        isLoading = true
        defer { isLoading = false }

        let finalGuest = guestWithFormattedName(guest)
        let normalizedName = redListRepository.normalizeGuestName(finalGuest.name)

        if await redListRepository.getActiveRedListMember(byName: finalGuest.name) != nil {
            uiEvent = .showRedListAddPermissionRequired(guest: finalGuest)
            return false
        }

        if await firebaseRedListMatch(for: normalizedName) != nil {
            uiEvent = .showRedListAddPermissionRequired(guest: finalGuest)
            return false
        }

        let guestToSave = await uploadPhotoIfNeeded(for: finalGuest)
        await eventRepository.insertGuest(guestToSave)
        await syncAfterOperation()
        uiEvent = .showSuccess("Misafir eklendi.")
        return true
    }

    /// Kırmızı liste şüphesiyle onaya gönderilen misafiri ekler (Android `addGuestAsPendingApproval`).
    func addGuestAsPendingApproval(_ guest: Guest, currentEvent: Event?) async {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return
        }
        guard checkInternetConnectivity() else {
            uiEvent = .showError("İnternet bağlantısı yok.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        var pending = guestWithFormattedName(guest)
        pending.status = .pendingApproval
        pending.isRedListPending = true

        let guestToSave = await uploadPhotoIfNeeded(for: pending)
        await eventRepository.insertGuest(guestToSave)
        await AdminNotificationService.sendRedListNotification(event: currentEvent, guest: guestToSave)
        uiEvent = .showSuccess("Misafir amir onayına gönderildi.")
    }

    func approveGuest(_ guest: Guest, currentEvent: Event?) async {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let result = await eventRepository.approveGuest(guest)
        switch result {
        case .success:
            uiEvent = .showSuccess("Misafir onaylandı.")
        case .failure(let error):
            uiEvent = .showError("Hata: \(error.localizedDescription)")
        }
    }

    func rejectRedListGuest(guestId: String, currentEvent: Event?) async {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        await eventRepository.deleteGuest(guestId: guestId, eventId: currentEvent?.id)
        _ = await redListRepository.removeFromRedList(guestId: guestId)
        await syncAfterOperation()
        uiEvent = .showSuccess("Misafir reddedildi.")
    }

    func removeFromRedList(guestId: String) async {
        guard checkInternetConnectivity() else { return }

        let result = await redListRepository.removeFromRedList(guestId: guestId)
        switch result {
        case .success:
            if let guest = await eventRepository.guest(byId: guestId) {
                let updated = Guest(
                    id: guest.id,
                    eventId: guest.eventId,
                    name: guest.name,
                    title: guest.title,
                    arrivalMethod: guest.arrivalMethod,
                    plate: guest.plate,
                    model: guest.model,
                    securityCheck: guest.securityCheck,
                    status: guest.status,
                    entryTime: guest.entryTime,
                    exitTime: guest.exitTime,
                    photoUri: guest.photoUri,
                    deletedAt: guest.deletedAt,
                    isRedListPending: false,
                    note: guest.note,
                    expectedTime: guest.expectedTime,
                    sectionTitle: guest.sectionTitle,
                    participationCategory: guest.participationCategory
                )
                await eventRepository.updateGuest(updated)
            }
            uiEvent = .showSuccess("Misafir kırmızı listeden çıkarıldı.")
        case .error(let message, _, _):
            uiEvent = .showError(message)
        }
    }

    // MARK: - Events

    func addEvent(_ event: Event) async {
        let formatted = Event(
            id: event.id,
            title: formatTurkishUpper(event.title),
            date: event.date,
            location: event.location,
            startTime: event.startTime,
            status: event.status,
            deletedAt: event.deletedAt,
            participatedCount: event.participatedCount,
            totalGuestCount: event.totalGuestCount
        )
        await eventRepository.insertEvent(formatted)
        uiEvent = .showSuccess("Etkinlik eklendi")
    }

    func deleteEvent(eventId: String) async {
        isLoading = true
        defer { isLoading = false }
        await eventRepository.deleteEvent(eventId: eventId)
        await syncAfterOperation()
        uiEvent = .showSuccess("Etkinlik silindi")
    }

    func deleteGuest(guestId: String, eventId: String? = nil, currentEvent: Event? = nil) async {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let effectiveEventId = eventId ?? currentEvent?.id
        await eventRepository.deleteGuest(guestId: guestId, eventId: effectiveEventId)
        await syncAfterOperation()
        uiEvent = .showSuccess("Misafir silindi")
    }

    // MARK: - Selection

    func toggleSelectionMode() {
        if isSelectionMode {
            selectedGuestIds = []
        }
        isSelectionMode.toggle()
    }

    func toggleGuestSelection(id: String) {
        if selectedGuestIds.contains(id) {
            selectedGuestIds.remove(id)
        } else {
            selectedGuestIds.insert(id)
        }
        if selectedGuestIds.isEmpty {
            isSelectionMode = false
        }
    }

    func selectAllGuests(ids: [String]) {
        selectedGuestIds = Set(ids)
    }

    func clearSelection() {
        selectedGuestIds = []
        isSelectionMode = false
    }

    func deleteSelectedGuests(currentEvent: Event?) async {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return
        }
        guard checkInternetConnectivity() else {
            uiEvent = .showError("İnternet bağlantısı gerekli.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let ids = Array(selectedGuestIds)
        guard !ids.isEmpty else { return }

        let eventId = currentEvent?.id
        for id in ids {
            await eventRepository.deleteGuest(guestId: id, eventId: eventId)
        }
        await syncAfterOperation()
        selectedGuestIds = []
        isSelectionMode = false
        uiEvent = .showSuccess("\(ids.count) misafir silindi.")
    }

    func assignSectionToSelectedGuests(sectionTitle: String, currentEvent: Event?) async {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return
        }
        guard checkInternetConnectivity() else {
            uiEvent = .showError("İnternet bağlantısı gerekli.")
            return
        }

        let ids = Array(selectedGuestIds)
        guard !ids.isEmpty else { return }

        let trimmed = sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            uiEvent = .showError("Grup başlığı boş olamaz")
            return
        }

        isLoading = true
        defer { isLoading = false }

        for id in ids {
            guard var guest = optimisticGuestUpdates[id] ?? guests.first(where: { $0.id == id }) else { continue }
            guest.sectionTitle = trimmed
            optimisticGuestUpdates[id] = guest
            await eventRepository.updateGuest(guest)
        }
        await syncAfterOperation()
        selectedGuestIds = []
        isSelectionMode = false
        uiEvent = .showSuccess("Heyet atandı: \(trimmed)")
    }

    func removeGuestFromDelegation(guestId: String, currentEvent: Event?) async {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return
        }
        guard var guest = optimisticGuestUpdates[guestId] ?? guests.first(where: { $0.id == guestId }) else {
            uiEvent = .showError("Misafir bulunamadı.")
            return
        }
        guest.sectionTitle = nil
        optimisticGuestUpdates[guestId] = guest
        await eventRepository.updateGuest(guest)
        await syncAfterOperation()
        uiEvent = .showSuccess("Misafir heyetten çıkarıldı")
    }

    func toggleEventSelectionMode() {
        if isEventSelectionMode {
            selectedEventIds = []
        }
        isEventSelectionMode.toggle()
    }

    func toggleEventSelection(id: String) {
        if selectedEventIds.contains(id) {
            selectedEventIds.remove(id)
        } else {
            selectedEventIds.insert(id)
        }
        if selectedEventIds.isEmpty {
            isEventSelectionMode = false
        }
    }

    func selectAllEvents(ids: [String]) {
        selectedEventIds = Set(ids)
    }

    func clearEventSelection() {
        selectedEventIds = []
        isEventSelectionMode = false
    }

    func deleteSelectedEvents() async {
        guard checkInternetConnectivity() else { return }
        isLoading = true
        defer { isLoading = false }

        let ids = Array(selectedEventIds)
        guard !ids.isEmpty else { return }

        for id in ids {
            await eventRepository.deleteEvent(eventId: id)
        }
        await syncAfterOperation()
        selectedEventIds = []
        isEventSelectionMode = false
    }

    // MARK: - Guest times / photo / details

    /// Misafirin giriş/çıkış saatlerini günceller (Android `updateGuestTimes`).
    /// `entryTime` / `exitTime` "HH:mm" biçiminde beklenir; boş/nil değer ilgili saati temizler.
    func updateGuestTimes(
        guestId: String,
        eventId: String,
        entryTime: String? = nil,
        exitTime: String? = nil
    ) async {
        guard checkInternetConnectivity() else {
            uiEvent = .showError("İnternet bağlantısı gerekli.")
            return
        }
        var resolvedGuest = optimisticGuestUpdates[guestId]
        if resolvedGuest == nil {
            resolvedGuest = await eventRepository.guest(eventId: eventId, guestId: guestId)
        }
        if resolvedGuest == nil {
            resolvedGuest = guests.first(where: { $0.id == guestId })
        }
        guard var guest = resolvedGuest else {
            uiEvent = .showError("Misafir bulunamadı.")
            return
        }

        guest.entryTime = isoTimestamp(fromDisplayTime: entryTime)
        guest.exitTime = isoTimestamp(fromDisplayTime: exitTime)

        if guest.exitTime != nil {
            guest.status = .exited
        } else if guest.entryTime != nil {
            guest.status = .checkedIn
        } else if guest.status != .pendingApproval {
            guest.status = .pending
        }

        optimisticGuestUpdates[guestId] = guest
        await persistGuestUpdate(guest)
        uiEvent = .showSuccess("Saat bilgisi güncellendi")
    }

    /// Misafir fotoğrafını anlık olarak günceller (Android `updateGuestPhoto`).
    func updateGuestPhoto(guestId: String, localURL: URL) async {
        guard checkInternetConnectivity() else {
            uiEvent = .showError("İnternet bağlantısı gerekli.")
            return
        }
        guard var guest = await eventRepository.guest(byId: guestId)
            ?? guests.first(where: { $0.id == guestId }) else {
            uiEvent = .showError("Misafir bulunamadı.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let result = await GuestPhotoStorage.uploadGuestPhoto(
            localURL: localURL,
            eventId: guest.eventId,
            guestId: guest.id
        )
        switch result {
        case .success(let url):
            guest.photoUri = url
            await eventRepository.updateGuest(guest)
            uiEvent = .showSuccess("Fotoğraf güncellendi")
        case .failure(let message):
            uiEvent = .showError(message)
        }
    }

    /// Misafir bilgilerini (+ opsiyonel yeni fotoğraf) günceller (Android `updateGuestDetails`).
    func updateGuestDetails(_ guest: Guest, newPhotoLocalURL: URL? = nil, currentEvent: Event?) async {
        if isEventPast(currentEvent) {
            uiEvent = .showError("Geçmiş etkinlikte değişiklik yapılamaz.")
            return
        }
        guard checkInternetConnectivity() else {
            uiEvent = .showError("İnternet bağlantısı gerekli.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        var updated = guestWithFormattedName(guest)

        if let newPhotoLocalURL {
            let result = await GuestPhotoStorage.uploadGuestPhoto(
                localURL: newPhotoLocalURL,
                eventId: updated.eventId,
                guestId: updated.id
            )
            if case .success(let url) = result {
                updated.photoUri = url
            } else if case .failure = result {
                uiEvent = .showError("Fotoğraf yüklenemedi, diğer bilgiler güncelleniyor.")
            }
        }

        await eventRepository.updateGuest(updated)
        uiEvent = .showSuccess("Misafir bilgileri güncellendi")
    }

    // MARK: - PIN permission

    /// PIN ile kırmızı liste check-in oturumu açar; başarılıysa `true`.
    @discardableResult
    func grantRedListPermission(pin: String) -> Bool {
        RedListPermissionManager.grantPermissionWithPin(pin)
    }

    // MARK: - Observation

    private func startObservationTasks() {
        observationTasks.add(Task { @MainActor [weak self] in
            guard let self else { return }
            var isFirstSnapshot = true
            for await snapshot in eventRepository.allEvents() {
                self.events = snapshot
                if isFirstSnapshot {
                    isFirstSnapshot = false
                    self.isBootstrapping = false
                    Self.logger.debug("İlk etkinlik snapshot: \(snapshot.count) kayıt")
                    if snapshot.isEmpty {
                        await self.syncAfterOperation()
                    }
                }
            }
        })

        observationTasks.add(Task { @MainActor [weak self] in
            guard let self else { return }
            for await snapshot in eventRepository.allGuests() {
                self.guests = snapshot
            }
        })

        observationTasks.add(Task { @MainActor [weak self] in
            guard let self else { return }
            for await ids in self.redListRepository.allRedListGuestIds() {
                self.redListGuestIds = ids
            }
        })

        observationTasks.add(Task { @MainActor [weak self] in
            guard let self else { return }
            for await ids in self.redListRepository.hiddenRedListGuestIds() {
                self.hiddenRedListGuestIds = ids
            }
        })
    }

    private func checkAdminStatus() async {
        let deviceId = DeviceIdentifier.getDeviceId()
        isAdminDevice = await authorizedDeviceRepository.isAdminDevice(deviceId: deviceId)
    }

    // MARK: - Helpers

    private func checkInternetConnectivity() -> Bool {
        NetworkMonitor.shared.isConnected
    }

    private func isEventPast(_ event: Event?) -> Bool {
        guard let event else { return false }
        return event.isExpired || event.status == .past
    }

    private func formatTurkishUpper(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed: String
        if let regex = try? NSRegularExpression(pattern: "\\s+") {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            collapsed = regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: " ")
        } else {
            collapsed = trimmed
        }
        return collapsed.uppercased(with: Self.turkishLocale)
    }

    private func guestWithFormattedName(_ guest: Guest) -> Guest {
        Guest(
            id: guest.id,
            eventId: guest.eventId,
            name: formatTurkishUpper(guest.name),
            title: guest.title,
            arrivalMethod: guest.arrivalMethod,
            plate: guest.plate,
            model: guest.model,
            securityCheck: guest.securityCheck,
            status: guest.status,
            entryTime: guest.entryTime,
            exitTime: guest.exitTime,
            photoUri: guest.photoUri,
            deletedAt: guest.deletedAt,
            isRedListPending: guest.isRedListPending,
            note: guest.note,
            expectedTime: guest.expectedTime,
            sectionTitle: guest.sectionTitle,
            participationCategory: guest.participationCategory
        )
    }

    private func matchesSearchQuery(_ guest: Guest, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }
        let name = guest.name.lowercased(with: Self.turkishLocale)
        let title = guest.title.lowercased(with: Self.turkishLocale)
        let plate = guest.plate?.lowercased(with: Self.turkishLocale) ?? ""
        return name.contains(normalizedQuery)
            || title.contains(normalizedQuery)
            || plate.contains(normalizedQuery)
    }

    private func guestAndToggleStatus(_ guest: Guest) -> VmResult<Guest> {
        if guest.status == .pendingApproval {
            return .error(NSError(
                domain: "EventViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bu misafir admin onayı bekliyor. Önce onay verin."]
            ))
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let updated: Guest
        switch guest.status {
        case .pending:
            updated = Guest(
                id: guest.id, eventId: guest.eventId, name: guest.name, title: guest.title,
                arrivalMethod: guest.arrivalMethod, plate: guest.plate, model: guest.model,
                securityCheck: guest.securityCheck, status: .checkedIn, entryTime: now,
                exitTime: guest.exitTime, photoUri: guest.photoUri, deletedAt: guest.deletedAt,
                isRedListPending: guest.isRedListPending, note: guest.note,
                expectedTime: guest.expectedTime, sectionTitle: guest.sectionTitle,
                participationCategory: guest.participationCategory
            )
        case .checkedIn:
            updated = Guest(
                id: guest.id, eventId: guest.eventId, name: guest.name, title: guest.title,
                arrivalMethod: guest.arrivalMethod, plate: guest.plate, model: guest.model,
                securityCheck: guest.securityCheck, status: .exited, entryTime: guest.entryTime,
                exitTime: now, photoUri: guest.photoUri, deletedAt: guest.deletedAt,
                isRedListPending: guest.isRedListPending, note: guest.note,
                expectedTime: guest.expectedTime, sectionTitle: guest.sectionTitle,
                participationCategory: guest.participationCategory
            )
        case .exited:
            updated = Guest(
                id: guest.id, eventId: guest.eventId, name: guest.name, title: guest.title,
                arrivalMethod: guest.arrivalMethod, plate: guest.plate, model: guest.model,
                securityCheck: guest.securityCheck, status: .pending, entryTime: nil,
                exitTime: nil, photoUri: guest.photoUri, deletedAt: guest.deletedAt,
                isRedListPending: guest.isRedListPending, note: guest.note,
                expectedTime: guest.expectedTime, sectionTitle: guest.sectionTitle,
                participationCategory: guest.participationCategory
            )
        case .pendingApproval:
            return .error(NSError(
                domain: "EventViewModel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Onay bekleyen misafir güncellenemez."]
            ))
        }
        return .success(updated)
    }

    private func statusChangeMessage(for guest: Guest) -> String {
        let action: String
        switch guest.status {
        case .checkedIn: action = "giriş yaptı"
        case .exited: action = "çıkış yaptı"
        case .pending: action = "sıfırlandı"
        case .pendingApproval: action = "güncellendi"
        }
        return "\(guest.name) \(action)"
    }

    private func persistGuestUpdate(_ guest: Guest) async {
        let guestId = guest.id
        await eventRepository.updateGuest(guest)
        try? await Task.sleep(nanoseconds: Self.optimisticClearDelayNanoseconds)
        optimisticGuestUpdates.removeValue(forKey: guestId)
    }

    private func firebaseRedListMatch(for normalizedName: String) async -> Bool? {
        guard !normalizedName.isEmpty else { return nil }
        do {
            let snapshot = try await Firestore.firestore()
                .collection(Self.adminRedListCollection)
                .document(normalizedName)
                .getDocument(source: .server)
            guard snapshot.exists else { return nil }
            let isActive = snapshot.data()?["isActive"] as? Bool ?? false
            return isActive ? true : nil
        } catch {
            return nil
        }
    }

    /// Misafirin `photoUri` değeri yerel dosya ise Storage'a yükler ve URL ile günceller.
    private func uploadPhotoIfNeeded(for guest: Guest) async -> Guest {
        guard GuestPhotoStorage.isLocalURI(guest.photoUri),
              let photoUri = guest.photoUri,
              let localURL = URL(string: photoUri) else {
            return guest
        }
        let result = await GuestPhotoStorage.uploadGuestPhoto(
            localURL: localURL,
            eventId: guest.eventId,
            guestId: guest.id
        )
        guard case .success(let url) = result else { return guest }
        var copy = guest
        copy.photoUri = url
        return copy
    }

    /// CRUD işlemleri sonrası anlık senkronizasyon (Android `syncAfterOperation`).
    private func syncAfterOperation() async {
        guard let autoSyncManager else { return }
        _ = await autoSyncManager.syncImmediately()
    }

    /// "HH:mm" görüntü saatini bugünün ISO 8601 zaman damgasına çevirir; boş/nil → nil.
    private func isoTimestamp(fromDisplayTime display: String?) -> String? {
        guard let display else { return nil }
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = Date()
        guard let date = calendar.date(
            bySettingHour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59),
            second: 0,
            of: now
        ) else {
            return nil
        }
        return ISO8601DateFormatter().string(from: date)
    }
}
