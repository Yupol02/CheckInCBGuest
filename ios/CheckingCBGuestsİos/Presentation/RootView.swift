import os.log
import SwiftUI

/// Kimlik doğrulama + cihaz bağlama durumuna göre kök yönlendirme.
///
/// v1.4: Yönlendirme artık `authState`'ten DEĞİL, `authViewModel.rootRoute`'tan okunur.
/// Sebep: giriş başarılı olur olmaz Firebase dinleyicisi `.authenticated` yayınlar ve
/// cihaz bağlama kontrolü henüz bitmemişken dashboard çizilirdi. `rootRoute` bu iki
/// bilgiyi birleştirerek dashboard'ın yalnızca doğrulama geçtikten sonra açılmasını sağlar.
@MainActor
struct RootView: View {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "RootView")

    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch authViewModel.rootRoute {
            case .loading:
                loadingView
            case .login:
                LoginView()
            case .dashboard:
                MainDashboardView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authViewModel.rootRoute)
        .onChange(of: authViewModel.rootRoute) { _, newRoute in
            Self.logger.debug("Root route: \(String(describing: newRoute), privacy: .public)")
        }
        .onChange(of: scenePhase) { _, phase in
            // Uygulama arka plandayken Console'dan yapılmış bir bağ sıfırlamasını yakalar.
            // Kendi içinde 5 dakikalık kısıtlama uygular.
            if phase == .active {
                authViewModel.revalidateBindingIfNeeded()
            }
        }
    }

    private var loadingView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(authViewModel.loadingMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Yükleniyor")
    }
}

#Preview {
    RootView()
        .environment(AppDependencies.authViewModel)
}
