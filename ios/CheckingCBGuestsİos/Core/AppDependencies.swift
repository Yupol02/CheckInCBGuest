import Foundation

/// İzole olmayan repository grafiği (tüm tipler `Sendable`).
///
/// `Event` ↔ `RedList` arasındaki döngüsel bağımlılık, tembel (lazy) provider
/// closure'ları ile çözülür. Repository'ler `@MainActor` değildir; arka plan
/// I/O'da güvenle kullanılabilir.
enum RepositoryContainer {

    /// Admin e-posta listesi (Firestore `admin_users`).
    /// `authorizedDeviceRepository`'den ÖNCE tanımlıdır; `static let` tembel
    /// başlatması sırayı kendiliğinden çözer, provider closure'a gerek yoktur.
    static let adminUserRepository: any AdminUserRepository =
        FirebaseAdminUserRepository()

    static let authorizedDeviceRepository: any AuthorizedDeviceRepository =
        FirebaseAuthorizedDeviceRepository(
            adminUserRepository: RepositoryContainer.adminUserRepository
        )

    /// E-posta ↔ cihaz bağlama (Firestore `device_bindings`).
    static let deviceBindingRepository: any DeviceBindingRepository =
        FirebaseDeviceBindingRepository()

    static let eventRepository: any EventRepository = FirebaseEventRepository(
        redListRepositoryProvider: { RepositoryContainer.redListRepository }
    )

    static let redListRepository: any RedListRepository = FirebaseRedListRepository(
        eventRepositoryProvider: { RepositoryContainer.eventRepository }
    )

    static let syncRepository: any SyncRepository = FirebaseSyncRepository(
        eventRepository: RepositoryContainer.eventRepository,
        authorizedDeviceRepository: RepositoryContainer.authorizedDeviceRepository,
        redListRepository: RepositoryContainer.redListRepository
    )
}

/// Uygulama genelinde paylaşılan ViewModel örnekleri ve fabrikalar.
@MainActor
enum AppDependencies {

    // MARK: - Paylaşılan tekil örnekler

    static let authViewModel = AuthViewModel(
        authRepository: FirebaseAuthRepository(),
        authorizedDeviceRepository: RepositoryContainer.authorizedDeviceRepository,
        deviceBindingRepository: RepositoryContainer.deviceBindingRepository
    )

    /// CRUD sonrası otomatik senkronizasyon yöneticisi (uygulama geneli tekil).
    static let autoSyncManager = AutoSyncManager(
        syncRepository: RepositoryContainer.syncRepository
    )

    // MARK: - ViewModel fabrikaları

    static func makeEventViewModel() -> EventViewModel {
        EventViewModel(
            eventRepository: RepositoryContainer.eventRepository,
            redListRepository: RepositoryContainer.redListRepository,
            authorizedDeviceRepository: RepositoryContainer.authorizedDeviceRepository,
            redListPermissionChecker: PinRedListPermissionChecker(),
            autoSyncManager: autoSyncManager
        )
    }

    static func makeRedListViewModel() -> RedListViewModel {
        RedListViewModel(
            redListRepository: RepositoryContainer.redListRepository,
            authorizedDeviceRepository: RepositoryContainer.authorizedDeviceRepository
        )
    }

    static func makeSyncViewModel() -> SyncViewModel {
        SyncViewModel(syncRepository: RepositoryContainer.syncRepository)
    }

    static func makeExcelImportViewModel() -> ExcelImportViewModel {
        let parser = DefaultExcelParser()
        return ExcelImportViewModel(
            validateExcelFileUseCase: DefaultValidateExcelFileUseCase(parser: parser),
            parseExcelFileUseCase: DefaultParseExcelFileUseCase(parser: parser),
            importGuestsFromExcelUseCase: DefaultImportGuestsFromExcelUseCase(
                parser: parser,
                eventRepository: RepositoryContainer.eventRepository,
                redListRepository: RepositoryContainer.redListRepository
            ),
            autoSyncManager: autoSyncManager
        )
    }
}
