import Foundation

/// Kimlik doğrulama sabitleri (Android `AppConstants.Auth` eşleniği).
enum AppAuth {
    /// Geçici: App Store 3.2.0 onayı için herkese açık kayıt.
    /// Onay + Unlisted dağıtıma geçince `false` yapıp yeni build gönderin.
    static let publicRegistrationEnabled = true

    /// Firebase Auth varsayılan minimum şifre uzunluğu.
    static let minPasswordLength = 6

    private static let adminEmails: Set<String> = [
        "cbsecurity@checkin.com",
        "managercb@cbcheckin.com",
    ]

    /// Verilen e-posta admin hesabı mı?
    static func isAdminEmail(_ email: String?) -> Bool {
        guard let email else { return false }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return adminEmails.contains(normalized)
    }
}
