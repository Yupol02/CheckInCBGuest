import FirebaseFirestore
import Foundation
import os.log

/// Firestore tabanlı `AuthorizedDeviceRepository` (Android `FirebaseAuthorizedDeviceRepository`).
///
/// `authorized_devices` koleksiyonu — belge ID = `deviceId` (SHA-256).
/// Önbellek ve throttle için `actor` izolasyonu kullanılır; yarış durumu derleme zamanında engellenir.
actor FirebaseAuthorizedDeviceRepository: AuthorizedDeviceRepository {

    // MARK: - Constants

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "FirebaseAuthorizedDeviceRepo")
    private static let collectionName = "authorized_devices"
    private static let updateThrottle: TimeInterval = 60.0
    private static let deviceCacheTTL: TimeInterval = 45.0
    private static let deviceCacheMaxSize = 64
    private static let batchChunkSize = 500

    // MARK: - Cache

    private struct CachedDevice {
        let entity: AuthorizedDevice
        let expiresAt: Date
    }

    private let firestore: Firestore
    private var lastUpdateCache: [String: Date] = [:]
    private var deviceCache: [String: CachedDevice] = [:]

    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let iso8601FormatterFallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Init

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    private var authorizedDevicesCollection: CollectionReference {
        firestore.collection(Self.collectionName)
    }

    // MARK: - AuthorizedDeviceRepository

    func isDeviceAuthorized(deviceId: String) async -> Bool {
        guard let device = await getAuthorizedDevice(deviceId: deviceId) else {
            return false
        }

        if device.isPermanent {
            await updateLastUsedAt(deviceId: deviceId)
            return true
        }

        if let sessionTimeout = device.sessionTimeoutMinutes {
            guard let authorizedAt = parseDate(from: device.authorizedAt) else {
                await removeAuthorizedDevice(deviceId: deviceId)
                return false
            }

            let elapsedMinutes = minutesBetween(authorizedAt, and: Date())
            if elapsedMinutes > sessionTimeout {
                await removeAuthorizedDevice(deviceId: deviceId)
                lastUpdateCache.removeValue(forKey: deviceId)
                deviceCache.removeValue(forKey: deviceId)
                return false
            }
        }

        await updateLastUsedAt(deviceId: deviceId)
        return true
    }

    func addAuthorizedDevice(
        deviceId: String,
        deviceName: String?,
        authorizedBy: String,
        isPermanent: Bool,
        sessionTimeoutMinutes: Int64?,
        isAdmin: Bool
    ) async {
        let now = nowISO8601String()
        let data = toFirestoreMap(
            deviceId: deviceId,
            deviceName: deviceName,
            authorizedBy: authorizedBy,
            isPermanent: isPermanent,
            sessionTimeoutMinutes: sessionTimeoutMinutes,
            isAdmin: isAdmin,
            authorizedAt: now,
            lastUsedAt: now
        )

        do {
            try await authorizedDevicesCollection
                .document(deviceId)
                .setData(data, merge: true)

            lastUpdateCache[deviceId] = Date()
            let entity = AuthorizedDevice(
                deviceId: deviceId,
                deviceName: deviceName,
                authorizedAt: now,
                authorizedBy: authorizedBy,
                isPermanent: isPermanent,
                sessionTimeoutMinutes: sessionTimeoutMinutes,
                lastUsedAt: now,
                isAdmin: isAdmin
            )
            evictCacheIfNeeded()
            deviceCache[deviceId] = CachedDevice(
                entity: entity,
                expiresAt: Date().addingTimeInterval(Self.deviceCacheTTL)
            )
        } catch {
            Self.logger.error("addAuthorizedDevice error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func registerDeviceRemotely(deviceId: String, deviceName: String, userEmail: String) async {
        do {
            let isAdmin = AppAuth.isAdminEmail(userEmail)
            let now = nowISO8601String()
            let authorizedBy: String
            if userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                authorizedBy = "AUTO_REGISTRATION"
            } else {
                authorizedBy = "AUTO_REGISTRATION:\(userEmail)"
            }

            let data = toFirestoreMap(
                deviceId: deviceId,
                deviceName: deviceName,
                authorizedBy: authorizedBy,
                isPermanent: true,
                sessionTimeoutMinutes: nil,
                isAdmin: isAdmin,
                authorizedAt: now,
                lastUsedAt: now
            )

            try await authorizedDevicesCollection
                .document(deviceId)
                .setData(data, merge: true)

            lastUpdateCache[deviceId] = Date()
            let entity = AuthorizedDevice(
                deviceId: deviceId,
                deviceName: deviceName,
                authorizedAt: now,
                authorizedBy: authorizedBy,
                isPermanent: true,
                sessionTimeoutMinutes: nil,
                lastUsedAt: now,
                isAdmin: isAdmin
            )
            evictCacheIfNeeded()
            deviceCache[deviceId] = CachedDevice(
                entity: entity,
                expiresAt: Date().addingTimeInterval(Self.deviceCacheTTL)
            )

            let emailPreview = String(userEmail.prefix(20))
            Self.logger.debug("Device registered: \(deviceName, privacy: .public), isAdmin=\(isAdmin), email=\(emailPreview, privacy: .public)...")
        } catch {
            Self.logger.error("Remote device registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func getAuthorizedDevice(deviceId: String) async -> AuthorizedDevice? {
        do {
            let now = Date()
            if let cached = deviceCache[deviceId] {
                if cached.expiresAt > now {
                    return cached.entity
                }
                deviceCache.removeValue(forKey: deviceId)
            }

            let snapshot = try await authorizedDevicesCollection
                .document(deviceId)
                .getDocument()

            guard let rawData = snapshot.data() else {
                return nil
            }

            guard let entity = Self.parseToEntity(deviceId: deviceId, data: rawData) else {
                return nil
            }

            evictCacheIfNeeded()
            deviceCache[deviceId] = CachedDevice(
                entity: entity,
                expiresAt: now.addingTimeInterval(Self.deviceCacheTTL)
            )
            return entity
        } catch {
            return nil
        }
    }

    func isAdminDevice(deviceId: String) async -> Bool {
        let device = await getAuthorizedDevice(deviceId: deviceId)
        return device?.isAdmin == true
    }

    nonisolated func adminDevices() -> AsyncStream<[AuthorizedDevice]> {
        let firestore = firestore
        return Self.makeDevicesStream(
            firestore: firestore,
            queryBuilder: { collection in
                collection
                    .whereField("isAdmin", isEqualTo: true)
                    .order(by: "authorizedAt", descending: true)
            }
        )
    }

    func removeAuthorizedDevice(deviceId: String) async {
        do {
            try await authorizedDevicesCollection.document(deviceId).delete()
            lastUpdateCache.removeValue(forKey: deviceId)
            deviceCache.removeValue(forKey: deviceId)
        } catch {
            Self.logger.error("removeAuthorizedDevice error: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func allAuthorizedDevices() -> AsyncStream<[AuthorizedDevice]> {
        let firestore = firestore
        return Self.makeDevicesStream(
            firestore: firestore,
            queryBuilder: { collection in
                collection.order(by: "authorizedAt", descending: true)
            }
        )
    }

    func updateLastUsedAt(deviceId: String) async {
        do {
            let lastUpdate = lastUpdateCache[deviceId] ?? .distantPast
            let now = Date()
            if now.timeIntervalSince(lastUpdate) < Self.updateThrottle {
                return
            }

            let timestamp = nowISO8601String()
            try await authorizedDevicesCollection
                .document(deviceId)
                .setData(["lastUsedAt": timestamp], merge: true)
            lastUpdateCache[deviceId] = now
        } catch {
            // Kritik değil — Android ile aynı: sessizce yutulur.
        }
    }

    func permanentDeviceCount() async -> Int {
        do {
            let snapshot = try await authorizedDevicesCollection
                .whereField("isPermanent", isEqualTo: true)
                .getDocuments()
            return snapshot.count
        } catch {
            return 0
        }
    }

    func totalDeviceCount() async -> Int {
        do {
            let snapshot = try await authorizedDevicesCollection.getDocuments()
            return snapshot.count
        } catch {
            return 0
        }
    }

    func cleanupExpiredAuthorizations() async {
        do {
            let snapshot = try await authorizedDevicesCollection
                .whereField("isPermanent", isEqualTo: false)
                .getDocuments()

            let now = Date()
            let toDelete = snapshot.documents.filter { document in
                let data = document.data()
                guard let timeoutNumber = data["sessionTimeoutMinutes"] as? NSNumber else {
                    return false
                }
                let sessionTimeout = timeoutNumber.int64Value
                guard sessionTimeout > 0 else { return false }

                guard let authorizedAtString = data["authorizedAt"] as? String,
                      !authorizedAtString.isEmpty,
                      let authorizedAt = parseDate(from: authorizedAtString) else {
                    return false
                }

                return minutesBetween(authorizedAt, and: now) > sessionTimeout
            }

            guard !toDelete.isEmpty else { return }

            for chunk in toDelete.chunked(into: Self.batchChunkSize) {
                let batch = firestore.batch()
                for document in chunk {
                    batch.deleteDocument(document.reference)
                    let documentId = document.documentID
                    lastUpdateCache.removeValue(forKey: documentId)
                    deviceCache.removeValue(forKey: documentId)
                }
                try await batch.commit()
            }
        } catch {
            Self.logger.error("cleanupExpiredAuthorizations error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Cache eviction

    private func evictCacheIfNeeded() {
        guard deviceCache.count >= Self.deviceCacheMaxSize else { return }

        let now = Date()
        let expiredKeys = deviceCache.filter { $0.value.expiresAt <= now }.map(\.key)
        for key in expiredKeys {
            deviceCache.removeValue(forKey: key)
        }

        if deviceCache.count >= Self.deviceCacheMaxSize {
            if let oldestKey = deviceCache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                deviceCache.removeValue(forKey: oldestKey)
            }
        }
    }

    // MARK: - Firestore mapping

    private func toFirestoreMap(
        deviceId: String,
        deviceName: String?,
        authorizedBy: String,
        isPermanent: Bool,
        sessionTimeoutMinutes: Int64?,
        isAdmin: Bool,
        authorizedAt: String,
        lastUsedAt: String?
    ) -> [String: Any] {
        var map: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": deviceName ?? "",
            "authorizedBy": authorizedBy,
            "isPermanent": isPermanent,
            "isAdmin": isAdmin,
            "authorizedAt": authorizedAt,
            "lastUsedAt": lastUsedAt ?? authorizedAt,
        ]
        if let sessionTimeoutMinutes {
            map["sessionTimeoutMinutes"] = sessionTimeoutMinutes
        }
        return map
    }

    private static func parseToEntity(deviceId: String, data: [String: Any]) -> AuthorizedDevice? {
        let deviceName = (data["deviceName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceNameOrNil = deviceName?.isEmpty == false ? deviceName : nil

        let authorizedAt: String
        if let raw = data["authorizedAt"] as? String, !raw.isEmpty {
            authorizedAt = raw
        } else {
            authorizedAt = ISO8601DateFormatter().string(from: Date())
        }

        let authorizedBy = (data["authorizedBy"] as? String).flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } ?? "ADMIN"

        let isPermanent = parseBoolStrict(data["isPermanent"], default: true)
        let sessionTimeoutMinutes = parsePositiveInt64(data["sessionTimeoutMinutes"])
        let lastUsedAt = (data["lastUsedAt"] as? String).flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let isAdmin = parseBoolStrict(data["isAdmin"], default: false)

        return AuthorizedDevice(
            deviceId: deviceId,
            deviceName: deviceNameOrNil,
            authorizedAt: authorizedAt,
            authorizedBy: authorizedBy,
            isPermanent: isPermanent,
            sessionTimeoutMinutes: sessionTimeoutMinutes,
            lastUsedAt: lastUsedAt,
            isAdmin: isAdmin
        )
    }

    // MARK: - AsyncStream factory

    private static func makeDevicesStream(
        firestore: Firestore,
        queryBuilder: (CollectionReference) -> Query
    ) -> AsyncStream<[AuthorizedDevice]> {
        AsyncStream { continuation in
            let collection = firestore.collection(collectionName)
            let query = queryBuilder(collection)

            let registration = query.addSnapshotListener { snapshot, error in
                if error != nil {
                    continuation.yield([])
                    return
                }
                guard let snapshot else {
                    continuation.yield([])
                    return
                }

                let devices = snapshot.documents.compactMap { document -> AuthorizedDevice? in
                    parseToEntity(deviceId: document.documentID, data: document.data())
                }
                continuation.yield(devices)
            }

            continuation.onTermination = { @Sendable _ in
                registration.remove()
            }
        }
    }

    // MARK: - Date / time helpers

    private func nowISO8601String() -> String {
        iso8601Formatter.string(from: Date())
    }

    private func parseDate(from isoString: String) -> Date? {
        if let date = iso8601Formatter.date(from: isoString) {
            return date
        }
        if let date = iso8601FormatterFallback.date(from: isoString) {
            return date
        }
        return ISO8601DateFormatter().date(from: isoString)
    }

    /// `ChronoUnit.MINUTES.between` eşleniği — tam dakika farkı.
    private func minutesBetween(_ start: Date, and end: Date) -> Int64 {
        let components = Calendar.current.dateComponents([.minute], from: start, to: end)
        return Int64(components.minute ?? 0)
    }

    // MARK: - Parsing helpers

    private static func parseBoolStrict(_ value: Any?, default defaultValue: Bool) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let string as String:
            switch string.lowercased() {
            case "true": return true
            case "false": return false
            default: return defaultValue
            }
        default:
            return defaultValue
        }
    }

    private static func parsePositiveInt64(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber:
            let longValue = number.int64Value
            return longValue > 0 ? longValue : nil
        case let int as Int:
            return int > 0 ? Int64(int) : nil
        case let int64 as Int64:
            return int64 > 0 ? int64 : nil
        case let double as Double:
            let longValue = Int64(double)
            return longValue > 0 ? longValue : nil
        case let string as String:
            guard let longValue = Int64(string), longValue > 0 else { return nil }
            return longValue
        default:
            return nil
        }
    }
}

// MARK: - Array chunking

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
