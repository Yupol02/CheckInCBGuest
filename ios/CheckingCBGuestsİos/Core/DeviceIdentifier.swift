import CryptoKit
import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Cihaz kimliği üreticisi (Android `DeviceIdentifier` eşleniği).
///
/// Tasarım ilkeleri:
/// - Güvenlik: Firestore `authorized_devices` doküman ID'si için SHA-256 hash döndürür.
/// - Performans: Hesaplanan değer önbelleğe alınır.
/// - Kalıcılık: Ham kimlik Keychain'de saklanır; iOS'ta Keychain uygulama silinse de
///   kaldığı için yeniden kurulumda AYNI kimlik korunur.
///
/// v1.4 geçiş garantisi (KRİTİK): Keychain'de kayıt yoksa, 1.3'ün ürettiği değerin
/// BİREBİR AYNISI hesaplanır (`identifierForVendor` → UserDefaults fallback) ve
/// Keychain'e taşınır. Böylece mevcut kurulumların `getDeviceId()` çıktısı değişmez,
/// dolayısıyla hiçbir `authorized_devices` dokümanı öksüz kalmaz.
///
/// Not: Android `androidId_serial` kullanırken iOS `identifierForVendor` kullanır.
/// Cihaz ID'leri platforma özgüdür; kritik olan iOS içinde tutarlı şekilde hash'lenmiş
/// değerin hem yazma hem okuma sırasında kullanılmasıdır.
enum DeviceIdentifier {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "DeviceIdentifier")

    private static let lock = NSLock()
    private static var cachedDeviceId: String?
    private static var cachedRawDeviceId: String?
    private static let fallbackKey = "device_id.fallback_id"

    /// Güvenli (SHA-256 hash'li) cihaz kimliği. Firestore doküman ID'si olarak kullanılır.
    static func getDeviceId() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cachedDeviceId { return cachedDeviceId }
        let hashed = hash(resolveRawLocked())
        cachedDeviceId = hashed
        return hashed
    }

    /// Ham cihaz kimliği (hash'lenmeden önce). Yalnızca görüntüleme amaçlı.
    static func getRawDeviceId() -> String {
        lock.lock()
        defer { lock.unlock() }
        return resolveRawLocked()
    }

    /// Kullanıcı dostu kısa cihaz adı (Android ile aynı: ham ID'nin ilk 8 karakteri, büyük harf).
    static func getDeviceName() -> String {
        String(getRawDeviceId().prefix(8)).uppercased()
    }

    /// Yalnızca BELLEK önbelleğini temizler (test senaryoları için).
    ///
    /// Keychain kaydı bilerek silinmez: silinmesi cihazın kimliğini değiştirir ve
    /// kullanıcıyı "bu hesap başka cihaza tanımlı" hatasıyla kilitler.
    static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedDeviceId = nil
        cachedRawDeviceId = nil
    }

    // MARK: - Internal

    /// Ham kimliği çözer ve bellek önbelleğine yazar. Çağıran `lock`u tutuyor olmalıdır.
    private static func resolveRawLocked() -> String {
        if let cachedRawDeviceId { return cachedRawDeviceId }
        let raw = rawDeviceIdInternal()
        cachedRawDeviceId = raw
        return raw
    }

    private static func rawDeviceIdInternal() -> String {
        // 1) Kanonik kaynak Keychain'dir — yeniden kurulumdan sağ çıkan tek katman.
        if let stored = KeychainStore.string(account: AppAuth.deviceIdKeychainAccount),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }

        // 2) Keychain boş: 1.3 ile BİREBİR aynı değeri üret. Bu, mevcut kurulumların
        //    cihaz kimliğinin değişmemesini garanti eder.
        let legacy = legacyRawDeviceId()

        // 3) Keychain'e taşı. Yazma başarısız olsa bile DÖNEN DEĞER DEĞİŞMEZ:
        //    legacy kaynak aynı cihazda belirlenimcidir, sonraki denemede aynı sonucu verir.
        if KeychainStore.set(legacy, account: AppAuth.deviceIdKeychainAccount) {
            return legacy
        }

        logger.warning("Keychain yazımı başarısız — bu oturumda eski kimlik kullanılıyor")
        return legacy
    }

    /// v1.3 davranışı, aynen korunur. Değiştirilmemelidir.
    private static func legacyRawDeviceId() -> String {
        #if canImport(UIKit)
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString,
           !vendorId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return vendorId
        }
        #endif
        return getOrCreateFallbackId()
    }

    private static func getOrCreateFallbackId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: fallbackKey),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        defaults.set(newId, forKey: fallbackKey)
        return newId
    }

    private static func hash(_ raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
