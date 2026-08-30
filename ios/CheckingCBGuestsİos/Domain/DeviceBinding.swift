import Foundation

/// Bir e-postanın bağlı olduğu cihaz (Firestore `device_bindings/{normalizedEmail}`).
///
/// Doküman ID'si normalize edilmiş e-postadır: sahip Firebase Console'da dokümanı
/// e-posta ile bulup silerek bağı sıfırlayabilir. Bağı yalnızca Console silebilir —
/// güvenlik kuralı istemciye `delete` izni vermez.
///
/// Alan adları camelCase, tarihler ISO8601 **string**; mevcut koleksiyonlarla
/// (`authorized_devices`, `events`, ...) aynı sözleşme.
struct DeviceBinding: Identifiable, Codable, Hashable, Sendable {

    var id: String { email }

    /// Normalize edilmiş e-posta; doküman ID'si ile aynı değer.
    let email: String
    /// Bağı kuran Firebase Auth kullanıcısının uid'i.
    let uid: String
    /// `DeviceIdentifier.getDeviceId()` — SHA-256 hex.
    /// `authorized_devices` doküman ID'si ile aynı değerdir.
    let deviceId: String
    /// Kısa, insan okunur cihaz etiketi (ham ID'nin ilk 8 karakteri).
    /// Reddetme mesajında gösterilir ki sahip telefonda cihazı doğrulayabilsin.
    let deviceName: String?
    let boundAt: String
    let lastSeenAt: String?
    /// Şu an yalnızca "ios". Android bu koleksiyona yazmıyor.
    let platform: String

    init(
        email: String,
        uid: String,
        deviceId: String,
        deviceName: String? = nil,
        boundAt: String,
        lastSeenAt: String? = nil,
        platform: String = "ios"
    ) {
        self.email = email
        self.uid = uid
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.boundAt = boundAt
        self.lastSeenAt = lastSeenAt
        self.platform = platform
    }

    /// Firestore dokümanından ayrıştırır. `deviceId` boşsa bağ geçersiz sayılır.
    static func from(documentId: String, data: [String: Any]) -> DeviceBinding? {
        let deviceId = (data["deviceId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !deviceId.isEmpty else { return nil }

        let deviceName = (data["deviceName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lastSeenAt = (data["lastSeenAt"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let boundAt = (data["boundAt"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return DeviceBinding(
            email: (data["email"] as? String) ?? documentId,
            uid: (data["uid"] as? String) ?? "",
            deviceId: deviceId,
            deviceName: deviceName?.isEmpty == false ? deviceName : nil,
            boundAt: boundAt?.isEmpty == false ? (boundAt ?? "") : AppAuth.nowISO8601String(),
            lastSeenAt: lastSeenAt?.isEmpty == false ? lastSeenAt : nil,
            platform: (data["platform"] as? String) ?? "ios"
        )
    }

    func toFirestoreMap() -> [String: Any] {
        [
            "email": email,
            "uid": uid,
            "deviceId": deviceId,
            "deviceName": deviceName ?? "",
            "boundAt": boundAt,
            "lastSeenAt": lastSeenAt ?? boundAt,
            "platform": platform,
        ]
    }
}

extension DeviceBinding {
    /// `#Preview` ve testler için örnek veri.
    static var preview: DeviceBinding {
        DeviceBinding(
            email: "test@checking.com",
            uid: "preview-uid-0001",
            deviceId: String(repeating: "a", count: 64),
            deviceName: "A1B2C3D4",
            boundAt: "2026-08-30T10:00:00.000Z",
            lastSeenAt: "2026-08-30T12:30:00.000Z"
        )
    }
}
