import FirebaseFirestore
import Foundation
import os.log

/// Firestore tabanlı `EventRepository` (Android `FirebaseEventRepository`).
///
/// Online-first: Firestore tek vernak. Çoklu snapshot dinleyicileri için dahili kilitli önbellek kullanılır.
final class FirebaseEventRepository: EventRepository, @unchecked Sendable {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "FirebaseEventRepository")
    private static let firestoreBatchLimit = 500

    private enum Collection {
        static let events = "events"
        static let guests = "guests"
        static let guestsSecure = "guests_secure"
    }

    private let firestore: Firestore
    private let redListRepositoryProvider: @Sendable () -> any RedListRepository

    init(
        firestore: Firestore = Firestore.firestore(),
        redListRepositoryProvider: @escaping @Sendable () -> any RedListRepository
    ) {
        self.firestore = firestore
        self.redListRepositoryProvider = redListRepositoryProvider
    }

    // MARK: - Collection paths

    private var eventsCollection: CollectionReference {
        firestore.collection(Collection.events)
    }

    private func guestsCollection(eventId: String) -> CollectionReference {
        precondition(!eventId.isEmpty && !eventId.contains("/"), "Invalid eventId: \(eventId)")
        return eventsCollection.document(eventId).collection(Collection.guests)
    }

    private func guestsSecureCollection(eventId: String) -> CollectionReference {
        precondition(!eventId.isEmpty && !eventId.contains("/"), "Invalid eventId: \(eventId)")
        return eventsCollection.document(eventId).collection(Collection.guestsSecure)
    }

    // MARK: - AsyncStream

    func allEvents() -> AsyncStream<[Event]> {
        let firestore = firestore
        return AsyncStream { continuation in
            let registration = firestore.collection(Collection.events).addSnapshotListener { snapshot, error in
                if let error {
                    Self.logger.error("Events listener error: \(error.localizedDescription, privacy: .public)")
                    continuation.yield([])
                    return
                }
                guard let snapshot else {
                    continuation.yield([])
                    return
                }

                let events = snapshot.documents.compactMap { document -> Event? in
                    var data = document.data()
                    if data["deleted"] as? Bool == true { return nil }
                    if data["id"] == nil {
                        data["id"] = document.documentID
                    }
                    switch FirestoreDataValidator.validateEvent(data: data) {
                    case .success(let event):
                        return event
                    case .failure(let reason):
                        Self.logger.warning("Event validation failed: \(reason, privacy: .public)")
                        return nil
                    }
                }
                .sorted { $0.date > $1.date }

                continuation.yield(events)
            }

            continuation.onTermination = { @Sendable _ in
                registration.remove()
            }
        }
    }

    func allGuests() -> AsyncStream<[Guest]> {
        let firestore = firestore
        return AsyncStream { continuation in
            let coordinator = GuestStreamCoordinator()

            func emitMerged() {
                continuation.yield(coordinator.mergedGuests())
            }

            let eventsRegistration = firestore.collection(Collection.events).addSnapshotListener { snapshot, error in
                if error != nil {
                    continuation.yield([])
                    return
                }
                guard let snapshot else {
                    continuation.yield([])
                    return
                }

                let eventIds = snapshot.documents.compactMap { document -> String? in
                    let data = document.data()
                    if data["deleted"] as? Bool == true { return nil }
                    if let id = data["id"] as? String, !id.isEmpty { return id }
                    return document.documentID
                }

                coordinator.resetGuestListeners()

                for eventId in eventIds {
                    let publicRegistration = firestore
                        .collection(Collection.events)
                        .document(eventId)
                        .collection(Collection.guests)
                        .addSnapshotListener { guestSnapshot, guestError in
                            if guestError == nil, let guestSnapshot {
                                let guests = guestSnapshot.documents.compactMap { doc in
                                    Self.parseGuestDocument(data: doc.data(), eventId: eventId)
                                }
                                coordinator.setPublicGuests(guests, for: eventId)
                                emitMerged()
                            }
                        }
                    coordinator.addGuestListener(publicRegistration)

                    let secureRegistration = firestore
                        .collection(Collection.events)
                        .document(eventId)
                        .collection(Collection.guestsSecure)
                        .addSnapshotListener { guestSnapshot, guestError in
                            if guestError == nil, let guestSnapshot {
                                let guests = guestSnapshot.documents.compactMap { doc in
                                    Self.parseGuestDocument(data: doc.data(), eventId: eventId)
                                }
                                coordinator.setSecureGuests(guests, for: eventId)
                                emitMerged()
                            }
                        }
                    coordinator.addGuestListener(secureRegistration)
                }

                emitMerged()
            }

            coordinator.setEventsListener(eventsRegistration)

            continuation.onTermination = { @Sendable _ in
                coordinator.removeAllListeners()
            }
        }
    }

    func guests(byEventId eventId: String) -> AsyncStream<[Guest]> {
        let firestore = firestore
        return AsyncStream { continuation in
            let publicRegistration = firestore
                .collection(Collection.events)
                .document(eventId)
                .collection(Collection.guests)
                .addSnapshotListener { snapshot, error in
                    if error != nil {
                        continuation.yield([])
                        return
                    }
                    guard let snapshot else {
                        continuation.yield([])
                        return
                    }
                    let guests = snapshot.documents.compactMap { document -> Guest? in
                        guard let guest = Self.parseGuestDocument(data: document.data(), eventId: eventId) else {
                            return nil
                        }
                        return guest.isRedListPending ? nil : guest
                    }
                    continuation.yield(guests)
                }

            let secureRegistration = firestore
                .collection(Collection.events)
                .document(eventId)
                .collection(Collection.guestsSecure)
                .addSnapshotListener { _, _ in
                    // Android: secure dinleyicisi yalnızca izin kontrolü; public akış yeterli.
                }

            continuation.onTermination = { @Sendable _ in
                publicRegistration.remove()
                secureRegistration.remove()
            }
        }
    }

    func pendingRedListGuests(eventId: String) -> AsyncStream<[Guest]> {
        let firestore = firestore
        return AsyncStream { continuation in
            let registration = firestore
                .collection(Collection.events)
                .document(eventId)
                .collection(Collection.guestsSecure)
                .addSnapshotListener { snapshot, error in
                    if error != nil {
                        continuation.yield([])
                        return
                    }
                    guard let snapshot else {
                        continuation.yield([])
                        return
                    }
                    let guests = snapshot.documents.compactMap { document -> Guest? in
                        guard let guest = Self.parseGuestDocument(data: document.data(), eventId: eventId) else {
                            return nil
                        }
                        return Guest(
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
                            isRedListPending: true,
                            note: guest.note,
                            expectedTime: guest.expectedTime,
                            sectionTitle: guest.sectionTitle,
                            participationCategory: guest.participationCategory
                        )
                    }
                    continuation.yield(guests)
                }

            continuation.onTermination = { @Sendable _ in
                registration.remove()
            }
        }
    }

    // MARK: - Read

    func allGuestsList() async -> [Guest] {
        let events = await allEventsIncludingDeleted()
        var allGuests: [Guest] = []
        for event in events {
            let guests = await allGuestsByEventIdIncludingDeleted(eventId: event.id)
            allGuests.append(contentsOf: guests)
        }
        return allGuests
    }

    func event(byId eventId: String) async -> Event? {
        do {
            let snapshot = try await eventsCollection.document(eventId).getDocument()
            guard var data = snapshot.data() else { return nil }
            if data["deleted"] as? Bool == true { return nil }
            if data["id"] == nil { data["id"] = snapshot.documentID }
            switch FirestoreDataValidator.validateEvent(data: data) {
            case .success(let event): return event
            case .failure: return nil
            }
        } catch {
            return nil
        }
    }

    func guest(byId id: String) async -> Guest? {
        async let publicGuest = Self.fetchGuestFromCollectionGroup(
            firestore: firestore,
            collectionId: Collection.guests,
            guestId: id,
            includingDeleted: false
        )
        async let secureGuest = Self.fetchGuestFromCollectionGroup(
            firestore: firestore,
            collectionId: Collection.guestsSecure,
            guestId: id,
            includingDeleted: false
        )
        if let guest = await publicGuest { return guest }
        return await secureGuest
    }

    func guest(eventId: String, guestId: String) async -> Guest? {
        let trimmedEventId = eventId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEventId.isEmpty {
            return await guest(byId: guestId)
        }

        async let publicGuest = fetchGuestDocument(
            collection: guestsCollection(eventId: trimmedEventId),
            guestId: guestId,
            eventId: trimmedEventId,
            includingDeleted: false
        )
        async let secureGuest = fetchGuestDocument(
            collection: guestsSecureCollection(eventId: trimmedEventId),
            guestId: guestId,
            eventId: trimmedEventId,
            includingDeleted: false
        )
        if let guest = await publicGuest { return guest }
        return await secureGuest
    }

    func eventIncludingDeleted(byId eventId: String) async -> Event? {
        do {
            let snapshot = try await eventsCollection.document(eventId).getDocument()
            guard var data = snapshot.data() else { return nil }
            if data["id"] == nil { data["id"] = snapshot.documentID }
            switch FirestoreDataValidator.validateEvent(data: data) {
            case .success(let event): return event
            case .failure: return nil
            }
        } catch {
            return nil
        }
    }

    func guestIncludingDeleted(byId guestId: String) async -> Guest? {
        async let publicGuest = Self.fetchGuestFromCollectionGroup(
            firestore: firestore,
            collectionId: Collection.guests,
            guestId: guestId,
            includingDeleted: true
        )
        async let secureGuest = Self.fetchGuestFromCollectionGroup(
            firestore: firestore,
            collectionId: Collection.guestsSecure,
            guestId: guestId,
            includingDeleted: true
        )
        if let guest = await publicGuest { return guest }
        return await secureGuest
    }

    func allEventsIncludingDeleted() async -> [Event] {
        do {
            let snapshot = try await eventsCollection.getDocuments()
            return snapshot.documents.compactMap { document -> Event? in
                var data = document.data()
                if data["id"] == nil { data["id"] = document.documentID }
                switch FirestoreDataValidator.validateEvent(data: data) {
                case .success(let event): return event
                case .failure: return nil
                }
            }
            .sorted { $0.date > $1.date }
        } catch {
            return []
        }
    }

    func allGuestsByEventIdIncludingDeleted(eventId: String) async -> [Guest] {
        await withTaskGroup(of: [Guest].self) { group in
            group.addTask {
                await self.fetchAllGuests(from: self.guestsCollection(eventId: eventId), eventId: eventId)
            }
            group.addTask {
                await self.fetchAllGuests(from: self.guestsSecureCollection(eventId: eventId), eventId: eventId)
            }

            var merged: [Guest] = []
            for await batch in group {
                merged.append(contentsOf: batch)
            }
            return merged
        }
    }

    // MARK: - Cloud

    func fetchGuestsFromRemote(eventId: String, isAdminDevice: Bool) async -> [Guest] {
        var guestsMap: [String: Guest] = [:]

        do {
            let publicSnapshot = try await guestsCollection(eventId: eventId)
                .getDocuments(source: .server)
            for document in publicSnapshot.documents {
                if let guest = Self.parseGuestDocument(data: document.data(), eventId: eventId) {
                    guestsMap[guest.id] = guest
                }
            }
        } catch {
            Self.logger.error("Public fetch error: \(error.localizedDescription, privacy: .public)")
        }

        if isAdminDevice {
            do {
                let secureSnapshot = try await guestsSecureCollection(eventId: eventId)
                    .getDocuments(source: .server)
                for document in secureSnapshot.documents {
                    if let guest = Self.parseGuestDocument(data: document.data(), eventId: eventId) {
                        guestsMap[guest.id] = guest
                    }
                }
            } catch {
                Self.logger.error("Secure fetch error: \(error.localizedDescription, privacy: .public)")
            }
        }

        return Array(guestsMap.values)
    }

    func uploadGuestToRemote(_ guest: Guest) async {
        let isSecure = guest.isRedListPending || guest.status == .pendingApproval
        let collection = isSecure
            ? guestsSecureCollection(eventId: guest.eventId)
            : guestsCollection(eventId: guest.eventId)

        do {
            try await collection
                .document(guest.id)
                .setData(toGuestMap(guest), merge: true)
        } catch {
            Self.logger.error("uploadGuestToRemote error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Event writes

    func insertEvent(_ event: Event) async {
        let data: [String: Any] = [
            "id": event.id,
            "title": event.title,
            "date": event.date,
            "location": event.location,
            "startTime": event.startTime,
            "status": event.status.rawValue,
            "deleted": false,
            "deletedAt": "",
        ]
        do {
            try await eventsCollection.document(event.id).setData(data, merge: true)
        } catch {
            Self.logger.error("insertEvent error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func updateEvent(_ event: Event) async {
        let data: [String: Any] = [
            "id": event.id,
            "title": event.title,
            "date": event.date,
            "location": event.location,
            "startTime": event.startTime,
            "status": event.status.rawValue,
            "deletedAt": event.deletedAt ?? "",
            "deleted": event.deletedAt != nil,
        ]
        do {
            try await eventsCollection.document(event.id).setData(data, merge: true)
        } catch {
            Self.logger.error("updateEvent error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteEvent(eventId: String) async {
        let deletedAt = ISO8601DateFormatter().string(from: Date())
        do {
            try await eventsCollection.document(eventId).updateData([
                "deleted": true,
                "deletedAt": deletedAt,
            ])

            let guests = await allGuestsByEventIdIncludingDeleted(eventId: eventId)
            for guest in guests where guest.deletedAt == nil {
                await deleteGuest(guestId: guest.id, eventId: eventId)
            }
        } catch {
            Self.logger.error("deleteEvent error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteGuestsByEventId(eventId: String) async {
        let guests = await allGuestsByEventIdIncludingDeleted(eventId: eventId)
        for guest in guests where guest.deletedAt == nil {
            await deleteGuest(guestId: guest.id, eventId: eventId)
        }
    }

    func deleteEventsBatch(eventIds: [String]) async -> BatchDeleteResult {
        if eventIds.isEmpty {
            return BatchDeleteResult(successCount: 0, failedCount: 0, errors: [])
        }

        var successCount = 0
        for eventId in eventIds {
            do {
                await deleteEvent(eventId: eventId)
                successCount += 1
            } catch {
                Self.logger.error("deleteEvent failed: \(eventId, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            }
        }
        return BatchDeleteResult(
            successCount: successCount,
            failedCount: eventIds.count - successCount,
            errors: []
        )
    }

    // MARK: - Guest writes

    func insertGuest(_ guest: Guest) async {
        var finalGuest = guest
        let isAlreadyFlagged = guest.isRedListPending || guest.status == .pendingApproval

        if !isAlreadyFlagged {
            let redListRepository = redListRepositoryProvider()
            if let match = await redListRepository.getActiveRedListMember(byName: guest.name) {
                _ = match
                finalGuest = Guest(
                    id: guest.id,
                    eventId: guest.eventId,
                    name: guest.name,
                    title: guest.title,
                    arrivalMethod: guest.arrivalMethod,
                    plate: guest.plate,
                    model: guest.model,
                    securityCheck: guest.securityCheck,
                    status: .pendingApproval,
                    entryTime: guest.entryTime,
                    exitTime: guest.exitTime,
                    photoUri: guest.photoUri,
                    deletedAt: guest.deletedAt,
                    isRedListPending: true,
                    note: guest.note,
                    expectedTime: guest.expectedTime,
                    sectionTitle: guest.sectionTitle,
                    participationCategory: guest.participationCategory
                )
            }
        }

        await uploadGuestToRemote(finalGuest)
    }

    func insertGuestLocally(_ guest: Guest) async {
        await uploadGuestToRemote(guest)
    }

    func insertGuests(_ guests: [Guest]) async {
        guard !guests.isEmpty else { return }

        for chunk in guests.chunked(into: Self.firestoreBatchLimit) {
            let batch = firestore.batch()
            for guest in chunk {
                let isSecure = guest.isRedListPending || guest.status == .pendingApproval
                let reference: DocumentReference
                if isSecure {
                    reference = guestsSecureCollection(eventId: guest.eventId).document(guest.id)
                } else {
                    reference = guestsCollection(eventId: guest.eventId).document(guest.id)
                }
                let clearedGuest = Guest(
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
                    deletedAt: nil,
                    isRedListPending: guest.isRedListPending,
                    note: guest.note,
                    expectedTime: guest.expectedTime,
                    sectionTitle: guest.sectionTitle,
                    participationCategory: guest.participationCategory
                )
                batch.setData(toGuestMap(clearedGuest), forDocument: reference, merge: true)
            }
            do {
                try await batch.commit()
            } catch {
                Self.logger.error("insertGuests batch error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func updateGuest(_ guest: Guest) async {
        await uploadGuestToRemote(guest)
    }

    func updateGuests(_ guests: [Guest]) async {
        for guest in guests {
            await uploadGuestToRemote(guest)
        }
    }

    func deleteGuest(guestId: String, eventId: String?) async {
        let deletedAt = ISO8601DateFormatter().string(from: Date())
        let updates: [String: Any] = [
            "deleted": true,
            "deletedAt": deletedAt,
        ]

        if let eventId = eventId?.trimmingCharacters(in: .whitespacesAndNewlines), !eventId.isEmpty {
            do {
                try await guestsCollection(eventId: eventId).document(guestId).updateData(updates)
            } catch { /* public koleksiyonda yok */ }
            do {
                try await guestsSecureCollection(eventId: eventId).document(guestId).updateData(updates)
            } catch { /* secure koleksiyonda yok */ }
            return
        }

        guard let guest = await guest(byId: guestId) else { return }
        do {
            try await guestsCollection(eventId: guest.eventId).document(guestId).updateData(updates)
        } catch { }
        do {
            try await guestsSecureCollection(eventId: guest.eventId).document(guestId).updateData(updates)
        } catch { }
    }

    func deleteGuestsBatch(guestIds: [String]) async -> BatchDeleteResult {
        if guestIds.isEmpty {
            return BatchDeleteResult(successCount: 0, failedCount: 0, errors: [])
        }

        var successCount = 0
        for guestId in guestIds {
            await deleteGuest(guestId: guestId, eventId: nil)
            successCount += 1
        }
        return BatchDeleteResult(
            successCount: successCount,
            failedCount: guestIds.count - successCount,
            errors: []
        )
    }

    func approveGuest(_ guest: Guest) async -> RepoResult<Void> {
        do {
            let secureRef = guestsSecureCollection(eventId: guest.eventId).document(guest.id)
            let publicRef = guestsCollection(eventId: guest.eventId).document(guest.id)

            let approvedGuest = Guest(
                id: guest.id,
                eventId: guest.eventId,
                name: guest.name,
                title: guest.title,
                arrivalMethod: guest.arrivalMethod,
                plate: guest.plate,
                model: guest.model,
                securityCheck: true,
                status: .pending,
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

            let data: [String: Any] = [
                "id": approvedGuest.id,
                "eventId": approvedGuest.eventId,
                "name": approvedGuest.name,
                "title": approvedGuest.title,
                "arrivalMethod": approvedGuest.arrivalMethod.rawValue,
                "status": approvedGuest.status.rawValue,
                "isRedListPending": false,
                "securityCheck": true,
                "note": approvedGuest.note ?? "",
                "deleted": false,
                "expectedTime": approvedGuest.expectedTime ?? "",
                "sectionTitle": approvedGuest.sectionTitle ?? "",
                "participationCategory": approvedGuest.participationCategory?.rawValue ?? "",
            ]

            _ = try await firestore.runTransaction { transaction, _ in
                transaction.setData(data, forDocument: publicRef, merge: true)
                transaction.deleteDocument(secureRef)
                return nil
            }

            return .success(())
        } catch {
            return .failure(RepositoryError(error))
        }
    }

    // MARK: - Mapping

    private func toGuestMap(_ guest: Guest) -> [String: Any] {
        var map: [String: Any] = [
            "id": guest.id,
            "eventId": guest.eventId,
            "name": guest.name,
            "title": guest.title,
            "arrivalMethod": guest.arrivalMethod.rawValue,
            "plate": guest.plate ?? "",
            "model": guest.model ?? "",
            "securityCheck": guest.securityCheck,
            "status": guest.status.rawValue,
            "photoUri": guest.photoUri ?? "",
            "isRedListPending": guest.isRedListPending,
            "deletedAt": guest.deletedAt ?? "",
            "deleted": guest.deletedAt != nil,
            "note": guest.note ?? "",
            "expectedTime": guest.expectedTime ?? "",
            "sectionTitle": guest.sectionTitle ?? "",
            "participationCategory": guest.participationCategory?.rawValue ?? "",
        ]

        if let entryTime = guest.entryTime, !entryTime.isEmpty {
            map["entryTime"] = entryTime
        } else {
            map["entryTime"] = FieldValue.delete()
        }

        if let exitTime = guest.exitTime, !exitTime.isEmpty {
            map["exitTime"] = exitTime
        } else {
            map["exitTime"] = FieldValue.delete()
        }

        return map
    }

    private static func parseGuestDocument(data: [String: Any], eventId: String) -> Guest? {
        if data["deleted"] as? Bool == true { return nil }
        switch FirestoreDataValidator.validateGuest(data: data, eventId: eventId) {
        case .success(let guest):
            return guest
        case .failure:
            return nil
        }
    }

    // MARK: - Fetch helpers

    private func fetchAllGuests(from collection: CollectionReference, eventId: String) async -> [Guest] {
        do {
            let snapshot = try await collection.getDocuments()
            return snapshot.documents.compactMap { document in
                Self.parseGuestDocument(data: document.data(), eventId: eventId)
            }
        } catch {
            return []
        }
    }

    private func fetchGuestDocument(
        collection: CollectionReference,
        guestId: String,
        eventId: String,
        includingDeleted: Bool
    ) async -> Guest? {
        do {
            let snapshot = try await collection.document(guestId).getDocument()
            guard let data = snapshot.data() else { return nil }
            if !includingDeleted, data["deleted"] as? Bool == true { return nil }
            switch FirestoreDataValidator.validateGuest(data: data, eventId: eventId) {
            case .success(let guest): return guest
            case .failure: return nil
            }
        } catch {
            return nil
        }
    }

    private static func fetchGuestFromCollectionGroup(
        firestore: Firestore,
        collectionId: String,
        guestId: String,
        includingDeleted: Bool
    ) async -> Guest? {
        do {
            let snapshot = try await firestore
                .collectionGroup(collectionId)
                .whereField("id", isEqualTo: guestId)
                .limit(to: 1)
                .getDocuments()

            for document in snapshot.documents {
                let data = document.data()
                if !includingDeleted, data["deleted"] as? Bool == true { continue }
                guard let eventId = data["eventId"] as? String, !eventId.isEmpty else { continue }
                switch FirestoreDataValidator.validateGuest(data: data, eventId: eventId) {
                case .success(let guest):
                    return guest
                case .failure:
                    continue
                }
            }
            return nil
        } catch {
            return nil
        }
    }
}

// MARK: - Guest stream coordinator

/// `getAllGuests` için thread-safe dinleyici ve önbellek yönetimi.
private final class GuestStreamCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var publicCache: [String: [Guest]] = [:]
    private var secureCache: [String: [Guest]] = [:]
    private var eventsListener: ListenerRegistration?
    private var guestListeners: [ListenerRegistration] = []

    func setEventsListener(_ registration: ListenerRegistration) {
        lock.lock()
        defer { lock.unlock() }
        eventsListener = registration
    }

    func addGuestListener(_ registration: ListenerRegistration) {
        lock.lock()
        defer { lock.unlock() }
        guestListeners.append(registration)
    }

    /// Yalnızca misafir alt dinleyicilerini kaldırır; ana etkinlik dinleyicisi aktif kalır.
    func resetGuestListeners() {
        lock.lock()
        defer { lock.unlock() }
        guestListeners.forEach { $0.remove() }
        guestListeners.removeAll()
        publicCache.removeAll()
        secureCache.removeAll()
    }

    func removeAllListeners() {
        lock.lock()
        defer { lock.unlock() }
        guestListeners.forEach { $0.remove() }
        guestListeners.removeAll()
        eventsListener?.remove()
        eventsListener = nil
        publicCache.removeAll()
        secureCache.removeAll()
    }

    func setPublicGuests(_ guests: [Guest], for eventId: String) {
        lock.lock()
        defer { lock.unlock() }
        publicCache[eventId] = guests
    }

    func setSecureGuests(_ guests: [Guest], for eventId: String) {
        lock.lock()
        defer { lock.unlock() }
        secureCache[eventId] = guests
    }

    func mergedGuests() -> [Guest] {
        lock.lock()
        defer { lock.unlock() }
        let eventIds = Set(publicCache.keys).union(secureCache.keys)
        return eventIds.flatMap { eventId in
            (publicCache[eventId] ?? []) + (secureCache[eventId] ?? [])
        }
    }
}

// MARK: - Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}
