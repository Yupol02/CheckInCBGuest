import FirebaseAuth
import FirebaseFirestore
import Foundation
import os.log

/// Firestore tabanlı `SyncRepository` (Android `SyncRepositoryImpl` eşleniği).
///
/// Firestore-only mimaride veri zaten doğrudan yazıldığı için `syncWithFirebase`
/// "hafif senkronizasyon" yapar: yalnızca SERVER'dan okuyarak yerel önbelleği
/// günceller; bu da snapshot dinleyicilerini otomatik tetikler. Tam push/pull
/// metodları (legacy) eksiksiz port edilmiştir.
final class FirebaseSyncRepository: SyncRepository, @unchecked Sendable {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "FirebaseSyncRepository")
    private static let maxBatchSize = 100
    private static let maxParallelGuests = 50

    private let firestore: Firestore
    private let eventRepository: any EventRepository
    private let authorizedDeviceRepository: any AuthorizedDeviceRepository
    private let redListRepository: any RedListRepository

    init(
        firestore: Firestore = Firestore.firestore(),
        eventRepository: any EventRepository,
        authorizedDeviceRepository: any AuthorizedDeviceRepository,
        redListRepository: any RedListRepository
    ) {
        self.firestore = firestore
        self.eventRepository = eventRepository
        self.authorizedDeviceRepository = authorizedDeviceRepository
        self.redListRepository = redListRepository
    }

    // MARK: - Collection paths

    private var eventsCollection: CollectionReference { firestore.collection("events") }
    private func guestsCollection(_ eventId: String) -> CollectionReference {
        eventsCollection.document(eventId).collection("guests")
    }
    private func guestsSecureCollection(_ eventId: String) -> CollectionReference {
        eventsCollection.document(eventId).collection("guests_secure")
    }
    private var authorizedDevicesCollection: CollectionReference {
        firestore.collection("authorized_devices")
    }

    // MARK: - Public API

    func syncWithFirebase() async -> SyncResult {
        let startTime = Date()
        guard await isOnline() else {
            return .error(SyncError.networkError(message: "İnternet bağlantısı bulunamadı."))
        }

        let deviceId = DeviceIdentifier.getDeviceId()
        await pullAuthorizedDevice(deviceId: deviceId)
        let isAdmin = await authorizedDeviceRepository.isAdminDevice(deviceId: deviceId)

        let pullResult = await pullRemoteChangesLightweight(isAdmin: isAdmin)
        if pullResult.state == .error { return pullResult }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        return .success("Güncellendi (\(durationMs)ms)", isAdmin: isAdmin, count: pullResult.successCount)
    }

    func pushLocalChanges() async -> SyncResult {
        let deviceId = DeviceIdentifier.getDeviceId()
        let isAdmin = await authorizedDeviceRepository.isAdminDevice(deviceId: deviceId)
        return await pushLocalChangesInternal(isAdmin: isAdmin)
    }

    func pullRemoteChanges(isAdmin: Bool) async -> SyncResult {
        let eventsSnapshot: QuerySnapshot
        do {
            eventsSnapshot = try await eventsCollection.getDocuments(source: .server)
        } catch {
            return .error(mapFirebaseException(error))
        }

        var processedEventIds: [String] = []
        for document in eventsSnapshot.documents {
            var data = document.data()
            if data["deleted"] as? Bool == true { continue }
            if data["id"] == nil { data["id"] = document.documentID }
            if case let .success(event) = FirestoreDataValidator.validateEvent(data: data) {
                await eventRepository.insertEvent(event)
                processedEventIds.append(event.id)
            }
        }

        var guestsSyncedCount = 0
        let bannedNames = await redListRepository.getAllActiveRedListNames()

        for eventId in processedEventIds {
            var documents: [QueryDocumentSnapshot] = []
            if let publicSnapshot = try? await guestsCollection(eventId).getDocuments(source: .server) {
                documents.append(contentsOf: publicSnapshot.documents)
            }
            if isAdmin, let secureSnapshot = try? await guestsSecureCollection(eventId).getDocuments(source: .server) {
                documents.append(contentsOf: secureSnapshot.documents)
            }

            for document in documents {
                let processed = await processGuestDocument(
                    document: document,
                    eventId: eventId,
                    bannedNames: bannedNames
                )
                if processed { guestsSyncedCount += 1 }
            }
        }

        return .success("Pull tamamlandı.", isAdmin: isAdmin, count: guestsSyncedCount)
    }

    // MARK: - Lightweight pull (syncWithFirebase çekirdeği)

    private func pullRemoteChangesLightweight(isAdmin: Bool) async -> SyncResult {
        let eventsSnapshot: QuerySnapshot
        do {
            eventsSnapshot = try await eventsCollection.getDocuments(source: .server)
        } catch {
            return .error(mapFirebaseException(error))
        }

        let eventIds: [String] = eventsSnapshot.documents.compactMap { document in
            let data = document.data()
            if data["deleted"] as? Bool == true { return nil }
            return data["id"] as? String ?? document.documentID
        }

        var guestsCount = 0
        for eventId in eventIds {
            if let publicSnapshot = try? await guestsCollection(eventId).getDocuments(source: .server) {
                guestsCount += publicSnapshot.documents.count
            }
            if isAdmin, let secureSnapshot = try? await guestsSecureCollection(eventId).getDocuments(source: .server) {
                guestsCount += secureSnapshot.documents.count
            }
        }

        return .success("Güncellendi", isAdmin: isAdmin, count: guestsCount)
    }

    // MARK: - Full push

    private func pushLocalChangesInternal(isAdmin: Bool) async -> SyncResult {
        let deviceId = DeviceIdentifier.getDeviceId()
        await pushAuthorizedDevice(deviceId: deviceId)

        let allEvents = await eventRepository.allEventsIncludingDeleted()
        var batch = firestore.batch()
        var batchCount = 0

        var guestsByEvent: [String: [Guest]] = [:]
        for event in allEvents where event.deletedAt == nil {
            guestsByEvent[event.id] = await eventRepository.allGuestsByEventIdIncludingDeleted(eventId: event.id)
        }

        do {
            for event in allEvents {
                if batchCount >= Self.maxBatchSize {
                    try await batch.commit()
                    batch = firestore.batch()
                    batchCount = 0
                }

                let eventDoc = eventsCollection.document(event.id)
                if let deletedAt = event.deletedAt {
                    batch.setData(deletedEventData(eventId: event.id, deletedAt: deletedAt, deviceId: deviceId), forDocument: eventDoc, merge: true)
                } else {
                    batch.setData(eventData(event, deviceId: deviceId), forDocument: eventDoc, merge: true)
                }
                batchCount += 1

                guard event.deletedAt == nil else { continue }

                for guest in guestsByEvent[event.id] ?? [] {
                    if batchCount >= Self.maxBatchSize {
                        try await batch.commit()
                        batch = firestore.batch()
                        batchCount = 0
                    }

                    let targetCollection = guest.isRedListPending
                        ? guestsSecureCollection(event.id)
                        : guestsCollection(event.id)

                    // FAIL-SAFE: Karşı koleksiyondaki eski dokümanı sil.
                    if guest.isRedListPending {
                        batch.deleteDocument(guestsCollection(event.id).document(guest.id))
                    } else if isAdmin {
                        batch.deleteDocument(guestsSecureCollection(event.id).document(guest.id))
                    }

                    let guestDoc = targetCollection.document(guest.id)
                    let data = guest.deletedAt != nil
                        ? deletedGuestData(guest, deviceId: deviceId)
                        : guestData(guest, deviceId: deviceId)
                    batch.setData(data, forDocument: guestDoc, merge: true)
                    batchCount += 1
                }
            }

            if batchCount > 0 { try await batch.commit() }
            return .success("Yerel değişiklikler gönderildi.", isAdmin: isAdmin)
        } catch {
            Self.logger.error("Push error: \(error.localizedDescription, privacy: .public)")
            return .success("Kısmi başarı (Push hatası)", isAdmin: isAdmin)
        }
    }

    // MARK: - Guest processing (full pull)

    private func processGuestDocument(
        document: QueryDocumentSnapshot,
        eventId: String,
        bannedNames: Set<String>
    ) async -> Bool {
        var data = document.data()
        let guestId = data["id"] as? String ?? document.documentID

        if data["deleted"] as? Bool == true {
            await eventRepository.deleteGuest(guestId: guestId, eventId: eventId)
            return false
        }

        data["id"] = guestId
        guard case let .success(guest) = FirestoreDataValidator.validateGuest(data: data, eventId: eventId) else {
            return false
        }

        // Sunucu otoritedir: onaylanmış misafiri tekrar pending'e çevirmeyiz.
        // Sadece zaten pending olan + yerel banlı isim eşleşmesinde pending korunur (no-op).
        await eventRepository.insertGuestLocally(guest)
        return true
    }

    // MARK: - Authorized device

    private func pullAuthorizedDevice(deviceId: String) async {
        do {
            let document = try await authorizedDevicesCollection.document(deviceId).getDocument(source: .server)
            if document.exists, let data = document.data() {
                if case let .success(device) = FirestoreDataValidator.validateAuthorizedDevice(data: data) {
                    await authorizedDeviceRepository.addAuthorizedDevice(
                        deviceId: device.deviceId,
                        deviceName: device.deviceName,
                        authorizedBy: device.authorizedBy,
                        isPermanent: device.isPermanent,
                        sessionTimeoutMinutes: device.sessionTimeoutMinutes,
                        isAdmin: device.isAdmin
                    )
                }
            } else {
                let userEmail = Auth.auth().currentUser?.email ?? ""
                await authorizedDeviceRepository.registerDeviceRemotely(
                    deviceId: deviceId,
                    deviceName: DeviceIdentifier.getDeviceName(),
                    userEmail: userEmail
                )
            }
        } catch {
            Self.logger.warning("pullAuthorizedDevice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pushAuthorizedDevice(deviceId: String) async {
        guard let local = await authorizedDeviceRepository.getAuthorizedDevice(deviceId: deviceId) else { return }
        let data: [String: Any] = [
            "deviceId": deviceId,
            "isAdmin": local.isAdmin,
            "lastModified": FieldValue.serverTimestamp(),
        ]
        do {
            try await authorizedDevicesCollection.document(deviceId).setData(data, merge: true)
        } catch {
            Self.logger.warning("pushAuthorizedDevice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Firestore payload builders

    private func eventData(_ event: Event, deviceId: String) -> [String: Any] {
        [
            "id": event.id,
            "title": event.title,
            "date": event.date,
            "location": event.location,
            "startTime": event.startTime,
            "status": event.status.rawValue,
            "deleted": false,
            "lastModified": FieldValue.serverTimestamp(),
            "modifiedBy": deviceId,
        ]
    }

    private func deletedEventData(eventId: String, deletedAt: String, deviceId: String) -> [String: Any] {
        [
            "id": eventId,
            "deleted": true,
            "deletedAt": deletedAt,
            "lastModified": FieldValue.serverTimestamp(),
            "modifiedBy": deviceId,
        ]
    }

    private func guestData(_ guest: Guest, deviceId: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": guest.id,
            "eventId": guest.eventId,
            "name": guest.name,
            "title": guest.title,
            "arrivalMethod": guest.arrivalMethod.rawValue,
            "plate": guest.plate ?? "",
            "model": guest.model ?? "",
            "securityCheck": guest.securityCheck,
            "status": guest.status.rawValue,
            "deleted": false,
            "isRedListPending": guest.isRedListPending,
            "note": guest.note ?? "",
            "expectedTime": guest.expectedTime ?? "",
            "sectionTitle": guest.sectionTitle ?? "",
            "participationCategory": guest.participationCategory?.rawValue ?? "",
            "lastModified": FieldValue.serverTimestamp(),
            "modifiedBy": deviceId,
        ]
        if let entryTime = guest.entryTime, !entryTime.isEmpty {
            data["entryTime"] = entryTime
        } else {
            data["entryTime"] = FieldValue.delete()
        }
        if let exitTime = guest.exitTime, !exitTime.isEmpty {
            data["exitTime"] = exitTime
        } else {
            data["exitTime"] = FieldValue.delete()
        }
        if let photoUri = guest.photoUri, !photoUri.isEmpty {
            data["photoUri"] = photoUri
        }
        return data
    }

    private func deletedGuestData(_ guest: Guest, deviceId: String) -> [String: Any] {
        [
            "id": guest.id,
            "eventId": guest.eventId,
            "deleted": true,
            "deletedAt": guest.deletedAt ?? ISO8601DateFormatter().string(from: Date()),
            "lastModified": FieldValue.serverTimestamp(),
            "modifiedBy": deviceId,
        ]
    }

    // MARK: - Helpers

    private func isOnline() async -> Bool {
        await MainActor.run { NetworkMonitor.shared.isConnected }
    }

    private func mapFirebaseException(_ error: Error) -> SyncError {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return .permissionDenied(collection: "sync", deviceId: DeviceIdentifier.getDeviceId())
        }
        return .unknownError(message: error.localizedDescription, context: "firebase")
    }
}
