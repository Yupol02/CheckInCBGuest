import Foundation
import SwiftUI

/// `NavigationStack` rotaları (Android `Screen` sealed sınıfı eşleniği).
enum AppRoute: Hashable {
    case eventDetail(Event)
    case guestDetail(guest: Guest, event: Event)
    case excelImport(event: Event)
    case redListManagement
    case redListGuestsList(event: Event)
    case redListGuestDetail(guest: Guest, event: Event)
}

// MARK: - Programatik navigasyon

private struct AppNavigationPathKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath>? = nil
}

extension EnvironmentValues {
    /// `Menu` içindeki `NavigationLink` yerine programatik push için paylaşılan yol.
    var appNavigationPath: Binding<NavigationPath>? {
        get { self[AppNavigationPathKey.self] }
        set { self[AppNavigationPathKey.self] = newValue }
    }
}

extension Binding where Value == NavigationPath {
    func push(_ route: AppRoute) {
        wrappedValue.append(route)
    }
}
