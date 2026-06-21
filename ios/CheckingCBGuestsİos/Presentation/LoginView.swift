import SwiftUI

/// Kurumsal giriş ekranı (Android `LoginScreen`).
@MainActor
struct LoginView: View {

    @Environment(AuthViewModel.self) private var authViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var showErrorBanner = false
    @State private var errorBannerMessage = ""

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
    }

    private var isLoading: Bool {
        authViewModel.loginUiState == .loading
    }

    private var isFormValid: Bool {
        !trimmedEmail.isEmpty && !password.isEmpty && trimmedEmail.contains("@")
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    formSection
                    loginButton
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            if isLoading {
                loadingOverlay
            }

            if showErrorBanner {
                errorBanner
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showErrorBanner)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .onChange(of: authViewModel.loginUiState) { _, newState in
            handleLoginUiStateChange(newState)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(LoginPalette.accent)
                .accessibilityHidden(true)

            Text("Misafir Kontrol")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(LoginPalette.primaryText)

            Text("Güvenli giriş ile devam edin")
                .font(.subheadline)
                .foregroundStyle(LoginPalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Hesap Bilgileri")
                .font(.headline)
                .foregroundStyle(LoginPalette.primaryText)

            LoginTextField(
                title: "E-posta Adresi",
                placeholder: "ornek@sirket.com",
                text: $email,
                icon: "envelope",
                keyboardType: .emailAddress,
                textContentType: .username,
                autocapitalization: .never,
                disableAutocorrection: true,
                isDisabled: isLoading
            )
            .focused($focusedField, equals: .email)
            .submitLabel(.next)
            .onSubmit { focusedField = .password }

            VStack(alignment: .leading, spacing: 8) {
                Text("Şifre")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(LoginPalette.secondaryText)

                HStack(spacing: 12) {
                    Image(systemName: "lock")
                        .foregroundStyle(LoginPalette.secondaryText)
                        .frame(width: 22)

                    Group {
                        if isPasswordVisible {
                            TextField("Şifrenizi girin", text: $password)
                                .textContentType(.password)
                        } else {
                            SecureField("Şifrenizi girin", text: $password)
                                .textContentType(.password)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isLoading)

                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundStyle(LoginPalette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Şifreyi gizle" : "Şifreyi göster")
                    .disabled(isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(LoginPalette.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            focusedField == .password ? LoginPalette.accent : LoginPalette.fieldBorder,
                            lineWidth: focusedField == .password ? 2 : 1
                        )
                )
            }
            .focused($focusedField, equals: .password)
            .submitLabel(.go)
            .onSubmit { submitLogin() }

            Text("Lütfen bilgilerinizi kontrol edin.")
                .font(.caption)
                .foregroundStyle(LoginPalette.secondaryText)
        }
        .padding(20)
        .background(LoginPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private var loginButton: some View {
        Button(action: submitLogin) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text("Giriş Yap")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(
                isFormValid && !isLoading
                    ? LoginPalette.accent
                    : LoginPalette.accent.opacity(0.45)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(!isFormValid || isLoading)
        .accessibilityHint("E-posta ve şifre ile oturum açar")
    }

    private var loadingOverlay: some View {
        Color.black.opacity(0.12)
            .ignoresSafeArea()
            .overlay {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Giriş yapılıyor")
    }

    private var errorBanner: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LoginPalette.error)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Giriş Başarısız")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LoginPalette.primaryText)
                    Text(errorBannerMessage)
                        .font(.subheadline)
                        .foregroundStyle(LoginPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    dismissError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LoginPalette.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hatayı kapat")
            }
            .padding(16)
            .background(LoginPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LoginPalette.error.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                LoginPalette.backgroundTop,
                LoginPalette.backgroundBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Actions

    private func submitLogin() {
        guard isFormValid, !isLoading else { return }
        focusedField = nil
        Task {
            await authViewModel.login(email: trimmedEmail, password: password)
        }
    }

    private func handleLoginUiStateChange(_ state: LoginUiState) {
        if case .error(let message) = state {
            errorBannerMessage = message
            showErrorBanner = true
        }
    }

    private func dismissError() {
        showErrorBanner = false
        authViewModel.clearLoginError()
    }
}

// MARK: - Text field component

private struct LoginTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var disableAutocorrection: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LoginPalette.secondaryText)

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(LoginPalette.secondaryText)
                    .frame(width: 22)

                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled(disableAutocorrection)
                    .disabled(isDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(LoginPalette.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LoginPalette.fieldBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Palette

private enum LoginPalette {
    static let accent = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
    static let error = Color(red: 244 / 255, green: 63 / 255, blue: 94 / 255)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let fieldBackground = Color(.secondarySystemGroupedBackground)
    static let fieldBorder = Color(.separator)
    static let cardBackground = Color(.systemBackground)
    static let backgroundTop = Color(.systemGroupedBackground)
    static let backgroundBottom = Color(.secondarySystemGroupedBackground)
}

#Preview {
    LoginView()
        .environment(AppDependencies.authViewModel)
}
