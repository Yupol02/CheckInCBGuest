import FirebaseFirestore
import Foundation
import os.log

/// `AdminUserRepository`'nin Firestore uygulaması.
///
/// Admin listesi v1.4 ile koddan Firestore'a taşındı: sahip Console'da
/// `admin_users/{normalizedEmail}` dokümanı oluşturup silerek yetki verir/alır,
/// App Store güncellemesi gerekmez.
actor FirebaseAdminUserRepository: AdminUserRepository {

    private static let logger = Logger(
        subsystem: "com.checkingcbguests",
        category: "FirebaseAdminUserRepository"
    )

    private let firestore: Firestore

    /// Süreç içi hafıza. Admin durumu oturum ortasında değişmediği için TTL gerekmez;
    /// amaç her `registerDeviceRemotely` çağrısında yeni bir Firestore okuması yapmamak.
    private var memo: [String: Bool] = [:]

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func lookupAdmin(email: String) async -> AdminLookupResult {
        let key = AppAuth.normalizedEmailKey(email)
        guard !key.isEmpty else { return .unavailable }

        if let cached = memo[key] {
            return .known(cached)
        }

        do {
            // Varsayılan kaynak (önbellek serbest) BİLİNÇLİDİR: çevrimdışıyken önceki
            // girişten önbelleğe alınmış admin cevabı, ".unavailable" demekten daha
            // doğrudur — yetkiyi korur.
            let snapshot = try await firestore
                .collection(AppAuth.adminUsersCollection)
                .document(key)
                .getDocument()

            guard snapshot.exists, let data = snapshot.data() else {
                // Doküman yok: bu yetkili bir sunucu cevabıdır — admin değil.
                memo[key] = false
                return .known(false)
            }

            let isAdmin = Self.parseBool(data["isAdmin"])
            memo[key] = isAdmin
            return .known(isAdmin)
        } catch {
            // Okuma hatası ".known(false)" DEĞİLDİR. Bkz. AdminLookupResult belgesi.
            Self.logger.error(
                "admin_users okunamadı: \(error.localizedDescription, privacy: .public)"
            )
            return .unavailable
        }
    }

    /// Firestore'da alan hem `Bool` hem `"true"` string olarak yazılmış olabilir
    /// (Console'dan elle giriş). Her ikisini de kabul et.
    private static func parseBool(_ value: Any?) -> Bool {
        if let boolValue = value as? Bool { return boolValue }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        }
        return false
    }
}
