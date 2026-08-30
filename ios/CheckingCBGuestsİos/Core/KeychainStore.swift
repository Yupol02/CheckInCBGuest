import Foundation
import os.log
import Security

/// Keychain sarmalayıcı — cihaz kimliğinin uygulama silinip yeniden kurulduğunda
/// korunmasını sağlar.
///
/// Tasarım ilkeleri:
/// - Erişilebilirlik `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
///   uygulama silinse bile AYNI cihazda kalır, ancak iCloud/iTunes yedeğine DAHİL
///   EDİLMEZ. Bu bilinçli bir karardır: yedek başka bir telefona yüklenirse cihaz
///   kimliği taşınmaz, aksi halde "1 e-posta = 1 cihaz" kısıtlaması delinebilirdi.
/// - `kSecAttrAccessGroup` AYARLANMAZ. Entitlements dosyasındaki varsayılan grup
///   ($(AppIdentifierPrefix)$(CFBundleIdentifier)) kullanılır; böylece hem gerçek
///   cihazda hem simülatörde ek yapılandırma olmadan çalışır.
/// - Hiçbir metot fırlatmaz veya çökmez. Başarısızlık `nil` / `false` ile bildirilir.
enum KeychainStore {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "KeychainStore")

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.checkingcbguests.CheckingCBGuestsI-os"
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Kayıtlı değeri okur. Bulunamazsa veya herhangi bir hata olursa `nil`.
    static func string(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logger.error("Keychain okuma hatası (account=\(account, privacy: .public)): \(status)")
            }
            return nil
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Değeri yazar (varsa günceller). Başarı durumunu döner; asla fırlatmaz.
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }

        // Kayıt zaten varsa güncelle.
        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(account: account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            if updateStatus == errSecSuccess { return true }
            logger.error("Keychain güncelleme hatası (account=\(account, privacy: .public)): \(updateStatus)")
            return false
        }

        logger.error("Keychain yazma hatası (account=\(account, privacy: .public)): \(addStatus)")
        return false
    }

    /// Kaydı siler. Kayıt yoksa da `true` döner (istenen son durum sağlanmıştır).
    @discardableResult
    static func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Cihaz bağlamasının yerel (çevrimdışı) kaydı.
///
/// Amaç: bağ bir kez sunucuda kurulduktan sonra, internet olmadan açılışlarda
/// kullanıcının çalışmaya devam edebilmesi. Sunucu doğrulaması yine arka planda
/// yapılır; bu önbellek yalnızca "bu cihaz daha önce bu e-posta için onaylandı"
/// bilgisini taşır ve tek başına yetki vermez.
enum DeviceBindingCache {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "DeviceBindingCache")

    /// Tek kayıt yeterlidir: 1 e-posta = 1 cihaz.
    struct CachedBinding: Codable, Sendable, Hashable {
        let email: String       // normalize edilmiş
        let deviceId: String
        let boundAt: String     // ISO8601
        /// Kesintisiz çevrimdışı doğrulama denemelerinin başladığı an (ISO8601).
        /// Başarılı her doğrulamada temizlenir. `AppAuth.offlineGraceHours` aşılırsa
        /// oturum kapatılır.
        var graceStartedAt: String?
    }

    static func load() -> CachedBinding? {
        guard let raw = KeychainStore.string(account: AppAuth.bindingKeychainAccount),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CachedBinding.self, from: data)
        } catch {
            // Bozuk kayıt: yok say, bir sonraki başarılı bağlamada üzerine yazılır.
            logger.error("Bağ önbelleği çözümlenemedi: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    static func save(_ binding: CachedBinding) -> Bool {
        do {
            let data = try JSONEncoder().encode(binding)
            guard let raw = String(data: data, encoding: .utf8) else { return false }
            return KeychainStore.set(raw, account: AppAuth.bindingKeychainAccount)
        } catch {
            logger.error("Bağ önbelleği yazılamadı: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Başarılı bağlama/doğrulama sonrası çağrılır; ihtimam sayacını da sıfırlar.
    static func save(email: String, deviceId: String, boundAt: String) {
        save(CachedBinding(email: email, deviceId: deviceId, boundAt: boundAt, graceStartedAt: nil))
    }

    static func clear() {
        KeychainStore.delete(account: AppAuth.bindingKeychainAccount)
    }

    /// Çevrimdışı ihtimam sayacını başlatır (zaten başlamışsa dokunmaz) ve
    /// süre aşıldıysa `true` döner.
    static func registerOfflineAttempt(now: Date = Date()) -> Bool {
        guard var cached = load() else { return false }

        let formatter = AppAuth.isoFormatter
        guard let startedAtRaw = cached.graceStartedAt,
              let startedAt = AppAuth.parseISO8601(startedAtRaw) else {
            cached.graceStartedAt = formatter.string(from: now)
            save(cached)
            return false
        }

        let elapsedHours = now.timeIntervalSince(startedAt) / 3600
        return elapsedHours > AppAuth.offlineGraceHours
    }

    /// Başarılı sunucu doğrulaması sonrası ihtimam sayacını sıfırlar.
    static func clearOfflineGrace() {
        guard var cached = load(), cached.graceStartedAt != nil else { return }
        cached.graceStartedAt = nil
        save(cached)
    }
}
