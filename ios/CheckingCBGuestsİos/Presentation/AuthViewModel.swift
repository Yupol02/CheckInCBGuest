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

/// Cihaz bağlama doğrulama kapısı.
///
/// `authState` Firebase'in gerçeğini yansıtmaya DEVAM eder; yönlendirme kararı ondan
/// ayrı verilir. Akışı filtrelemek (`.authenticated`'ı yutmak) `logout()`'u ve
/// `applyAuthState` içindeki tekrar-önleme kontrolünü bozardı.
enum SessionGate: Equatable, Sendable {
    /// Cihaz bağlama kontrolü sürüyor.
    case pending
    case allowed
    /// Reddedildi; `signOut` yolda.
    case blocked
}

/// Kök yönlendirme kararı — `RootView`'un tükettiği TEK kaynak.
enum RootRoute: Equatable, Sendable {
    case loading
    case login
    case dashboard
}

/// Kimlik doğrulama ve cihaz kaydı iş mantığı (Android `AuthViewModel`).
@MainActor
@Observable
final class AuthViewModel {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "AuthViewModel")
    private static let adminAlertsTopic = "admin_alerts"

    private let authRepository: any AuthRepository
    private let authorizedDeviceRepository: any AuthorizedDeviceRepository
    private let deviceBindingRepository: any DeviceBindingRepository

    @ObservationIgnored
    private nonisolated let authTasks = ObservationTaskHolder()
    @ObservationIgnored
    private nonisolated let authWatchdogTasks = ObservationTaskHolder()
    @ObservationIgnored
    private nonisolated let bindingTasks = ObservationTaskHolder()

    @ObservationIgnored
    private var lastRevalidationAt: Date?

    /// Repository `authState` akışının yerel yansıması.
    private(set) var authState: AuthState = .loading

    private(set) var loginUiState: LoginUiState = .idle

    private(set) var sessionGate: SessionGate = .pending

    init(
        authRepository: any AuthRepository,
        authorizedDeviceRepository: any AuthorizedDeviceRepository,
        deviceBindingRepository: any DeviceBindingRepository
    ) {
        self.authRepository = authRepository
        self.authorizedDeviceRepository = authorizedDeviceRepository
        self.deviceBindingRepository = deviceBindingRepository

        bootstrapAuthStateSynchronously()
        resolveSessionGateSynchronously()
        startAuthStateObservation()
        startAuthBootstrapTimeoutWatchdog()
        startSessionGateWatchdog()
    }

    deinit {
        authTasks.cancelAll()
        authWatchdogTasks.cancelAll()
        bindingTasks.cancelAll()
    }

    // MARK: - Yönlendirme

    /// `authState` + `sessionGate` birleşimi. Her ikisi de `@Observable` olduğu için
    /// SwiftUI bu hesaplanmış özelliği doğru şekilde izler.
    var rootRoute: RootRoute {
        switch authState {
        case .loading:
            return .loading
        case .notAuthenticated:
            return .login
        case .authenticated:
            switch sessionGate {
            case .pending:
                return .loading
            case .blocked:
                // signOut'un dinleyiciye ulaşmasını BEKLEMEDEN giriş ekranına dön.
                // Aksi halde signOut sonrası / dinleyici öncesi pencerede dashboard parlar.
                return .login
            case .allowed:
                return .dashboard
            }
        }
    }

    /// Yükleme ekranında gösterilecek metin.
    var loadingMessage: String {
        if case .authenticated = authState, sessionGate == .pending {
            return "Cihaz doğrulanıyor…"
        }
        return "Oturum kontrol ediliyor…"
    }

    // MARK: - Public API

    func login(email: String, password: String) async {
        loginUiState = .loading
        // signIn'DEN ÖNCE kapatılır: Firebase dinleyicisi `await` sırasında ateşlerse
        // rota `.loading`'de kalsın, dashboard parlamasın.
        sessionGate = .pending

        let result = await authRepository.signIn(email: email, password: password)
        switch result {
        case .error(let message):
            // Oturum açılmadı; kapıyı serbest bırak, yoksa sonraki denemede takılır.
            sessionGate = .allowed
            loginUiState = .error(message: message)
            return
        case .success:
            break
        }

        // Kullanıcının yazdığı metin değil, Firebase'in normalize ettiği e-posta kullanılır.
        guard let user = authRepository.getCurrentUser(), let userEmail = user.email else {
            await failLogin(message: DeviceBindingMessages.generic, clearCache: false)
            return
        }

        let deviceId = DeviceIdentifier.getDeviceId()
        let deviceName = DeviceIdentifier.getDeviceName()

        let bindingResult = await deviceBindingRepository.bindOrValidate(
            email: userEmail,
            uid: user.uid,
            deviceId: deviceId,
            deviceName: deviceName
        )

        switch bindingResult {
        case .bound, .matched:
            DeviceBindingCache.save(
                email: AppAuth.normalizedEmailKey(userEmail),
                deviceId: deviceId,
                boundAt: AppAuth.nowISO8601String()
            )
            await onLoginSuccess(userEmail: userEmail, deviceId: deviceId, deviceName: deviceName)
            // Kapı SADECE burada açılır — onLoginSuccess admin önbelleğini hazırladıktan
            // SONRA, yani MainDashboardView'un EventViewModel'i kurmasından önce.
            sessionGate = .allowed
            loginUiState = .success

        case .rejected(let boundDeviceName):
            await failLogin(
                message: DeviceBindingMessages.rejected(
                    boundDeviceName: boundDeviceName,
                    currentDeviceName: deviceName
                ),
                clearCache: true
            )

        case .networkRequired:
            await failLogin(
                message: DeviceBindingMessages.networkRequiredOnFirstBind,
                clearCache: false
            )

        case .failed(let message):
            await failLogin(message: message, clearCache: false)
        }
    }

    func logout() async {
        await authRepository.signOut()
        sessionGate = .allowed
        loginUiState = .idle
    }

    func clearLoginError() {
        loginUiState = .idle
    }

    /// Uygulama öne geldiğinde çağrılır (RootView `scenePhase`).
    ///
    /// Uygulama arka plandayken sahibin Console'dan yaptığı bir sıfırlamayı yakalar;
    /// bu olmadan serbest bırakılmış bir cihaz sonraki soğuk açılışa kadar çalışmaya
    /// devam ederdi.
    func revalidateBindingIfNeeded() {
        guard case .authenticated(let user) = authState, let email = user.email else { return }
        if let last = lastRevalidationAt,
           Date().timeIntervalSince(last) < AppAuth.revalidationThrottle {
            return
        }
        lastRevalidationAt = Date()
        scheduleRevalidation(email: email, deviceId: DeviceIdentifier.getDeviceId(), blocking: false)
    }

    // MARK: - Oturum kapısı

    /// Keychain okuması senkrondur (milisaniyenin altında); bu sayede önceden bağlanmış
    /// bir cihazda soğuk açılışta hiç spinner görünmez.
    private func resolveSessionGateSynchronously() {
        guard case .authenticated(let user) = authState, let email = user.email else {
            // Oturum yok — kapı ilgisiz.
            sessionGate = .allowed
            return
        }

        let deviceId = DeviceIdentifier.getDeviceId()
        let normalized = AppAuth.normalizedEmailKey(email)

        if let cached = DeviceBindingCache.load(),
           cached.email == normalized,
           cached.deviceId == deviceId {
            // Yerel kayıt var → çevrimdışı da çalış, doğrulamayı arka planda yap.
            sessionGate = .allowed
            scheduleRevalidation(email: email, deviceId: deviceId, blocking: false)
        } else {
            // Yerel kayıt yok (1.3'ten yükseltme veya Keychain kaybı) → doğrulanana
            // kadar bekle. Bu yol bağı OLUŞTURABİLİR, o yüzden bindOrValidate kullanır.
            sessionGate = .pending
            scheduleRevalidation(email: email, deviceId: deviceId, blocking: true)
        }
    }

    private func scheduleRevalidation(email: String, deviceId: String, blocking: Bool) {
        bindingTasks.add(Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRevalidation(email: email, deviceId: deviceId, blocking: blocking)
        })
    }

    private func performRevalidation(email: String, deviceId: String, blocking: Bool) async {
        let result: DeviceBindingResult
        if blocking {
            guard let user = authRepository.getCurrentUser() else {
                sessionGate = .allowed
                return
            }
            result = await deviceBindingRepository.bindOrValidate(
                email: email,
                uid: user.uid,
                deviceId: deviceId,
                deviceName: DeviceIdentifier.getDeviceName()
            )
        } else {
            result = await deviceBindingRepository.revalidate(email: email, deviceId: deviceId)
        }

        guard !Task.isCancelled else { return }

        switch result {
        case .bound, .matched:
            DeviceBindingCache.save(
                email: AppAuth.normalizedEmailKey(email),
                deviceId: deviceId,
                boundAt: AppAuth.nowISO8601String()
            )
            sessionGate = .allowed

        case .rejected:
            Self.logger.warning("Cihaz bağı reddedildi — oturum kapatılıyor")
            DeviceBindingCache.clear()
            await forceSignOut(message: DeviceBindingMessages.forcedSignOut)

        case .networkRequired:
            // İhtimam: sunucuya ulaşılamıyor. Süre aşıldıysa oturumu kapat.
            if DeviceBindingCache.registerOfflineAttempt() {
                Self.logger.warning("Çevrimdışı ihtimam süresi doldu — oturum kapatılıyor")
                await forceSignOut(message: DeviceBindingMessages.offlineGraceExpired)
            } else {
                sessionGate = .allowed
            }

        case .failed(let message):
            // Açılışta HOŞGÖRÜLÜ davranılır (girişte katı). Yanlış yapılandırılmış bir
            // kural yüzünden sahadaki tüm cihazların kilitlenmesini önler.
            Self.logger.error("Açılış doğrulaması başarısız: \(message, privacy: .public)")
            sessionGate = .allowed
        }
    }

    /// Kapı `.pending`'de takılırsa kurtarır. Depo zaman aşımı (12 sn) asıl mekanizmadır;
    /// bu, farklı bir dosyada yaşadığı için eklenen ikinci güvencedir.
    private func startSessionGateWatchdog() {
        authWatchdogTasks.add(Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AppAuth.sessionGateWatchdog * 1_000_000_000))
            guard let self, self.sessionGate == .pending else { return }
            Self.logger.warning("Oturum kapısı zaman aşımı — güvenli tarafa (allowed) düşülüyor")
            self.sessionGate = .allowed
        })
    }

    private func failLogin(message: String, clearCache: Bool) async {
        // signOut'TAN ÖNCE: aradaki pencerede dashboard'a düşmeyi engeller.
        sessionGate = .blocked
        await authRepository.signOut()
        if clearCache {
            DeviceBindingCache.clear()
        }
        loginUiState = .error(message: message)
    }

    private func forceSignOut(message: String) async {
        sessionGate = .blocked
        await authRepository.signOut()
        loginUiState = .error(message: message)
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
        // Oturum kapandı: `.blocked` kapının bir sonraki giriş denemesine sızmasını önle.
        if case .notAuthenticated = state {
            sessionGate = .allowed
            lastRevalidationAt = nil
        }
        if case .loading = state { return }
        authWatchdogTasks.cancelAll()
    }

    /// Giriş sonrası cihaz kaydı ve admin FCM topic aboneliği.
    private func onLoginSuccess(userEmail: String, deviceId: String, deviceName: String) async {
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
