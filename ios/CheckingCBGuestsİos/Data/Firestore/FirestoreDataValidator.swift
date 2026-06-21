import Foundation
import os.log

/// Firestore belgelerini domain modellerine güvenli dönüştürür (Android `DataValidator`).
enum FirestoreDataValidator {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "FirestoreDataValidator")
    private static let maxTitleLength = 200
    private static let maxNameLength = 200
    private static let maxDeviceNameLength = 100

    enum ValidationResult<T: Sendable>: Sendable {
        case success(T)
        case failure(reason: String)
    }

    // MARK: - Event

    static func validateEvent(data: [String: Any]) -> ValidationResult<Event> {
        guard let id = requiredString(data, key: "id") else {
            return .failure(reason: "Event ID boş olamaz")
        }

        guard let title = requiredString(data, key: "title") else {
            return .failure(reason: "Etkinlik başlığı boş olamaz")
        }

        if title.count > maxTitleLength {
            return .failure(reason: "Etkinlik başlığı çok uzun (maksimum \(maxTitleLength) karakter)")
        }

        let date = optionalNonEmptyString(data, key: "date") ?? ""
        let location = optionalNonEmptyString(data, key: "location") ?? ""
        let startTime = optionalNonEmptyString(data, key: "startTime") ?? ""
        let status = parseEnum(EventStatus.self, data: data, key: "status", default: .active)

        let deletedAtRaw = optionalNonEmptyString(data, key: "deletedAt")
        let deletedAt: String?
        if let deletedAtRaw, isValidISO8601Timestamp(deletedAtRaw) {
            deletedAt = deletedAtRaw
        } else {
            if deletedAtRaw != nil {
                logger.warning("Invalid deletedAt timestamp format: \(deletedAtRaw ?? "", privacy: .public)")
            }
            deletedAt = nil
        }

        let event = Event(
            id: id,
            title: title,
            date: date,
            location: location,
            startTime: startTime,
            status: status,
            deletedAt: deletedAt
        )
        return .success(event)
    }

    // MARK: - Guest

    static func validateGuest(data: [String: Any], eventId: String) -> ValidationResult<Guest> {
        guard let id = requiredString(data, key: "id") else {
            return .failure(reason: "Guest ID boş olamaz")
        }

        let guestEventId = optionalNonEmptyString(data, key: "eventId") ?? eventId
        if guestEventId != eventId {
            return .failure(reason: "Misafir eventId uyuşmuyor")
        }

        guard let name = requiredString(data, key: "name") else {
            return .failure(reason: "Misafir adı boş olamaz")
        }

        if name.count > maxNameLength {
            return .failure(reason: "Misafir adı çok uzun (maksimum \(maxNameLength) karakter)")
        }

        let title = optionalNonEmptyString(data, key: "title") ?? ""
        if title.count > maxTitleLength {
            return .failure(reason: "Ünvan çok uzun (maksimum \(maxTitleLength) karakter)")
        }

        let arrivalMethod = parseEnum(ArrivalMethod.self, data: data, key: "arrivalMethod", default: .pedestrian)
        let plate = optionalNonEmptyString(data, key: "plate")
        let model = optionalNonEmptyString(data, key: "model")
        let securityCheck = parseBoolStrict(data["securityCheck"], default: true)
        let status = parseEnum(GuestStatus.self, data: data, key: "status", default: .pending)

        let entryTime = optionalNonEmptyString(data, key: "entryTime").flatMap { value in
            isValidISO8601Timestamp(value) ? value : nil
        }
        let exitTime = optionalNonEmptyString(data, key: "exitTime").flatMap { value in
            isValidISO8601Timestamp(value) ? value : nil
        }
        let photoUri = optionalNonEmptyString(data, key: "photoUri")
        let deletedAt = optionalNonEmptyString(data, key: "deletedAt").flatMap { value in
            isValidISO8601Timestamp(value) ? value : nil
        }
        let note = optionalNonEmptyString(data, key: "note")
        let expectedTime = optionalNonEmptyString(data, key: "expectedTime")
        let isRedListPending = parseBoolStrict(data["isRedListPending"], default: false)
        let sectionTitle = optionalNonEmptyString(data, key: "sectionTitle")

        let participationCategory: ParticipationCategory?
        if let rawCategory = optionalNonEmptyString(data, key: "participationCategory"),
           let parsed = ParticipationCategory(rawValue: rawCategory) {
            participationCategory = parsed
        } else {
            participationCategory = nil
        }

        let guest = Guest(
            id: id,
            eventId: guestEventId,
            name: name,
            title: title,
            arrivalMethod: arrivalMethod,
            plate: plate,
            model: model,
            securityCheck: securityCheck,
            status: status,
            entryTime: entryTime,
            exitTime: exitTime,
            photoUri: photoUri,
            deletedAt: deletedAt,
            isRedListPending: isRedListPending,
            note: note,
            expectedTime: expectedTime,
            sectionTitle: sectionTitle,
            participationCategory: participationCategory
        )
        return .success(guest)
    }

    // MARK: - Authorized Device

    /// Firestore yetkili cihaz belgesini doğrular (Android `DataValidator.validateAuthorizedDevice`).
    ///
    /// Varsayılanlar Android ile birebir: `isPermanent` yoksa `true`, `isAdmin` yoksa `false`,
    /// `authorizedBy` yoksa `"ADMIN"`, `authorizedAt` geçersizse şimdiki zaman.
    static func validateAuthorizedDevice(data: [String: Any]) -> ValidationResult<AuthorizedDevice> {
        guard let deviceId = requiredString(data, key: "deviceId") else {
            return .failure(reason: "Device ID boş olamaz")
        }

        let deviceName = optionalNonEmptyString(data, key: "deviceName")
        if let deviceName, deviceName.count > maxDeviceNameLength {
            logger.warning("Device name too long: \(deviceName.count, privacy: .public) characters, max: \(maxDeviceNameLength, privacy: .public)")
        }

        let authorizedBy = optionalNonEmptyString(data, key: "authorizedBy") ?? "ADMIN"
        let isPermanent = parseBoolStrict(data["isPermanent"], default: true)
        let isAdmin = parseBoolStrict(data["isAdmin"], default: false)
        let sessionTimeoutMinutes = parsePositiveInt64(data["sessionTimeoutMinutes"])

        let authorizedAt: String
        if let raw = optionalNonEmptyString(data, key: "authorizedAt"), isValidISO8601Timestamp(raw) {
            authorizedAt = raw
        } else {
            authorizedAt = ISO8601DateFormatter().string(from: Date())
        }

        let lastUsedAt = optionalNonEmptyString(data, key: "lastUsedAt").flatMap { value in
            isValidISO8601Timestamp(value) ? value : nil
        }

        let device = AuthorizedDevice(
            deviceId: deviceId,
            deviceName: deviceName,
            authorizedAt: authorizedAt,
            authorizedBy: authorizedBy,
            isPermanent: isPermanent,
            sessionTimeoutMinutes: sessionTimeoutMinutes,
            lastUsedAt: lastUsedAt,
            isAdmin: isAdmin
        )
        return .success(device)
    }

    // MARK: - Helpers

    private static func parsePositiveInt64(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber:
            let longValue = number.int64Value
            return longValue > 0 ? longValue : nil
        case let int as Int:
            return int > 0 ? Int64(int) : nil
        case let string as String:
            guard let longValue = Int64(string) else { return nil }
            return longValue > 0 ? longValue : nil
        default:
            return nil
        }
    }

    private static func requiredString(_ data: [String: Any], key: String) -> String? {
        guard let value = data[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalNonEmptyString(_ data: [String: Any], key: String) -> String? {
        guard let value = data[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseEnum<T: RawRepresentable & Sendable>(
        _: T.Type,
        data: [String: Any],
        key: String,
        default defaultValue: T
    ) -> T where T.RawValue == String {
        guard let raw = optionalNonEmptyString(data, key: key),
              let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }

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

    private static func isValidISO8601Timestamp(_ timestamp: String) -> Bool {
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatterWithFractional.date(from: timestamp) != nil {
            return true
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp) != nil
    }
}
