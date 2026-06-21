import Foundation

// MARK: - AuthorizedDeviceRepository

/// Yetkili cihaz yönetimi sözleşmesi (Android `AuthorizedDeviceRepository`).
///
/// **İş parçacığı beklentileri**
/// - `AsyncStream` metodları: Firestore / yerel önbellek dinleyicilerinden beslenir;
///   UI güncellemeleri `@MainActor` ViewModel’de tüketilmelidir.
/// - `async` metodlar: Yetkilendirme kontrolü ve yazma işlemleri; ağ I/O içerebilir.
/// - `updateLastUsedAt`: Gereksiz yazmayı önlemek için implementasyon en az 1 dakika
///   aralıkla güncelleme yapmalıdır (Android ile aynı optimizasyon).
protocol AuthorizedDeviceRepository: Sendable {

    /// Cihazın kırmızı liste işlemleri için yetkili olup olmadığını kontrol eder.
    /// Kalıcı cihazlar: her zaman `true`. PIN cihazları: oturum zaman aşımı kontrolü.
    func isDeviceAuthorized(deviceId: String) async -> Bool

    func addAuthorizedDevice(
        deviceId: String,
        deviceName: String?,
        authorizedBy: String,
        isPermanent: Bool,
        sessionTimeoutMinutes: Int64?,
        isAdmin: Bool
    ) async

    /// Firestore `authorized_devices` kaydı; admin e-posta listesine göre `isAdmin` atanır.
    func registerDeviceRemotely(deviceId: String, deviceName: String, userEmail: String) async

    func getAuthorizedDevice(deviceId: String) async -> AuthorizedDevice?
    func isAdminDevice(deviceId: String) async -> Bool
    func adminDevices() -> AsyncStream<[AuthorizedDevice]>
    func removeAuthorizedDevice(deviceId: String) async
    func allAuthorizedDevices() -> AsyncStream<[AuthorizedDevice]>
    func updateLastUsedAt(deviceId: String) async
    func permanentDeviceCount() async -> Int
    func totalDeviceCount() async -> Int
    func cleanupExpiredAuthorizations() async
}

extension AuthorizedDeviceRepository {
    /// Android `isPermanent = false`, `sessionTimeoutMinutes = null`, `isAdmin = false` varsayılanları.
    func addAuthorizedDevice(
        deviceId: String,
        deviceName: String?,
        authorizedBy: String
    ) async {
        await addAuthorizedDevice(
            deviceId: deviceId,
            deviceName: deviceName,
            authorizedBy: authorizedBy,
            isPermanent: false,
            sessionTimeoutMinutes: nil,
            isAdmin: false
        )
    }
}
