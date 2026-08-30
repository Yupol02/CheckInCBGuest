import Foundation

/// E-posta ↔ cihaz bağlama sözleşmesi.
///
/// Kural: bir e-posta yalnızca tek bir cihaza bağlanabilir. Bağ bir kez kurulduktan
/// sonra istemci onu değiştiremez veya silemez — yalnızca Firebase Console'dan
/// (dokümanı silerek) sıfırlanabilir. Bu kısıt Firestore güvenlik kurallarıyla
/// zorlanır; buradaki istemci mantığı yalnızca kullanıcı deneyimi katmanıdır.
protocol DeviceBindingRepository: Sendable {

    /// Giriş anında ATOMİK bağlama/doğrulama.
    ///
    /// `runTransaction` kullanır; bu iki şeyi birden garanti eder:
    /// 1. Sunucuya gerçek bir gidiş-dönüş (çevrimdışıyken `.networkRequired` döner,
    ///    yerel önbellekten sessizce "başarılı" olmaz).
    /// 2. İki cihazın aynı anda ilk bağı kurma yarışında yalnızca birinin kazanması.
    func bindOrValidate(
        email: String,
        uid: String,
        deviceId: String,
        deviceName: String
    ) async -> DeviceBindingResult

    /// Açılış / öne gelme sırasında arka plan doğrulaması. SALT OKUR, yazmaz.
    /// Sunucudan okur (`source: .server`) — önbellek bu kontrolü anlamsız kılardı.
    func revalidate(email: String, deviceId: String) async -> DeviceBindingResult
}

/// Admin e-posta listesi sözleşmesi (Firestore `admin_users`).
///
/// v1.4 öncesinde admin listesi koda gömülüydü ve yeni admin eklemek App Store
/// güncellemesi gerektiriyordu. Artık sahip Console'dan doküman ekleyip silerek
/// yönetir.
protocol AdminUserRepository: Sendable {

    /// `admin_users/{normalizedEmail}` okur.
    ///
    /// Doküman yoksa `.known(false)` (yetkili sunucu cevabı: admin değil),
    /// okuma hata verirse `.unavailable` döner. İkisi KARIŞTIRILMAMALIDIR:
    /// hatayı "admin değil" saymak yanlışlıkla yetki düşürmeye yol açar.
    func lookupAdmin(email: String) async -> AdminLookupResult
}
