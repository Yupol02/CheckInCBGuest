import FirebaseMessaging
import Foundation
import Observation
import os.log
import UIKit

/// Giriş ekranı UI durumu (Android `LoginUiState`).
enum LoginUiState: Equatable, Sendable {
    case idle
    case loading
    case success
    case error(message: String)
}

/// Kimlik doğrulama ve cihaz kaydı iş mantığı (Android `AuthViewModel`).
@MainActor
@Observable
final class AuthViewModel {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "AuthViewModel")
    private static let adminAlertsTopic = "admin_alerts"

    private let authRepository: any AuthRepository
    private let authorizedDeviceRepository: any AuthorizedDeviceRepository

    @ObservationIgnored
    private nonisolated let authTasks = ObservationTaskHolder()
    @ObservationIgnored
    private nonisolated let authWatchdogTasks = ObservationTaskHolder()

    /// Repository `authState` akışının yerel yansıması.
    private(set) var authState: AuthState = .loading

    private(set) var loginUiState: LoginUiState = .idle

    init(
        authRepository: any AuthRepository,
        authorizedDeviceRepository: any AuthorizedDeviceRepository
    ) {
        self.authRepository = authRepository
        self.authorizedDeviceRepository = authorizedDeviceRepository

        bootstrapAuthStateSynchronously()
        startAuthStateObservation()
        startAuthBootstrapTimeoutWatchdog()
    }

    deinit {
        authTasks.cancelAll()
        authWatchdogTasks.cancelAll()
    }

    // MARK: - Public API

    func login(email: String, password: String) async {
        loginUiState = .loading

        let result = await authRepository.signIn(email: email, password: password)
        switch result {
        case .success:
            loginUiState = .success
            await onLoginSuccess()
        case .error(let message):
            loginUiState = .error(message: message)
        }
    }

    func logout() async {
        await authRepository.signOut()
        loginUiState = .idle
    }

    func clearLoginError() {
        loginUiState = .idle
    }

    // MARK: - Private

    /// Firebase `currentUser` senkron okunur; async dinleyici gelene kadar loading'de takılmayı önler.
    private func bootstrapAuthStateSynchronously() {
        if let user = authRepository.getCurrentUser() {
            authState = .authenticated(AuthenticatedUser(user: user))
            Self.logger.debug("Auth bootstrap: authenticated (\(user.uid, privacy: .public))")
        } else {
            authState = .notAuthenticated
            Self.logger.debug("Auth bootstrap: notAuthenticated")
        }
    }

    private func startAuthStateObservation() {
        authTasks.add(Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in authRepository.authState {
                guard !Task.isCancelled else { return }
                self.applyAuthState(state, source: "stream")
            }
        })
    }

    /// Dinleyici hiç tetiklenmezse loading ekranında sonsuz beklemeyi engeller.
    private func startAuthBootstrapTimeoutWatchdog() {
        authWatchdogTasks.add(Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, case .loading = self.authState else { return }
            Self.logger.warning("Auth bootstrap timeout — notAuthenticated'a düşülüyor")
            self.applyAuthState(.notAuthenticated, source: "timeout")
        })
    }

    private func applyAuthState(_ state: AuthState, source: String) {
        if authState != state {
            Self.logger.debug("Auth state güncellendi [\(source, privacy: .public)]: \(String(describing: state), privacy: .public)")
            authState = state
        }
        if case .loading = state { return }
        authWatchdogTasks.cancelAll()
    }

    /// Giriş sonrası cihaz kaydı ve admin FCM topic aboneliği.
    private func onLoginSuccess() async {
        let userEmail = authRepository.getCurrentUser()?.email ?? ""
        let deviceId = DeviceIdentifier.getDeviceId()
        let deviceName = DeviceIdentifier.getDeviceName()

        await authorizedDeviceRepository.registerDeviceRemotely(
            deviceId: deviceId,
            deviceName: deviceName,
            userEmail: userEmail
        )

        let isAdmin = await authorizedDeviceRepository.isAdminDevice(deviceId: deviceId)

        if isAdmin {
            await subscribeToAdminAlerts()
        } else {
            await unsubscribeFromAdminAlerts()
        }
    }

    private func subscribeToAdminAlerts() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Messaging.messaging().subscribe(toTopic: Self.adminAlertsTopic) { error in
                if let error {
                    Self.logger.error(
                        "Admin alerts aboneliği başarısız: \(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    Self.logger.debug("Admin alerts konusuna abone olundu")
                }
                continuation.resume()
            }
        }
    }

    private func unsubscribeFromAdminAlerts() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Messaging.messaging().unsubscribe(fromTopic: Self.adminAlertsTopic) { error in
                if let error {
                    Self.logger.error(
                        "Admin alerts abonelik iptali başarısız: \(error.localizedDescription, privacy: .public)"
                    )
                }
                continuation.resume()
            }
        }
    }
}
