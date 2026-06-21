import SwiftUI

/// Uygulama geneli tema: renkler, boşluklar, köşe yarıçapları (Android `Theme`/`Color` eşleniği).
enum AppTheme {

    enum Colors {
        static let accent = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
        static let accentSoft = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255).opacity(0.12)
        static let success = Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
        static let warning = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)
        static let danger = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
        static let redList = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)

        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let cardBackground = Color(.secondarySystemGroupedBackground)
        static let groupedBackground = Color(.systemGroupedBackground)
        static let separator = Color(.separator)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }
}

// MARK: - GuestStatus UI

extension GuestStatus {
    var displayName: String {
        switch self {
        case .pending: return "Bekliyor"
        case .checkedIn: return "İçeride"
        case .exited: return "Çıkış Yaptı"
        case .pendingApproval: return "Onay Bekliyor"
        }
    }

    var color: Color {
        switch self {
        case .pending: return AppTheme.Colors.secondaryText
        case .checkedIn: return AppTheme.Colors.success
        case .exited: return AppTheme.Colors.warning
        case .pendingApproval: return AppTheme.Colors.danger
        }
    }

    var iconName: String {
        switch self {
        case .pending: return "clock"
        case .checkedIn: return "checkmark.circle.fill"
        case .exited: return "arrow.right.circle.fill"
        case .pendingApproval: return "exclamationmark.shield.fill"
        }
    }
}

// MARK: - EventStatus UI

extension EventStatus {
    var displayName: String {
        switch self {
        case .active: return "Aktif"
        case .upcoming: return "Yaklaşan"
        case .past: return "Tamamlandı"
        }
    }

    var color: Color {
        switch self {
        case .active: return AppTheme.Colors.success
        case .upcoming: return AppTheme.Colors.accent
        case .past: return AppTheme.Colors.secondaryText
        }
    }
}

// MARK: - ArrivalMethod UI

extension ArrivalMethod {
    var displayName: String {
        switch self {
        case .pedestrian: return "Yaya"
        case .vehicle: return "Araç"
        }
    }

    var iconName: String {
        switch self {
        case .pedestrian: return "figure.walk"
        case .vehicle: return "car.fill"
        }
    }
}
