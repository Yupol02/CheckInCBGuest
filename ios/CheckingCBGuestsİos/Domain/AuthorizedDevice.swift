import Foundation

/// Yetkili cihaz kaydı (Android `AuthorizedDeviceEntity` eşleniği).
///
/// Kalıcı (admin) veya PIN tabanlı oturum yetkilendirmesini temsil eder.
struct AuthorizedDevice: Identifiable, Codable, Hashable, Sendable {
    var id: String { deviceId }

    /// SHA-256 ile hashlenmiş cihaz kimliği.
    let deviceId: String
    let deviceName: String?
    /// ISO 8601 zaman damgası.
    let authorizedAt: String
    /// `"PIN"` veya `"ADMIN"`.
    let authorizedBy: String
    let isPermanent: Bool
    let sessionTimeoutMinutes: Int64?
    let lastUsedAt: String?
    let isAdmin: Bool

    init(
        deviceId: String,
        deviceName: String? = nil,
        authorizedAt: String,
        authorizedBy: String,
        isPermanent: Bool = false,
        sessionTimeoutMinutes: Int64? = nil,
        lastUsedAt: String? = nil,
        isAdmin: Bool = false
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.authorizedAt = authorizedAt
        self.authorizedBy = authorizedBy
        self.isPermanent = isPermanent
        self.sessionTimeoutMinutes = sessionTimeoutMinutes
        self.lastUsedAt = lastUsedAt
        self.isAdmin = isAdmin
    }
}

extension AuthorizedDevice {
    static var previewAdmin: AuthorizedDevice {
        AuthorizedDevice(
            deviceId: "preview-device-admin-hash",
            deviceName: "iPad Pro — Güvenlik",
            authorizedAt: "2025-06-01T10:00:00Z",
            authorizedBy: "ADMIN",
            isPermanent: true,
            isAdmin: true
        )
    }

    static var previewPIN: AuthorizedDevice {
        AuthorizedDevice(
            deviceId: "preview-device-pin-hash",
            deviceName: "iPhone — Kapı",
            authorizedAt: "2025-06-15T08:30:00Z",
            authorizedBy: "PIN",
            isPermanent: false,
            sessionTimeoutMinutes: 480,
            lastUsedAt: "2025-06-15T14:00:00Z",
            isAdmin: false
        )
    }
}
