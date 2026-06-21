import FirebaseAuth
import Foundation

// MARK: - AuthRepository

/// Firebase Authentication ile giriş / çıkış işlemlerini yöneten sözleşme.
///
/// **İş parçacığı beklentileri**
/// - `authState`: Firebase Auth dinleyicisinden beslenir; UI bağlamak için tüketiciler
///   genelde `@MainActor` ViewModel içinde `for await` kullanmalıdır. Uygulama katmanı
///   olayları ana iş parçacığına `Task { @MainActor in ... }` ile yönlendirebilir.
/// - `signIn` / `signOut`: Ağ çağrısı içerir; implementasyonlar arka planda çalışabilir,
///   çağıran `async` bağlamından beklenir — UI güncellemesi MainActor’da yapılmalıdır.
/// - `getCurrentUser()`: Senkrondur; Firebase SDK çağrısı hafiftir, tipik olarak ana
///   iş parçacığından okunur.
protocol AuthRepository: Sendable {

    /// Mevcut kimlik doğrulama durumunu sürekli yayınlar (Android `Flow<AuthState>`).
    var authState: AsyncStream<AuthState> { get }

    /// E-posta ve şifre ile giriş. Yalnızca yetkili hesaplar kabul edilir.
    func signIn(email: String, password: String) async -> LoginResult

    /// Oturumu kapatır.
    func signOut() async

    /// Giriş yapılmışsa Firebase kullanıcısını döner.
    func getCurrentUser() -> User?
}

// MARK: - FirebaseAuth bridging

extension AuthenticatedUser {
    /// `AuthState.authenticated` için Firebase `User` özetine dönüşüm.
    init(user: User) {
        uid = user.uid
        email = user.email
        isEmailVerified = user.isEmailVerified
    }
}
