import os.log
import SwiftUI

/// Oturum açıldıktan sonra ana navigasyon kabuğu.
///
/// Tüm etkinlik/misafir ekranları paylaşılan tek bir `EventViewModel` örneğini
/// `environment` üzerinden kullanır (Android tek `EventViewModel` paritesi).
@MainActor
struct MainDashboardView: View {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "MainDashboardView")

    @State private var eventViewModel: EventViewModel
    @State private var navigationPath = NavigationPath()

    init() {
        _eventViewModel = State(initialValue: AppDependencies.makeEventViewModel())
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            EventListView()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .environment(eventViewModel)
        .environment(\.appNavigationPath, $navigationPath)
        .onChange(of: navigationPath.count) { _, count in
            Self.logger.debug("Navigation path depth: \(count)")
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .eventDetail(let event):
            EventDetailView(event: event)
        case .guestDetail(let guest, let event):
            GuestDetailView(guest: guest, event: event)
        case .excelImport(let event):
            ExcelImportView(event: event)
        case .redListManagement:
            RedListManagementView()
        case .redListGuestsList(let event):
            RedListGuestsListView(event: event)
        case .redListGuestDetail(let guest, let event):
            RedListGuestDetailView(guest: guest, event: event)
        }
    }
}

#Preview {
    MainDashboardView()
        .environment(AppDependencies.authViewModel)
}
