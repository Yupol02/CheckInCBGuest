import FirebaseAuth
import Foundation

// MARK: - AuthRepository

/// Firebase Authentication ile giriş / kayıt / çıkış işlemlerini yöneten sözleşme.
///
/// **İş parçacığı beklentileri**
/// - `authState`: Firebase Auth dinleyicisinden beslenir; UI bağlamak için tüketiciler
///   genelde `@MainActor` ViewModel içinde `for await` kullanmalıdır. Uygulama katmanı
///   olayları ana iş parçacığına `Task { @MainActor in ... }` ile yönlendirebilir.
/// - `signIn` / `signUp` / `signOut`: Ağ çağrısı içerir; implementasyonlar arka planda çalışabilir,
///   çağıran `async` bağlamından beklenir — UI güncellemesi MainActor’da yapılmalıdır.
/// - `getCurrentUser()`: Senkrondur; Firebase SDK çağrısı hafiftir, tipik olarak ana
///   iş parçacığından okunur.
protocol AuthRepository: Sendable {

    /// Mevcut kimlik doğrulama durumunu sürekli yayınlar (Android `Flow<AuthState>`).
    var authState: AsyncStream<AuthState> { get }

    /// E-posta ve şifre ile giriş.
    func signIn(email: String, password: String) async -> LoginResult

    /// Yeni hesap oluşturur (Firebase Auth `createUser`).
    /// App Store onayı için herkese açık; sonra `AppAuth.publicRegistrationEnabled` ile kapatılır.
    func signUp(email: String, password: String) async -> LoginResult

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
