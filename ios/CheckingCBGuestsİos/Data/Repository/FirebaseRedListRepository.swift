import FirebaseFirestore
import Foundation
import os.log

/// Firestore tabanlı `RedListRepository` (Android `FirebaseRedListRepository`).
///
/// `admin_red_list_names` koleksiyonu — belge ID = normalize edilmiş isim.
/// `eventRepositoryProvider` döngüsel bağımlılığı önlemek için lazy çözülür.
actor FirebaseRedListRepository: RedListRepository {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "FirebaseRedListRepository")
    private static let collectionName = "admin_red_list_names"
    private static let emptyQueryMaxLength = 100
    private static let guestIdInQueryChunkSize = 10

    private let firestore: Firestore
    private let eventRepositoryProvider: @Sendable () -> any EventRepository
    private var cachedEventRepository: (any EventRepository)?

    init(
        firestore: Firestore = Firestore.firestore(),
        eventRepositoryProvider: @escaping @Sendable () -> any EventRepository
    ) {
        self.firestore = firestore
        self.eventRepositoryProvider = eventRepositoryProvider
    }

    nonisolated private var adminRedListNamesCollection: CollectionReference {
        firestore.collection(Self.collectionName)
    }

    private func eventRepository() -> any EventRepository {
        if let cachedEventRepository {
            return cachedEventRepository
        }
        let repository = eventRepositoryProvider()
        cachedEventRepository = repository
        return repository
    }

    // MARK: - RedListRepository (normalizasyon)

    nonisolated func normalizeGuestName(_ guestName: String) -> String {
        guestName.normalizeGuestName()
    }

    // MARK: - AsyncStream

    nonisolated func allRedListMembers(isAdmin: Bool) -> AsyncStream<[RedListMember]> {
        let collection = adminRedListNamesCollection
        return AsyncStream { continuation in
            let registration = collection.addSnapshotListener { snapshot, error in
                if let error {
                    Self.logger.error("RedList listener error: \(error.localizedDescription, privacy: .public)")
                    continuation.yield([])
                    return
                }
                guard let snapshot else {
                    continuation.yield([])
                    return
                }

                let members = snapshot.documents.compactMap { document -> RedListMember? in
                    let data = document.data()
                    guard Self.isActive(data) else { return nil }
                    if !isAdmin, data["addedBy"] as? String == "ADMIN" { return nil }
                    return Self.parseDocumentToMember(documentId: document.documentID, data: data)
                }
                .sorted { $0.addedDate > $1.addedDate }

                continuation.yield(members)
            }

            continuation.onTermination = { @Sendable _ in
                registration.remove()
            }
        }
    }

    nonisolated func allRedListGuestIds() -> AsyncStream<Set<String>> {
        makeGuestIdSetStream { data in
            guard Self.isActive(data) else { return nil }
            return Self.nonManualGuestId(from: data)
        }
    }

    nonisolated func adminRedListGuestIds() -> AsyncStream<Set<String>> {
        makeGuestIdSetStream { data in
            guard Self.isActive(data) else { return nil }
            guard data["addedBy"] as? String == "ADMIN" else { return nil }
            return Self.nonManualGuestId(from: data)
        }
    }

    nonisolated func hiddenRedListGuestIds() -> AsyncStream<Set<String>> {
        makeGuestIdSetStream { data in
            guard Self.isActive(data) else { return nil }
            guard data["addedBy"] as? String != "ADMIN" else { return nil }
            return Self.nonManualGuestId(from: data)
        }
    }

    nonisolated func searchRedListMembers(query: String) -> AsyncStream<[RedListMember]> {
        let normalizedQuery = normalizeGuestName(query)
        if normalizedQuery.count > Self.emptyQueryMaxLength {
            return AsyncStream { continuation in
                continuation.yield([])
                continuation.finish()
            }
        }

        let collection = adminRedListNamesCollection
        return AsyncStream { continuation in
            let registration = collection.addSnapshotListener { snapshot, error in
                if error != nil {
                    continuation.yield([])
                    return
                }
                guard let snapshot else {
                    continuation.yield([])
                    return
                }

                let members: [RedListMember]
                if normalizedQuery.isEmpty {
                    members = snapshot.documents.compactMap { document in
                        let data = document.data()
                        guard Self.isActive(data) else { return nil }
                        return Self.parseDocumentToMember(documentId: document.documentID, data: data)
                    }
                } else {
                    members = snapshot.documents
                        .filter { document in
                            let data = document.data()
                            let name = data["name"] as? String ?? document.documentID
                            return name.normalizeGuestName().contains(normalizedQuery)
                        }
                        .compactMap { document in
                            let data = document.data()
                            guard Self.isActive(data) else { return nil }
                            return Self.parseDocumentToMember(documentId: document.documentID, data: data)
                        }
                }

                continuation.yield(members.sorted { $0.addedDate > $1.addedDate })
            }

            continuation.onTermination = { @Sendable _ in
                registration.remove()
            }
        }
    }

    // MARK: - Okuma

    func fetchRedListDirectlyFromCloud() async -> Set<String> {
        do {
            let snapshot = try await adminRedListNamesCollection.getDocuments(source: .server)
            return Set(
                snapshot.documents.compactMap { document -> String? in
                    let isActive = document.data()["isActive"] as? Bool ?? true
                    guard isActive else { return nil }
                    let rawName = document.data()["name"] as? String ?? document.documentID
                    return rawName.normalizeGuestName()
                }
            )
        } catch {
            Self.logger.error("Cloud fetch error: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func getAllActiveRedListNames() async -> Set<String> {
        do {
            let snapshot = try await adminRedListNamesCollection.getDocuments()
            return Set(
                snapshot.documents.compactMap { document -> String? in
                    let data = document.data()
                    guard Self.isActive(data) else { return nil }
                    let name = data["name"] as? String ?? document.documentID
                    return name.normalizeGuestName()
                }
            )
        } catch {
            Self.logger.error("getAllActiveRedListNames error: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func forceUpdateFromFirebase() async {
        // Firebase-only: Room sync artık yok (Android ile aynı no-op).
    }

    func getAdminRedListMember(byName guestName: String) async -> RedListMember? {
        let normalized = normalizeGuestName(guestName)
        guard !normalized.isEmpty else { return nil }

        do {
            let snapshot = try await adminRedListNamesCollection.document(normalized).getDocument()
            guard let data = snapshot.data() else { return nil }
            guard Self.isActive(data) else { return nil }
            guard data["addedBy"] as? String == "ADMIN" else { return nil }
            return Self.parseDocumentToMember(documentId: snapshot.documentID, data: data)
        } catch {
            return nil
        }
    }

    func getActiveRedListMember(byName guestName: String) async -> RedListMember? {
        let normalized = normalizeGuestName(guestName)
        guard !normalized.isEmpty else { return nil }

        do {
            let snapshot = try await adminRedListNamesCollection.document(normalized).getDocument()
            guard let data = snapshot.data() else { return nil }
            guard Self.isActive(data) else { return nil }
            return Self.parseDocumentToMember(documentId: snapshot.documentID, data: data)
        } catch {
            return nil
        }
    }

    func getRedListMember(byGuestId guestId: String) async -> RedListMember? {
        do {
            let snapshot = try await adminRedListNamesCollection
                .whereField("guestId", isEqualTo: guestId)
                .getDocuments()

            guard let document = snapshot.documents.first else { return nil }
            let data = document.data()
            guard Self.isActive(data) else { return nil }
            return Self.parseDocumentToMember(documentId: document.documentID, data: data)
        } catch {
            return nil
        }
    }

    func areGuestsInRedList(guestIds: [String]) async -> [String: Bool] {
        guard !guestIds.isEmpty else { return [:] }

        let uniqueIds = Array(Set(guestIds))
        var found = Set<String>()

        for chunk in uniqueIds.chunked(into: Self.guestIdInQueryChunkSize) {
            do {
                let snapshot = try await adminRedListNamesCollection
                    .whereField("guestId", in: chunk)
                    .getDocuments()

                for document in snapshot.documents {
                    if let guestId = document.data()["guestId"] as? String {
                        found.insert(guestId)
                    }
                }
            } catch {
                Self.logger.error("areGuestsInRedList chunk error: \(error.localizedDescription, privacy: .public)")
            }
        }

        return Dictionary(uniqueKeysWithValues: guestIds.map { ($0, found.contains($0)) })
    }

    // MARK: - Yazma

    func addToRedList(
        guestId: String,
        reason: RedListEntryReason,
        notes: String?,
        addedBy: String?
    ) async -> RedListResult<RedListMember> {
        do {
            guard let guest = await eventRepository().guest(byId: guestId) else {
                return .error(
                    message: "Misafir bulunamadı",
                    errorCode: .guestNotFound
                )
            }

            let normalizedName = normalizeGuestName(guest.name)
            let displayName = formatDisplayName(guest.name)

            let existingSnapshot = try await adminRedListNamesCollection
                .document(normalizedName)
                .getDocument()

            if existingSnapshot.exists {
                let existingData = existingSnapshot.data()
                if existingData?["isActive"] as? Bool == true {
                    return .error(
                        message: "\"\(displayName)\" zaten kırmızı listede.",
                        errorCode: .alreadyInRedList
                    )
                }
            }

            let addedDate = nowISO8601String()
            let member = RedListMember(
                guestId: guestId,
                guestName: displayName,
                reason: reason,
                addedDate: addedDate,
                addedBy: notesTrimmed(addedBy),
                notes: notesTrimmed(notes),
                requiresSpecialPermission: true,
                isActive: true
            )

            let firebaseData = firebaseMemberPayload(
                member: member,
                normalizedName: normalizedName,
                reason: reason,
                addedBy: addedBy ?? "ADMIN",
                notes: notes,
                isManual: false,
                guestId: guestId
            )

            if addedBy == "ADMIN" {
                try await adminRedListNamesCollection
                    .document(normalizedName)
                    .setData(firebaseData, merge: true)
            }

            return .success(member)
        } catch {
            return mapWriteError(error)
        }
    }

    func addManuallyToRedList(
        guestName: String,
        reason: RedListEntryReason,
        notes: String?,
        addedBy: String?
    ) async -> RedListResult<RedListMember> {
        do {
            let normalizedName = normalizeGuestName(guestName)
            let displayName = formatDisplayName(guestName)

            if normalizedName.isEmpty {
                return .error(
                    message: "Misafir adı boş olamaz",
                    errorCode: .invalidInput
                )
            }

            let existingSnapshot = try await adminRedListNamesCollection
                .document(normalizedName)
                .getDocument()

            if existingSnapshot.exists, existingSnapshot.data()?["isActive"] as? Bool == true {
                return .error(
                    message: "\"\(displayName)\" zaten kırmızı listede.",
                    errorCode: .alreadyInRedList
                )
            }

            let manualGuestId = "MANUAL_\(UUID().uuidString)"
            let addedDate = nowISO8601String()
            let member = RedListMember(
                guestId: manualGuestId,
                guestName: displayName,
                reason: reason,
                addedDate: addedDate,
                addedBy: notesTrimmed(addedBy),
                notes: notesTrimmed(notes),
                requiresSpecialPermission: true,
                isActive: true
            )

            let firebaseData = firebaseMemberPayload(
                member: member,
                normalizedName: normalizedName,
                reason: reason,
                addedBy: addedBy ?? "ADMIN",
                notes: notes,
                isManual: true,
                guestId: manualGuestId
            )

            try await adminRedListNamesCollection
                .document(normalizedName)
                .setData(firebaseData, merge: true)

            return .success(member)
        } catch {
            return mapWriteError(error)
        }
    }

    func removeFromRedList(guestId: String) async -> RedListResult<Void> {
        do {
            if let member = await getRedListMember(byGuestId: guestId) {
                let normalized = normalizeGuestName(member.guestName)
                try await adminRedListNamesCollection.document(normalized).delete()
            }
            return .success(())
        } catch {
            return .error(message: error.localizedDescription, underlying: RepositoryError(error))
        }
    }

    func removeFromRedList(byMemberId memberId: String) async -> RedListResult<Void> {
        do {
            let documentRef = adminRedListNamesCollection.document(memberId)
            let snapshot = try await documentRef.getDocument()

            if snapshot.exists {
                try await documentRef.delete()
                return .success(())
            }

            let querySnapshot = try await adminRedListNamesCollection
                .whereField("guestId", isEqualTo: memberId)
                .getDocuments()

            if let document = querySnapshot.documents.first {
                try await document.reference.delete()
            }

            return .success(())
        } catch {
            return .error(message: error.localizedDescription, underlying: RepositoryError(error))
        }
    }

    func updateGuestNameInRedList(guestId: String, newName: String) async {
        guard let member = await getRedListMember(byGuestId: guestId) else { return }

        let oldNormalized = normalizeGuestName(member.guestName)
        let newNormalized = normalizeGuestName(newName)
        let displayName = formatDisplayName(newName)

        do {
            if oldNormalized == newNormalized {
                try await adminRedListNamesCollection
                    .document(oldNormalized)
                    .updateData(["name": displayName])
            } else {
                let oldSnapshot = try await adminRedListNamesCollection.document(oldNormalized).getDocument()
                guard var data = oldSnapshot.data() else { return }

                data["name"] = displayName
                data["normalizedName"] = newNormalized

                try await adminRedListNamesCollection.document(newNormalized).setData(data)
                try await adminRedListNamesCollection
                    .document(oldNormalized)
                    .updateData(["isActive": false])
            }
        } catch {
            Self.logger.error("updateGuestNameInRedList error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func linkManualEntryToRealGuest(
        guestName: String,
        realGuestId: String,
        realGuestName: String
    ) async -> Bool {
        false
    }

    // MARK: - Stream factory

    nonisolated private func makeGuestIdSetStream(
        filter: @escaping @Sendable ([String: Any]) -> String?
    ) -> AsyncStream<Set<String>> {
        let collection = adminRedListNamesCollection
        return AsyncStream { continuation in
            let registration = collection.addSnapshotListener { snapshot, error in
                if error != nil {
                    continuation.yield([])
                    return
                }
                guard let snapshot else {
                    continuation.yield([])
                    return
                }

                let ids = Set(
                    snapshot.documents.compactMap { document -> String? in
                        filter(document.data())
                    }
                )
                continuation.yield(ids)
            }

            continuation.onTermination = { @Sendable _ in
                registration.remove()
            }
        }
    }

    // MARK: - Parsing & formatting

    private func formatDisplayName(_ guestName: String) -> String {
        let trimmed = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed: String
        if let regex = try? NSRegularExpression(pattern: "\\s+") {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            collapsed = regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: " ")
        } else {
            collapsed = trimmed
        }
        return collapsed.uppercased(with: Locale(identifier: "tr_TR"))
    }

    private static func parseDocumentToMember(documentId: String, data: [String: Any]) -> RedListMember? {
        let name = data["name"] as? String ?? documentId
        let guestId = data["guestId"] as? String ?? "SYNCED_\(documentId)"
        let reasonRaw = data["reason"] as? String ?? RedListEntryReason.special.rawValue
        let addedBy = data["addedBy"] as? String
        let addedAt = data["addedAt"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let isActive = data["isActive"] as? Bool ?? true
        let notes = data["notes"] as? String

        let reason = RedListEntryReason(rawValue: reasonRaw) ?? .special

        return RedListMember(
            id: documentId,
            guestId: guestId,
            guestName: formatDisplayNameStatic(name),
            reason: reason,
            addedDate: addedAt,
            addedBy: addedBy,
            notes: notes,
            requiresSpecialPermission: true,
            isActive: isActive
        )
    }

    private static func formatDisplayNameStatic(_ guestName: String) -> String {
        let trimmed = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed: String
        if let regex = try? NSRegularExpression(pattern: "\\s+") {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            collapsed = regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: " ")
        } else {
            collapsed = trimmed
        }
        return collapsed.uppercased(with: Locale(identifier: "tr_TR"))
    }

    private static func isActive(_ data: [String: Any]) -> Bool {
        data["isActive"] as? Bool == true
    }

    private static func nonManualGuestId(from data: [String: Any]) -> String? {
        guard let guestId = data["guestId"] as? String else { return nil }
        guard !guestId.hasPrefix("MANUAL_") else { return nil }
        return guestId
    }

    // MARK: - Firestore payload

    private func firebaseMemberPayload(
        member: RedListMember,
        normalizedName: String,
        reason: RedListEntryReason,
        addedBy: String,
        notes: String?,
        isManual: Bool,
        guestId: String
    ) -> [String: Any] {
        [
            "name": member.guestName,
            "normalizedName": normalizedName,
            "reason": reason.rawValue,
            "addedBy": addedBy,
            "addedAt": member.addedDate,
            "isActive": true,
            "notes": notes ?? "",
            "isManual": isManual,
            "guestId": guestId,
        ]
    }

    private func nowISO8601String() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func notesTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mapWriteError(_ error: Error) -> RedListResult<RedListMember> {
        let message = error.localizedDescription
        let errorCode: RedListErrorCode = message.contains("zaten")
            ? .alreadyInRedList
            : .databaseError
        return .error(
            message: message.isEmpty ? "Hata oluştu" : message,
            underlying: RepositoryError(error),
            errorCode: errorCode
        )
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
