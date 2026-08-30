import CryptoKit
import UIKit
import XCTest
@testable import CheckingCBGuestsIos

/// v1.4 cihaz kimliği ve e-posta normalizasyonu testleri.
final class CheckingCBGuestsI_osTests: XCTestCase {

    private func clearKeychainDeviceId() {
        KeychainStore.delete(account: AppAuth.deviceIdKeychainAccount)
        DeviceIdentifier.clearCache()
    }

    // MARK: - T10: 1.3 → 1.4 cihaz kimliği eşdeğerliği (EN KRİTİK TEST)

    /// Keychain BOŞKEN üretilen kimlik, 1.3'ün ürettiğiyle BİREBİR aynı olmalıdır.
    /// Aksi halde yükseltmede tüm authorized_devices dokümanları öksüz kalır.
    func testDeviceIdMatchesLegacyAlgorithmWhenKeychainEmpty() throws {
        clearKeychainDeviceId()

        // 1.3'ün algoritması, burada bağımsız olarak yeniden üretiliyor:
        // SHA-256(identifierForVendor.uuidString) → hex
        guard let vendorId = UIDevice.current.identifierForVendor?.uuidString else {
            throw XCTSkip("identifierForVendor yok — bu ortamda test edilemez")
        }
        let expected = SHA256.hash(data: Data(vendorId.utf8))
            .map { String(format: "%02x", $0) }.joined()

        let actual = DeviceIdentifier.getDeviceId()

        XCTAssertEqual(actual, expected,
            "T10 BAŞARISIZ: 1.4 cihaz kimliği 1.3'ten farklı. Yükseltme tüm cihaz kayıtlarını bozar.")
        XCTAssertEqual(actual.count, 64, "SHA-256 hex 64 karakter olmalı")
    }

    /// İkinci çağrı artık Keychain'den okumalı ve AYNI değeri vermeli.
    /// (Yeniden kurulum senaryosunun çekirdeği: IDFV değişse bile Keychain kalır.)
    func testDeviceIdSurvivesCacheClearViaKeychain() throws {
        clearKeychainDeviceId()
        let first = DeviceIdentifier.getDeviceId()   // Keychain'e yazar

        DeviceIdentifier.clearCache()                // yalnızca BELLEK önbelleği
        let second = DeviceIdentifier.getDeviceId()  // Keychain'den okumalı

        XCTAssertEqual(first, second, "Keychain turu kimliği korumadı")
        XCTAssertNotNil(KeychainStore.string(account: AppAuth.deviceIdKeychainAccount),
            "Ham kimlik Keychain'e yazılmamış — yeniden kurulumda kaybolur")
    }

    /// Keychain'de FARKLI bir değer varsa o kanonik kabul edilmeli
    /// (gerçek yeniden kurulum: IDFV değişti, Keychain kaldı).
    func testKeychainValueWinsOverFreshVendorId() throws {
        clearKeychainDeviceId()
        let simulatedOldRawId = "11111111-2222-3333-4444-555555555555"
        XCTAssertTrue(KeychainStore.set(simulatedOldRawId, account: AppAuth.deviceIdKeychainAccount))
        DeviceIdentifier.clearCache()

        let expected = SHA256.hash(data: Data(simulatedOldRawId.utf8))
            .map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(DeviceIdentifier.getDeviceId(), expected,
            "Keychain'deki kimlik yok sayıldı — yeniden kurulumda kullanıcı kilitlenir")

        clearKeychainDeviceId()
    }

    // MARK: - E-posta normalizasyonu (Firestore kuralı ile eşleşmeli)

    /// Türkçe locale tuzağı: "I".lowercased() → "ı" olur ve Firestore
    /// kuralındaki locale-bağımsız lower() ile EŞLEŞMEZ.
    func testNormalizedEmailKeyIsLocaleInvariant() {
        XCTAssertEqual(AppAuth.normalizedEmailKey("ADMIN@CHECKIN.COM"), "admin@checkin.com")
        XCTAssertEqual(AppAuth.normalizedEmailKey("  Test@Checking.com  "), "test@checking.com")
        XCTAssertEqual(AppAuth.normalizedEmailKey("ISTANBUL@x.com"), "istanbul@x.com",
            "Türkçe locale'de 'ı' üretilirse Firestore kuralıyla eşleşmez")
        XCTAssertEqual(AppAuth.normalizedEmailKey(nil), "")
    }

    // MARK: - Cihaz bağı ayrıştırma

    func testDeviceBindingRoundTrip() throws {
        let map = DeviceBinding.preview.toFirestoreMap()
        let parsed = try XCTUnwrap(DeviceBinding.from(documentId: "test@checking.com", data: map))
        XCTAssertEqual(parsed.deviceId, DeviceBinding.preview.deviceId)
        XCTAssertEqual(parsed.email, DeviceBinding.preview.email)
        XCTAssertEqual(parsed.platform, "ios")
    }

    /// deviceId boş/eksikse bağ GEÇERSİZ sayılmalı — aksi halde boş bir doküman
    /// "eşleşme yok" olarak yorumlanıp kullanıcıyı yanlışlıkla kilitleyebilir.
    func testDeviceBindingRejectsEmptyDeviceId() {
        XCTAssertNil(DeviceBinding.from(documentId: "a@b.com", data: ["deviceId": ""]))
        XCTAssertNil(DeviceBinding.from(documentId: "a@b.com", data: [:]))
    }
}
