import os.log
import SwiftUI

private enum UnauthenticatedPage {
    case login
    case signUp
}

/// Kimlik doğrulama durumuna göre kök yönlendirme.
@MainActor
struct RootView: View {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "RootView")

    @Environment(AuthViewModel.self) private var authViewModel
    @State private var unauthenticatedPage: UnauthenticatedPage =
        AppAuth.publicRegistrationEnabled ? .signUp : .login

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                loadingView
            case .notAuthenticated:
                unauthenticatedContent
            case .authenticated:
                MainDashboardView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authViewModel.authState)
        .onChange(of: authViewModel.authState) { _, newState in
            Self.logger.debug("Root route: \(String(describing: newState), privacy: .public)")
        }
    }

    @ViewBuilder
    private var unauthenticatedContent: some View {
        let showSignUp = AppAuth.publicRegistrationEnabled && unauthenticatedPage == .signUp
        if showSignUp {
            SignUpView {
                authViewModel.clearLoginError()
                unauthenticatedPage = .login
            }
        } else {
            LoginView(
                onNavigateToSignUp: AppAuth.publicRegistrationEnabled
                    ? {
                        authViewModel.clearLoginError()
                        unauthenticatedPage = .signUp
                    }
                    : nil
            )
        }
    }

    private var loadingView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Oturum kontrol ediliyor…")
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
