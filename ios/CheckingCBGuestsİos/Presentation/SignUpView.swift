import SwiftUI

/// Ayrı kayıt sayfası — Firebase Auth `createUser` ile gerçek hesap oluşturur.
@MainActor
struct SignUpView: View {

    @Environment(AuthViewModel.self) private var authViewModel
    var onNavigateToLogin: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var showErrorBanner = false
    @State private var errorBannerMessage = ""

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email, password, confirmPassword
    }

    private var isLoading: Bool {
        authViewModel.loginUiState == .loading
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFormValid: Bool {
        !trimmedEmail.isEmpty
            && trimmedEmail.contains("@")
            && trimmedEmail.contains(".")
            && password.count >= AppAuth.minPasswordLength
            && confirmPassword == password
    }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    formSection
                    signUpButton
                    goToLoginButton
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            if isLoading { loadingOverlay }
            if showErrorBanner { errorBanner }
        }
        .animation(.easeInOut(duration: 0.25), value: showErrorBanner)
        .onChange(of: authViewModel.loginUiState) { _, newState in
            if case .error(let message) = newState {
                errorBannerMessage = message
                showErrorBanner = true
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(LoginPalette.accent)

            Text("Hesap Oluştur")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(LoginPalette.primaryText)

            Text("E-posta ile ücretsiz kayıt olun. Hesabınız Firebase Authentication'a kaydedilir.")
                .font(.subheadline)
                .foregroundStyle(LoginPalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Yeni Hesap")
                .font(.headline)
                .foregroundStyle(LoginPalette.primaryText)

            LoginTextField(
                title: "E-posta Adresi",
                placeholder: "ornek@email.com",
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

            passwordField(
                title: "Şifre",
                placeholder: "En az \(AppAuth.minPasswordLength) karakter",
                text: $password,
                field: .password,
                next: .confirmPassword
            )

            passwordField(
                title: "Şifre tekrar",
                placeholder: "Şifrenizi tekrar girin",
                text: $confirmPassword,
                field: .confirmPassword,
                next: nil
            )

            if !confirmPassword.isEmpty && confirmPassword != password {
                Text("Şifreler eşleşmiyor")
                    .font(.caption)
                    .foregroundStyle(LoginPalette.error)
            }
        }
        .padding(20)
        .background(LoginPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private func passwordField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        next: Field?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LoginPalette.secondaryText)

            HStack(spacing: 12) {
                Image(systemName: "lock")
                    .foregroundStyle(LoginPalette.secondaryText)
                    .frame(width: 22)

                Group {
                    if isPasswordVisible {
                        TextField(placeholder, text: text)
                            .textContentType(.newPassword)
                    } else {
                        SecureField(placeholder, text: text)
                            .textContentType(.newPassword)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isLoading)

                Button { isPasswordVisible.toggle() } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(LoginPalette.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(LoginPalette.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        focusedField == field ? LoginPalette.accent : LoginPalette.fieldBorder,
                        lineWidth: focusedField == field ? 2 : 1
                    )
            )
        }
        .focused($focusedField, equals: field)
        .submitLabel(next == nil ? .go : .next)
        .onSubmit {
            if let next {
                focusedField = next
            } else {
                submitSignUp()
            }
        }
    }

    private var signUpButton: some View {
        Button(action: submitSignUp) {
            HStack(spacing: 10) {
                if isLoading { ProgressView().tint(.white) }
                Text("Kayıt Ol")
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
        .accessibilityHint("Firebase'de yeni hesap oluşturur")
    }

    private var goToLoginButton: some View {
        Button {
            authViewModel.clearLoginError()
            onNavigateToLogin()
        } label: {
            Text("Zaten hesabınız var mı? Giriş yapın")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LoginPalette.accent)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
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
    }

    private var errorBanner: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LoginPalette.error)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kayıt Başarısız")
                        .font(.subheadline.weight(.semibold))
                    Text(errorBannerMessage)
                        .font(.subheadline)
                        .foregroundStyle(LoginPalette.secondaryText)
                }
                Spacer()
                Button {
                    showErrorBanner = false
                    authViewModel.clearLoginError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LoginPalette.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(LoginPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [LoginPalette.backgroundTop, LoginPalette.backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func submitSignUp() {
        guard isFormValid, !isLoading else { return }
        focusedField = nil
        Task {
            await authViewModel.signUp(email: trimmedEmail, password: password)
        }
    }
}
