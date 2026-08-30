import Foundation

/// Kimlik doğrulama ve cihaz bağlama sabitleri.
///
/// v1.4 ile herkese açık kayıt kaldırıldı: hesaplar yalnızca Firebase Console'dan
/// oluşturulur ve her e-posta tek bir cihaza bağlanır. Admin yetkisi de artık kodda
/// değil, Firestore `admin_users` koleksiyonunda tutulur.
enum AppAuth {

    // MARK: - Firestore koleksiyonları

    /// E-posta ↔ cihaz bağlarının tutulduğu koleksiyon.
    /// Doküman ID'si normalize edilmiş e-postadır; böylece sahip Console'da
    /// dokümanı doğrudan bulup silerek bağı sıfırlayabilir.
    static let deviceBindingsCollection = "device_bindings"

    /// Admin e-postalarının tutulduğu koleksiyon. Doküman ID'si normalize edilmiş
    /// e-posta, alan `isAdmin: Bool`. Yalnızca Console'dan yazılır (güvenlik kuralı).
    static let adminUsersCollection = "admin_users"

    // MARK: - Keychain hesap adları

    /// Ham cihaz kimliğinin saklandığı Keychain kaydı.
    static let deviceIdKeychainAccount = "device.raw_id"

    /// Yerel cihaz bağlama önbelleğinin saklandığı Keychain kaydı.
    static let bindingKeychainAccount = "device.binding"

    // MARK: - Zaman aşımları

    /// Tek bir bağlama işleminin üst sınırı (saniye).
    static let bindingTimeout: TimeInterval = 12

    /// `AuthViewModel` oturum kapısı emniyet supabı (saniye).
    /// Depo zaman aşımı ayrı bir dosyada yaşadığı için ikinci bir güvence olarak durur.
    static let sessionGateWatchdog: TimeInterval = 15

    /// Uygulama öne geldiğinde yeniden doğrulama arası minimum süre (saniye).
    static let revalidationThrottle: TimeInterval = 300

    /// Sunucuya hiç ulaşılamadan geçirilebilecek azami süre (saat).
    /// Aşılırsa oturum kapatılır — aksi halde uçak modunda süresiz kullanım mümkün olurdu.
    static let offlineGraceHours: Double = 48

    // MARK: - Tarih biçimi

    /// Mevcut koleksiyonlarla aynı ISO8601 biçimi (kesirli saniyeli).
    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func nowISO8601String() -> String {
        isoFormatter.string(from: Date())
    }

    /// Kesirli saniyeli ve saniyesiz her iki biçimi de kabul eder
    /// (`FirebaseAuthorizedDeviceRepository.parseDate` ile aynı hoşgörü).
    static func parseISO8601(_ raw: String) -> Date? {
        if let date = isoFormatter.date(from: raw) { return date }
        if let date = isoFallbackFormatter.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    // MARK: - E-posta normalizasyonu

    /// Firestore doküman ID'si için e-posta normalizasyonu.
    ///
    /// UYARI: `en_US_POSIX` locale'i ZORUNLUDUR. Cihaz dili Türkçe iken
    /// `"I".lowercased()` → `"ı"` üretir; Firestore güvenlik kuralındaki `lower()`
    /// ise locale'den bağımsızdır. İkisi ayrışırsa doküman ID'si kuralla eşleşmez
    /// ve her yazma `permissionDenied` ile reddedilir.
    /// Aynı gerekçeyle `String.normalizeGuestName()` de bu locale'i kullanır.
    static func normalizedEmailKey(_ email: String?) -> String {
        guard let email else { return "" }
        return email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
