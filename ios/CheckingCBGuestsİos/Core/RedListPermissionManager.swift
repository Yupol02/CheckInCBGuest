import Foundation

/// Kırmızı liste işlemleri için PIN tabanlı yetki oturumu (Android `PermissionManager`).
///
/// Oturum `UserDefaults`'ta saklanır (Android `SharedPreferences` eşleniği). PIN doğru
/// girildiğinde belirli bir süre boyunca (varsayılan 30 dk) kırmızı liste check-in
/// işlemlerine izin verilir.
enum RedListPermissionManager {

    /// Android ile birebir aynı admin PIN değeri.
    static let adminPin = "145334"

    private static let defaultTimeoutMinutes = 30

    private enum Keys {
        static let hasPermission = "red_list_has_permission"
        static let grantedAt = "red_list_permission_granted_at"
        static let timeoutMinutes = "red_list_session_timeout_minutes"
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - PIN doğrulama

    static func verifyAdminPin(_ pin: String) -> Bool {
        pin == adminPin
    }

    /// PIN doğruysa oturumu açar ve `true` döner.
    @discardableResult
    static func grantPermissionWithPin(_ pin: String) -> Bool {
        guard verifyAdminPin(pin) else { return false }
        grantPermission()
        return true
    }

    static func grantPermission() {
        defaults.set(true, forKey: Keys.hasPermission)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.grantedAt)
    }

    static func revokePermission() {
        defaults.set(false, forKey: Keys.hasPermission)
        defaults.removeObject(forKey: Keys.grantedAt)
    }

    // MARK: - Oturum durumu

    /// Yerel PIN oturumu geçerli mi (süresi dolmamış mı)?
    static func hasValidLocalPermission() -> Bool {
        guard defaults.bool(forKey: Keys.hasPermission) else { return false }
        let grantedAt = defaults.double(forKey: Keys.grantedAt)
        guard grantedAt > 0 else { return false }

        let elapsedMinutes = (Date().timeIntervalSince1970 - grantedAt) / 60.0
        if elapsedMinutes >= Double(sessionTimeoutMinutes) {
            revokePermission()
            return false
        }
        return true
    }

    /// Oturumun kalan süresi (dakika). Geçerli oturum yoksa 0.
    static func sessionTimeRemainingMinutes() -> Int {
        guard hasValidLocalPermission() else { return 0 }
        let grantedAt = defaults.double(forKey: Keys.grantedAt)
        let elapsedMinutes = (Date().timeIntervalSince1970 - grantedAt) / 60.0
        return max(0, sessionTimeoutMinutes - Int(elapsedMinutes))
    }

    static var sessionTimeoutMinutes: Int {
        let stored = defaults.integer(forKey: Keys.timeoutMinutes)
        return stored > 0 ? stored : defaultTimeoutMinutes
    }

    static func setSessionTimeout(minutes: Int) {
        let clamped = min(max(minutes, 1), 1440)
        defaults.set(clamped, forKey: Keys.timeoutMinutes)
    }
}

// MARK: - RedListPermissionChecking implementasyonu

/// PIN oturumuna göre kırmızı liste check-in yetkisi veren gerçek kontrolör.
struct PinRedListPermissionChecker: RedListPermissionChecking {
    func canCheckInRedListGuest() -> Bool {
        RedListPermissionManager.hasValidLocalPermission()
    }
}
