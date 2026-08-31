import FirebaseFirestore
import Foundation
import os.log

/// `DeviceBindingRepository`'nin Firestore uygulaması.
///
/// `actor` seçimi bilinçlidir (`FirebaseAuthorizedDeviceRepository` ile aynı desen):
/// eşzamanlı `bindOrValidate` çağrılarını (giriş butonuna çift dokunma, girişin
/// açılış doğrulamasıyla yarışması) sıraya sokar.
actor FirebaseDeviceBindingRepository: DeviceBindingRepository {

    private static let logger = Logger(
        subsystem: "com.checkingcbguests",
        category: "FirebaseDeviceBindingRepository"
    )

    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    private var bindingsCollection: CollectionReference {
        firestore.collection(AppAuth.deviceBindingsCollection)
    }

    // MARK: - Bağlama / doğrulama

    func bindOrValidate(
        email: String,
        uid: String,
        deviceId: String,
        deviceName: String
    ) async -> DeviceBindingResult {
        let key = AppAuth.normalizedEmailKey(email)
        guard !key.isEmpty, !deviceId.isEmpty else {
            return .failed(message: DeviceBindingMessages.generic)
        }

        let reference = bindingsCollection.document(key)
        let now = AppAuth.nowISO8601String()

        do {
            // Eşleme closure'ın İÇİNDE yapılır: `runTransaction` `Any?` döndürür ve
            // `Any` Sendable DEĞİLDİR; task group'un gerektirdiği Sendable kısıtını
            // sağlamak için sonucu burada somut `DeviceBindingResult`'a çeviriyoruz.
            return try await withTimeout(seconds: AppAuth.bindingTimeout) { [firestore] in
                let raw = try await firestore.runTransaction { transaction, errorPointer in
                    let snapshot: DocumentSnapshot
                    do {
                        snapshot = try transaction.getDocument(reference)
                    } catch let error as NSError {
                        errorPointer?.pointee = error
                        return nil
                    }

                    // Karar mantığı Firestore'dan ayrı, saf bir fonksiyonda:
                    // birim testleriyle doğrulanabilsin diye.
                    switch Self.decide(existing: snapshot.exists ? snapshot.data() : nil,
                                       currentDeviceId: deviceId) {
                    case .bind:
                        let binding = DeviceBinding(
                            email: key,
                            uid: uid,
                            deviceId: deviceId,
                            deviceName: deviceName,
                            boundAt: now,
                            lastSeenAt: now
                        )
                        transaction.setData(binding.toFirestoreMap(), forDocument: reference)
                        return ["outcome": "bound"]

                    case .match:
                        transaction.setData(
                            ["lastSeenAt": now],
                            forDocument: reference,
                            merge: true
                        )
                        return ["outcome": "matched"]

                    case .exempt:
                        // Muaf hesap: hiçbir şey YAZMA. Yazmak, farklı cihazlardan
                        // gelen eşzamanlı girişlerin birbirinin lastSeenAt'ini
                        // ezmesine ve gereksiz kural yüzeyine yol açardı.
                        return ["outcome": "matched"]

                    case .reject(let boundDeviceName):
                        // Yazma yapmayan bir transaction no-op olarak commit olur.
                        return [
                            "outcome": "rejected",
                            "deviceName": boundDeviceName ?? "",
                        ]
                    }
                }
                return Self.mapTransactionOutcome(raw)
            }
        } catch {
            return Self.classify(error)
        }
    }

    // MARK: - Yeniden doğrulama (salt okuma)

    func revalidate(email: String, deviceId: String) async -> DeviceBindingResult {
        let key = AppAuth.normalizedEmailKey(email)
        guard !key.isEmpty, !deviceId.isEmpty else {
            return .failed(message: DeviceBindingMessages.generic)
        }

        let reference = bindingsCollection.document(key)
        do {
            // Eşleme closure İÇİNDE: `DocumentSnapshot` Sendable değildir.
            return try await withTimeout(seconds: AppAuth.bindingTimeout) {
                // source: .server — önbellekten okumak bu kontrolü anlamsız kılardı;
                // çevrimdışıyken hata verir ve .networkRequired'a düşer (istenen davranış).
                let snapshot = try await reference.getDocument(source: .server)

                guard snapshot.exists,
                      let data = snapshot.data(),
                      let binding = DeviceBinding.from(documentId: key, data: data)
                else {
                    // Doküman yok — sahip Console'dan bağı sıfırlamış olabilir.
                    // BİLİNÇLİ OLARAK yeniden bağlanmıyoruz: sıfırlama çoğunlukla hesabı
                    // BAŞKA bir cihaza devretmek için yapılır; burada hemen yeniden
                    // bağlamak, yeni cihaz giriş yapamadan bağı geri çalardı.
                    // Bunun yerine ihtimam yoluna düşülür: cihaz çalışmaya devam eder,
                    // süre dolunca oturum kapanır ve giriş sırasında yeniden bağlanır.
                    return .networkRequired
                }

                switch Self.decide(existing: data, currentDeviceId: deviceId) {
                case .bind, .match, .exempt:
                    return .matched
                case .reject(let boundDeviceName):
                    return .rejected(boundDeviceName: boundDeviceName ?? binding.deviceName)
                }
            }
        } catch {
            return Self.classify(error)
        }
    }

    // MARK: - Yardımcılar

    /// Cihaz bağlama kararı. Firestore'dan bağımsız, saf fonksiyon (test edilebilir).
    enum BindingDecision: Equatable {
        /// Bağ yok → bu cihaza bağla.
        case bind
        /// Bağ bu cihaza ait.
        case match
        /// Hesap cihaz kısıtından muaf (`allowMultipleDevices: true`).
        case exempt
        /// Başka cihaza bağlı.
        case reject(boundDeviceName: String?)
    }

    /// - Parameters:
    ///   - existing: Firestore'daki mevcut doküman verisi; doküman yoksa `nil`.
    ///   - currentDeviceId: Bu cihazın kimliği.
    ///
    /// `allowMultipleDevices` alanı YALNIZCA Firebase Console'dan açılabilir
    /// (güvenlik kuralı istemcinin yazmasını engeller). Amacı App Store inceleme
    /// demo hesabıdır: incelemeci hem iPhone hem iPad'de test edebilsin diye.
    /// Onay sonrası Console'dan kapatın — yeni sürüm gerekmez.
    static func decide(existing: [String: Any]?, currentDeviceId: String) -> BindingDecision {
        guard let existing else { return .bind }

        if parseBool(existing["allowMultipleDevices"]) {
            return .exempt
        }

        let boundDeviceId = (existing["deviceId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !boundDeviceId.isEmpty else { return .bind }

        if boundDeviceId == currentDeviceId { return .match }

        let name = (existing["deviceName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .reject(boundDeviceName: name?.isEmpty == false ? name : nil)
    }

    /// Console'dan elle girilen alanlar `Bool` yerine string olabilir.
    private static func parseBool(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        }
        return false
    }

    private static func mapTransactionOutcome(_ raw: Any?) -> DeviceBindingResult {
        guard let map = raw as? [String: Any],
              let outcome = map["outcome"] as? String else {
            return .failed(message: DeviceBindingMessages.generic)
        }
        switch outcome {
        case "bound":
            return .bound
        case "matched":
            return .matched
        case "rejected":
            let name = (map["deviceName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .rejected(boundDeviceName: name?.isEmpty == false ? name : nil)
        default:
            return .failed(message: DeviceBindingMessages.generic)
        }
    }

    /// Hata sınıflandırması. Sıra önemlidir: kural hatası (`permissionDenied`)
    /// "internet yok" ile KARIŞTIRILMAMALIDIR, yoksa yanlış yapılandırılmış bir
    /// güvenlik kuralı ağ sorunu gibi görünür ve teşhis edilemez.
    private static func classify(_ error: Error) -> DeviceBindingResult {
        if error is TimeoutError {
            return .networkRequired
        }

        let nsError = error as NSError

        if nsError.domain == FirestoreErrorDomain {
            switch nsError.code {
            case FirestoreErrorCode.unavailable.rawValue,
                 FirestoreErrorCode.deadlineExceeded.rawValue:
                return .networkRequired
            case FirestoreErrorCode.permissionDenied.rawValue:
                logger.error("Cihaz bağlama kural tarafından reddedildi (permissionDenied)")
                return .failed(message: DeviceBindingMessages.permissionDenied)
            default:
                break
            }
        }

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost:
                return .networkRequired
            default:
                break
            }
        }

        logger.error("Cihaz bağlama hatası: \(error.localizedDescription, privacy: .public)")
        return .failed(message: DeviceBindingMessages.generic)
    }

    private struct TimeoutError: Error {}

    /// İşi bir zaman aşımıyla yarıştırır.
    ///
    /// UYARI: `runTransaction` işbirlikçi iptali DESTEKLEMEZ. Zaman aşımından sonra
    /// `await`'i terk etsek de Firestore çağrısı arka planda tamamlanabilir. Sonuç
    /// analizi: geç tamamlanan bir ilk bağ, kullanıcının göremediği bir doküman
    /// oluşturur; aynı cihazdan sonraki giriş `.matched` (sorunsuz), başka cihazdan
    /// `.rejected` (doğru davranış) verir. Veri bozulması oluşmaz.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

/// Cihaz bağlama ile ilgili kullanıcıya gösterilen metinler.
/// Tek yerde toplanmaları bilinçli: hepsi aynı akışın parçası ve birlikte okunmalı.
enum DeviceBindingMessages {

    static let generic =
        "Cihaz doğrulaması yapılamadı. Lütfen tekrar deneyin. Sorun sürerse organizatörünüze başvurun."

    static let permissionDenied =
        "Cihaz kaydınız sunucu tarafından reddedildi. Lütfen organizatörünüzle iletişime geçin."

    static let networkRequiredOnFirstBind =
        "İlk cihaz kaydı için internet bağlantısı gerekli. Lütfen bağlantınızı kontrol edip tekrar deneyin."

    static let offlineGraceExpired =
        "Oturumunuzu doğrulamak için internete bağlanmanız gerekiyor. Lütfen bağlanıp tekrar giriş yapın."

    static let forcedSignOut =
        "Oturumunuz sonlandırıldı: bu hesap başka bir cihaza tanımlı. Organizatörünüze başvurun."

    /// Reddetme mesajı — hem bağlı cihazın hem eldeki cihazın kısa kodunu taşır ki
    /// sahip telefonda kimliği doğrulayıp Console'dan sıfırlayabilsin.
    static func rejected(boundDeviceName: String?, currentDeviceName: String) -> String {
        let base = "Bu hesap başka bir cihaza tanımlı"
        let devices: String
        if let boundDeviceName, !boundDeviceName.isEmpty {
            devices = " (bağlı cihaz: \(boundDeviceName), bu cihaz: \(currentDeviceName))"
        } else {
            devices = " (bu cihaz: \(currentDeviceName))"
        }
        return base + devices
            + ". Güvenlik nedeniyle aynı hesapla ikinci bir cihazdan giriş yapılamaz."
            + " Cihaz değişikliği için organizatörünüze başvurun."
    }
}
