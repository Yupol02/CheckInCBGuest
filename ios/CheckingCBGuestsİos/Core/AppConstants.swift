import Foundation

/// Uygulama genel sabitleri (Android `AppConstants` eşleniği).
///
/// Android'deki `FlowLifecycle` namespace'i Kotlin coroutine `SharingStarted`
/// yaşam döngüsüne özgü olduğu için iOS (AsyncStream) tarafında karşılığı yoktur
/// ve bilinçli olarak atlanmıştır. Admin e-postaları için bkz. `AppAuth`.
enum AppConstants {

    /// Mimari: Firebase-only. Çevrimdışı destek Firestore offline persistence ile sağlanır.
    enum Architecture {
        static let useFirebaseOnly = true
    }

    /// UI zamanlama sabitleri.
    enum UIDelays {
        /// Snackbar mesajlarının otomatik kapanma süresi (saniye).
        static let snackbarAutoDismiss: TimeInterval = 3.0
        /// Art arda çağrıları önlemek için yenileme gecikmesi (saniye).
        static let refreshDelay: TimeInterval = 0.5
        /// Sync durum mesajlarının temizlenme gecikmesi (saniye).
        static let syncMessageClearDelay: TimeInterval = 3.0

        /// `Task.sleep` için nanosaniye yardımcıları.
        static let snackbarAutoDismissNanos: UInt64 = 3_000_000_000
        static let refreshDelayNanos: UInt64 = 500_000_000
        static let syncMessageClearDelayNanos: UInt64 = 3_000_000_000
    }

    /// Senkronizasyon işlem sabitleri.
    enum Sync {
        /// Tek batch'te işlenecek maksimum öğe sayısı (Firestore limiti).
        static let maxBatchSize = 500
        /// Bellek verimliliği için chunk başına öğe sayısı.
        static let chunkSize = 100
    }

    /// Excel içe aktarma sabitleri.
    enum ExcelImport {
        /// İzin verilen maksimum dosya boyutu (10 MB).
        static let maxFileSizeBytes: Int64 = 10 * 1024 * 1024
        /// Önizlemede gösterilecek satır sayısı.
        static let previewRowCount = 10
        /// Bellek verimliliği için içe aktarma chunk boyutu.
        static let importChunkSize = 50
    }

    /// Veritabanı/throttle sabitleri.
    enum Database {
        /// İki güncelleme işlemi arası minimum süre (saniye).
        static let updateThrottle: TimeInterval = 60.0
    }

    /// Giriş doğrulama sabitleri (Android `AppConstants.Validation`).
    enum Validation {
        static let maxNameLength = 200
        static let maxTitleLength = 200
        static let minNameLength = 2
        static let minTitleLength = 2
    }
}

// MARK: - Observation task lifecycle

/// `@MainActor` + `@Observable` ViewModel'lerde task iptali.
///
/// `deinit` nonisolated çalıştığı için task referansları bu kap üzerinden yönetilir;
/// `@ObservationIgnored` ile birlikte kullanılmalıdır.
final class ObservationTaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []

    func add(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        tasks.append(task)
    }

    nonisolated func cancelAll() {
        lock.lock()
        let pending = tasks
        tasks.removeAll()
        lock.unlock()
        pending.forEach { $0.cancel() }
    }
}
