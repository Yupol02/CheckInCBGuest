import Foundation

// MARK: - Event / Guest işlemleri

/// Genel repository işlem sonucu (Android `RepoResult`).
enum RepoResult<T: Sendable>: Sendable {
    case success(T)
    case failure(RepositoryError)

    func map<U: Sendable>(_ transform: (T) -> U) -> RepoResult<U> {
        switch self {
        case .success(let data):
            return .success(transform(data))
        case .failure(let error):
            return .failure(error)
        }
    }

    @discardableResult
    func onSuccess(_ action: (T) -> Void) -> RepoResult<T> {
        if case .success(let data) = self { action(data) }
        return self
    }

    @discardableResult
    func onFailure(_ action: (RepositoryError) -> Void) -> RepoResult<T> {
        if case .failure(let error) = self { action(error) }
        return self
    }
}

/// Ağ / veri katmanı hatalarının `Sendable` temsili (`Throwable` eşleniği).
struct RepositoryError: Error, Sendable, Hashable {
    let localizedDescription: String

    init(localizedDescription: String) {
        self.localizedDescription = localizedDescription
    }

    init(_ error: Error) {
        self.localizedDescription = error.localizedDescription
    }
}

/// Toplu silme işlemi sonucu (Android `BatchDeleteResult`).
struct BatchDeleteResult: Sendable, Hashable {
    let successCount: Int
    let failedCount: Int
    let errors: [String]

    init(successCount: Int, failedCount: Int, errors: [String]) {
        self.successCount = successCount
        self.failedCount = failedCount
        self.errors = errors
    }
}

// MARK: - Kimlik doğrulama

/// Giriş işlemi sonucu (Android `LoginResult`).
enum LoginResult: Sendable, Hashable {
    case success
    case error(message: String)
}

/// Kimlik doğrulama oturum durumu (Android `AuthState`).
///
/// `authenticated` yalnızca `Sendable` alanlar taşır. Tam Firebase `User` nesnesi için
/// `AuthRepository.getCurrentUser()` kullanın (genelde ana iş parçacığında).
enum AuthState: Sendable, Hashable {
    case loading
    case notAuthenticated
    case authenticated(AuthenticatedUser)
}

/// Firebase `User` özeti — `AuthState` akışında güvenli eşzamanlılık için.
struct AuthenticatedUser: Sendable, Hashable {
    let uid: String
    let email: String?
    let isEmailVerified: Bool
}

// MARK: - Kırmızı liste

/// Kırmızı liste işlem sonucu (Android `RedListResult`).
enum RedListResult<T: Sendable>: Sendable {
    case success(T)
    case error(message: String, underlying: RepositoryError? = nil, errorCode: RedListErrorCode? = nil)

    func map<U: Sendable>(_ transform: (T) -> U) -> RedListResult<U> {
        switch self {
        case .success(let data):
            return .success(transform(data))
        case .error(let message, let underlying, let errorCode):
            return .error(message: message, underlying: underlying, errorCode: errorCode)
        }
    }

    @discardableResult
    func onSuccess(_ action: (T) -> Void) -> RedListResult<T> {
        if case .success(let data) = self { action(data) }
        return self
    }

    @discardableResult
    func onError(_ action: (String, RepositoryError?, RedListErrorCode?) -> Void) -> RedListResult<T> {
        if case .error(let message, let underlying, let code) = self {
            action(message, underlying, code)
        }
        return self
    }
}

/// Kırmızı liste hata kodları (Android `RedListErrorCode`).
enum RedListErrorCode: String, Sendable, Hashable, Codable, CaseIterable {
    case guestNotFound = "GUEST_NOT_FOUND"
    case alreadyInRedList = "ALREADY_IN_RED_LIST"
    case invalidInput = "INVALID_INPUT"
    case databaseError = "DATABASE_ERROR"
    case unknownError = "UNKNOWN_ERROR"
}
