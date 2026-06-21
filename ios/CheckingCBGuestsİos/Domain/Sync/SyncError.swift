import Foundation

/// Senkronizasyon hatalarını tip güvenli temsil eden enum (Android `SyncError` sealed class eşleniği).
///
/// Her hata türü hata ayıklama ve kullanıcı geri bildirimi için ilgili bağlamı taşır.
enum SyncError: Error, Equatable, Sendable {

    /// Ağ kaynaklı hatalar (bağlantı, zaman aşımı, vb.).
    case networkError(message: String)

    /// İzin reddi (Firebase güvenlik kuralları).
    case permissionDenied(collection: String, deviceId: String? = nil)

    /// Veri doğrulama hatası (geçersiz format, eksik alan, vb.).
    case dataValidationError(field: String, reason: String, entityType: String)

    /// Bilinmeyen/beklenmeyen hatalar.
    case unknownError(message: String, context: String? = nil)

    /// Senkronizasyon zaten devam ediyor (eşzamanlı işlemi önler).
    case syncInProgress

    /// Tutarlı hata tanımlaması için hata kodu (Android `ErrorCode`).
    enum Code: String, Sendable {
        case networkError = "NETWORK_ERROR"
        case permissionDenied = "PERMISSION_DENIED"
        case dataValidationError = "DATA_VALIDATION_ERROR"
        case unknownError = "UNKNOWN_ERROR"
        case syncInProgress = "SYNC_IN_PROGRESS"
    }

    /// Loglama ve analitik için hata kodu.
    var code: Code {
        switch self {
        case .networkError: return .networkError
        case .permissionDenied: return .permissionDenied
        case .dataValidationError: return .dataValidationError
        case .unknownError: return .unknownError
        case .syncInProgress: return .syncInProgress
        }
    }

    /// Hata kodu string gösterimi.
    var codeString: String { code.rawValue }

    /// Kullanıcıya gösterilecek Türkçe mesaj.
    var userMessage: String {
        switch self {
        case let .networkError(message):
            return Self.networkErrorMessage(message)
        case let .permissionDenied(collection, _):
            return Self.permissionDeniedMessage(collection)
        case let .dataValidationError(field, reason, entityType):
            return "Veri doğrulama hatası (\(entityType)): \(field) - \(reason)"
        case let .unknownError(message, context):
            let contextMsg = context.map { " (\($0))" } ?? ""
            let detail = message.isEmpty ? "Detay bilgisi yok" : message
            return "Bilinmeyen hata\(contextMsg): \(detail)"
        case .syncInProgress:
            return "Senkronizasyon zaten devam ediyor. Lütfen bekleyin."
        }
    }

    // MARK: - Private message builders

    private static func networkErrorMessage(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("timeout") {
            return "İstek zaman aşımına uğradı. Lütfen tekrar deneyin."
        }
        if lower.contains("unavailable") {
            return "Firebase servisi kullanılamıyor. Lütfen daha sonra tekrar deneyin."
        }
        if lower.contains("connection") || lower.contains("network") {
            return "İnternet bağlantısı hatası: \(message)"
        }
        if lower.contains("host") {
            return "Sunucuya bağlanılamıyor. İnternet bağlantınızı kontrol edin."
        }
        return "Ağ hatası: \(message)"
    }

    private static func permissionDeniedMessage(_ collection: String) -> String {
        let messages: [String: String] = [
            "authorized_devices": "Cihaz yetkilendirme bilgilerine erişim reddedildi.",
            "events": "Etkinlik verilerine erişim reddedildi.",
            "guests": "Misafir verilerine erişim reddedildi.",
            "red_list": "Kırmızı liste verilerine erişim reddedildi. (Sadece admin cihazlar erişebilir)",
            "admin_red_list_names": "Admin kırmızı liste verilerine erişim reddedildi.",
        ]
        return messages[collection] ?? "\(collection) koleksiyonuna erişim reddedildi."
    }
}
