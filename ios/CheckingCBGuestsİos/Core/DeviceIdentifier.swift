import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Cihaz kimliği üreticisi (Android `DeviceIdentifier` eşleniği).
///
/// Tasarım ilkeleri:
/// - Güvenlik: Firestore `authorized_devices` doküman ID'si için SHA-256 hash döndürür.
/// - Performans: Hesaplanan değer önbelleğe alınır.
/// - Güvenilirlik: `identifierForVendor` yoksa kalıcı UUID fallback'i (UserDefaults).
///
/// Not: Android `androidId_serial` kullanırken iOS `identifierForVendor` kullanır.
/// Cihaz ID'leri platforma özgüdür; kritik olan iOS içinde tutarlı şekilde hash'lenmiş
/// değerin hem yazma hem okuma sırasında kullanılmasıdır.
enum DeviceIdentifier {

    private static let lock = NSLock()
    private static var cachedDeviceId: String?
    private static var cachedRawDeviceId: String?
    private static let fallbackKey = "device_id.fallback_id"

    /// Güvenli (SHA-256 hash'li) cihaz kimliği. Firestore doküman ID'si olarak kullanılır.
    static func getDeviceId() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cachedDeviceId { return cachedDeviceId }
        let hashed = hash(rawDeviceIdInternal())
        cachedDeviceId = hashed
        return hashed
    }

    /// Ham cihaz kimliği (hash'lenmeden önce). Yalnızca görüntüleme amaçlı.
    static func getRawDeviceId() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cachedRawDeviceId { return cachedRawDeviceId }
        let raw = rawDeviceIdInternal()
        cachedRawDeviceId = raw
        return raw
    }

    /// Kullanıcı dostu kısa cihaz adı (Android ile aynı: ham ID'nin ilk 8 karakteri, büyük harf).
    static func getDeviceName() -> String {
        String(getRawDeviceId().prefix(8)).uppercased()
    }

    /// Önbelleği temizler (test veya cihaz değişikliği senaryoları için).
    static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedDeviceId = nil
        cachedRawDeviceId = nil
    }

    // MARK: - Internal

    private static func rawDeviceIdInternal() -> String {
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
