import FirebaseAuth
import Foundation
import os.log

/// Firebase Auth ile e-posta / şifre girişi (Android `FirebaseAuthRepository` eşleniği).
///
/// Yalnızca Firebase Console'da tanımlı yetkili hesaplar giriş yapabilir.
/// UI yönlendirmesi için `@MainActor` üzerinde çalışır; `authState` dinleyicisi
/// iptal edildiğinde `removeStateDidChangeListener` ile temizlenir.
@MainActor
final class FirebaseAuthRepository: AuthRepository {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "FirebaseAuthRepository")

    private var auth: Auth { Auth.auth() }

    // MARK: - AuthRepository

    nonisolated var authState: AsyncStream<AuthState> {
        Self.makeAuthStateStream()
    }

    func signIn(email: String, password: String) async -> LoginResult {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty || Self.isBlank(password) {
            return .error(message: "E-posta ve şifre boş olamaz")
        }

        do {
            _ = try await auth.signIn(withEmail: trimmedEmail, password: password)
            return .success
        } catch {
            return Self.mapSignInError(error)
        }
    }

    func signOut() async {
        try? auth.signOut()
    }

    func getCurrentUser() -> User? {
        auth.currentUser
    }

    // MARK: - Auth state stream

    /// `callbackFlow` + `awaitClose` eşleniği; dinleyici `onTermination` ile kaldırılır.
    private nonisolated static func makeAuthStateStream() -> AsyncStream<AuthState> {
        let auth = Auth.auth()

        return AsyncStream { continuation in
            // Dinleyici ilk callback'i geciktirebilir; senkron bootstrap beyaz ekranı önler.
            if let user = auth.currentUser {
                continuation.yield(.authenticated(AuthenticatedUser(user: user)))
                Self.logger.debug("Auth stream bootstrap: authenticated")
            } else {
                continuation.yield(.notAuthenticated)
                Self.logger.debug("Auth stream bootstrap: notAuthenticated")
            }

            let handle = auth.addStateDidChangeListener { _, user in
                let state: AuthState
                if let user {
                    state = .authenticated(AuthenticatedUser(user: user))
                } else {
                    state = .notAuthenticated
                }
                Self.logger.debug("Auth state changed: \(String(describing: state), privacy: .public)")
                continuation.yield(state)
            }

            continuation.onTermination = { @Sendable _ in
                auth.removeStateDidChangeListener(handle)
            }
        }
    }

    // MARK: - Error mapping

    private nonisolated static func mapSignInError(_ error: Error) -> LoginResult {
        let nsError = error as NSError

        if nsError.domain == AuthErrorDomain,
           let code = AuthErrorCode.Code(rawValue: nsError.code) {
            switch code {
            case .invalidEmail, .userNotFound:
                return .error(message: "Geçersiz e-posta adresi veya hesap bulunamadı")
            case .wrongPassword:
                return .error(message: "Hatalı şifre")
            case .keychainError:
                Self.logger.error(
                    "Keychain hatası: \(Self.keychainFailureReason(from: nsError), privacy: .public)"
                )
                return .error(message: "Güvenli oturum depolamasına erişilemedi. Uygulamayı kapatıp yeniden açın.")
            default:
                break
            }
        }

        if Self.isKeychainAccessError(nsError) {
            Self.logger.error(
                "Keychain erişim hatası: \(Self.keychainFailureReason(from: nsError), privacy: .public)"
            )
            return .error(message: "Güvenli oturum depolamasına erişilemedi. Uygulamayı kapatıp yeniden açın.")
        }

        let message = error.localizedDescription
        if message.isEmpty {
            return .error(message: "Giriş yapılamadı. Lütfen tekrar deneyin.")
        }
        return .error(message: message)
    }

    /// Kotlin `CharSequence.isBlank()` — yalnızca e-posta trim edilir, şifre olduğu gibi kontrol edilir.
    private nonisolated static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private nonisolated static func isKeychainAccessError(_ error: NSError) -> Bool {
        let description = error.localizedDescription.lowercased()
        if description.contains("keychain") {
            return true
        }
        if let reason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
           reason.lowercased().contains("keychain") {
            return true
        }
        return false
    }

    private nonisolated static func keychainFailureReason(from error: NSError) -> String {
        if let reason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
           !reason.isEmpty {
            return reason
        }
        return error.localizedDescription
    }
}
