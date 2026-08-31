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

    // MARK: - Arama sırasında sıra numarası (regresyon)

    private func makeGuest(_ name: String, time: String, section: String? = nil) -> Guest {
        Guest(
            id: "id-\(name)",
            eventId: "event-1",
            name: name,
            title: "Ünvan",
            arrivalMethod: .pedestrian,
            expectedTime: time,
            sectionTitle: section
        )
    }

    /// 20 kişilik listede 14. sıradaki kişi, arama sonucunda TEK BAŞINA
    /// gösterildiğinde de 14 kalmalıdır.
    ///
    /// Hata: numara gösterilen dizi üzerinden hesaplandığı için arama yapınca
    /// 1'e düşüyordu.
    func testOrderNumberStaysStableWhenFiltered() throws {
        let all = (1...20).map { makeGuest(String(format: "Kisi%02d", $0), time: String(format: "%02d:00", $0 % 24)) }

        let fullItems = GuestListGrouping.build(from: all)
        let target = try XCTUnwrap(all.first { $0.name == "Kisi14" })
        let fullNumber = try XCTUnwrap(orderNumber(of: target, in: fullItems))
        XCTAssertEqual(fullNumber, 14, "Senaryo kurulumu bozulmuş: hedef kişi listede 14. olmalı")

        // Arama: yalnızca hedef kişi görünür, numaralandırma temeli TAM liste
        let filteredItems = GuestListGrouping.build(from: [target], orderBasis: all)
        let filteredNumber = try XCTUnwrap(orderNumber(of: target, in: filteredItems))

        XCTAssertEqual(filteredNumber, fullNumber,
            "Arama sonucunda sıra numarası değişti (listede \(fullNumber), aramada \(filteredNumber))")
    }

    /// orderBasis verilmezse eski davranış korunur (geriye dönük uyumluluk).
    func testOrderNumberFallsBackToShownListWhenNoBasis() throws {
        let all = (1...5).map { makeGuest("Kisi\($0)", time: "0\($0):00") }
        let items = GuestListGrouping.build(from: [all[3]])
        XCTAssertEqual(orderNumber(of: all[3], in: items), 1)
    }

    /// Eşit saatli misafirlerde numaralandırma belirlenimci olmalı:
    /// girdi sırası değişse de aynı kişi aynı numarayı almalı.
    func testOrderNumberIsDeterministicForEqualTimes() throws {
        let a = makeGuest("Ahmet", time: "09:00")
        let b = makeGuest("Berk", time: "09:00")
        let c = makeGuest("Cem", time: "09:00")

        let first = GuestListGrouping.build(from: [a, b, c], orderBasis: [a, b, c])
        let shuffled = GuestListGrouping.build(from: [a, b, c], orderBasis: [c, a, b])

        for guest in [a, b, c] {
            XCTAssertEqual(orderNumber(of: guest, in: first), orderNumber(of: guest, in: shuffled),
                "\(guest.name) için numara girdi sırasına göre değişti")
        }
    }

    private func orderNumber(of guest: Guest, in items: [GuestListUiItem]) -> Int? {
        for item in items {
            if case .guest(let g, let ctx) = item, g.id == guest.id { return ctx.orderNumber }
        }
        return nil
    }

    // MARK: - Cihaz bağlama kararı

    private typealias Decision = FirebaseDeviceBindingRepository.BindingDecision

    func testDecideBindsWhenNoDocument() {
        XCTAssertEqual(FirebaseDeviceBindingRepository.decide(existing: nil, currentDeviceId: "dev-1"), .bind)
    }

    func testDecideBindsWhenDeviceIdMissingOrEmpty() {
        XCTAssertEqual(FirebaseDeviceBindingRepository.decide(existing: [:], currentDeviceId: "dev-1"), .bind)
        XCTAssertEqual(FirebaseDeviceBindingRepository.decide(existing: ["deviceId": "  "], currentDeviceId: "dev-1"), .bind)
    }

    func testDecideMatchesSameDevice() {
        XCTAssertEqual(
            FirebaseDeviceBindingRepository.decide(existing: ["deviceId": "dev-1"], currentDeviceId: "dev-1"),
            .match
        )
    }

    func testDecideRejectsOtherDeviceAndReportsItsName() {
        let decision = FirebaseDeviceBindingRepository.decide(
            existing: ["deviceId": "dev-OTHER", "deviceName": "A1B2C3D4"],
            currentDeviceId: "dev-1"
        )
        XCTAssertEqual(decision, .reject(boundDeviceName: "A1B2C3D4"))
    }

    /// App Store inceleme demo hesabı: Console'dan allowMultipleDevices açılınca
    /// BAŞKA cihazdan giriş de kabul edilmeli.
    func testDecideExemptsWhenAllowMultipleDevicesIsTrue() {
        XCTAssertEqual(
            FirebaseDeviceBindingRepository.decide(
                existing: ["deviceId": "dev-OTHER", "allowMultipleDevices": true],
                currentDeviceId: "dev-1"
            ),
            .exempt
        )
    }

    /// Console'dan elle girilen alan string olabilir; "true" da kabul edilmeli.
    func testDecideExemptionAcceptsStringTrue() {
        XCTAssertEqual(
            FirebaseDeviceBindingRepository.decide(
                existing: ["deviceId": "dev-OTHER", "allowMultipleDevices": "true"],
                currentDeviceId: "dev-1"
            ),
            .exempt
        )
    }

    /// Muafiyet kapalıyken (false / eksik / bozuk değer) kısıt uygulanmalı.
    func testDecideDoesNotExemptWhenFlagIsFalseOrInvalid() {
        for value: Any in [false, "false", "evet", 0] {
            let decision = FirebaseDeviceBindingRepository.decide(
                existing: ["deviceId": "dev-OTHER", "allowMultipleDevices": value],
                currentDeviceId: "dev-1"
            )
            XCTAssertEqual(decision, .reject(boundDeviceName: nil), "değer: \(value)")
        }
    }
}
