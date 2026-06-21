import SwiftUI

// MARK: - PIN istemi

/// Kırmızı liste check-in yetkisi için PIN giriş sayfası (Android `RedListPermissionDialog` PIN akışı).
struct PinPromptSheet: View {
    var title: String = "Yetki Gerekli"
    var message: String = "Kırmızı liste işlemleri için yönetici PIN'i girin."
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.xl) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.Colors.accent)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title2)
                    .padding()
                    .background(AppTheme.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))

                if showError {
                    Text("Hatalı PIN. Tekrar deneyin.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.danger)
                }

                Button {
                    if RedListPermissionManager.verifyAdminPin(pin) {
                        onSubmit(pin)
                        dismiss()
                    } else {
                        showError = true
                        pin = ""
                    }
                } label: {
                    Text("Onayla")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Colors.accent)
                .disabled(pin.isEmpty)

                Spacer()
            }
            .padding(AppTheme.Spacing.xl)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Kırmızı listeye ekleme

/// Kırmızı listeye manuel üye ekleme sayfası (Android `AddToRedListDialog`).
struct AddToRedListSheet: View {
    /// (isim, sebep, notlar) — onaylandığında çağrılır.
    let onAdd: (String, RedListEntryReason, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var reason: RedListEntryReason = .security
    @State private var notes = ""

    private var isValid: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Misafir") {
                    TextField("Ad Soyad", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Sebep") {
                    Picker("Sebep", selection: $reason) {
                        ForEach(RedListEntryReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Notlar") {
                    TextField("Opsiyonel not", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Kırmızı Listeye Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        onAdd(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            reason,
                            trimmedNotes.isEmpty ? nil : trimmedNotes
                        )
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Heyet ata

/// Mevcut heyetleri chip olarak gösteren atama sayfası (Android `SectionTitleDialog`).
struct SectionTitleSheet: View {
    let existingSectionTitles: [String]
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newSectionTitle = ""
    @State private var duplicateError = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                if !existingSectionTitles.isEmpty {
                    Text("Mevcut gruplar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(existingSectionTitles, id: \.self) { title in
                                Button(title) {
                                    onConfirm(title)
                                    dismiss()
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .padding(.vertical, AppTheme.Spacing.sm)
                                .background(AppTheme.Colors.accentSoft)
                                .foregroundStyle(AppTheme.Colors.accent)
                                .clipShape(Capsule())
                            }
                        }
                    }

                    Divider()
                }

                Text(existingSectionTitles.isEmpty ? "Yeni grup oluştur" : "Veya yeni grup adı")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Örn: Türk Heyeti, Kıbrıs Heyeti", text: $newSectionTitle)
                    .textInputAutocapitalization(.words)
                    .padding()
                    .background(AppTheme.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .stroke(duplicateError ? AppTheme.Colors.danger : Color.clear, lineWidth: 1)
                    )
                    .onChange(of: newSectionTitle) { _, _ in duplicateError = false }

                if duplicateError {
                    Text("Bu grup zaten mevcut. Lütfen yukarıdaki listeden seçin.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.danger)
                }

                Spacer()
            }
            .padding(AppTheme.Spacing.xl)
            .navigationTitle("Gruba Ata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur") { confirmNewSection() }
                        .disabled(newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func confirmNewSection() {
        let trimmed = newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let isDuplicate = existingSectionTitles.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        if isDuplicate {
            duplicateError = true
        } else {
            onConfirm(trimmed)
            dismiss()
        }
    }
}
