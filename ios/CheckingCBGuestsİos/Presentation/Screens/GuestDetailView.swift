import PhotosUI
import SwiftUI

/// Misafir detay ekranı (Android `GuestDetailScreen`).
@MainActor
struct GuestDetailView: View {

    let guest: Guest
    let event: Event

    @Environment(EventViewModel.self) private var eventVM
    @Environment(\.dismiss) private var dismiss

    @State private var showTimesEditor = false
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var showRemoveSectionConfirm = false
    @State private var showStatusConfirm = false
    @State private var photoItem: PhotosPickerItem?
    @State private var toast: ToastMessage?
    /// Son görülen canlı misafir değeri.
    @State private var lastKnownGuest: Guest?

    private var isPast: Bool { event.isExpired || event.status == .past }

    /// Listedeki güncel hâli.
    ///
    /// Yedek olarak `AppRoute` içine gömülü ve **kalıcı olarak eskiyen** `guest` yerine son görülen
    /// canlı değer kullanılır; aksi hâlde liste bir an misafiri içermediğinde ekran eski saate dönüyordu.
    private var current: Guest {
        eventVM.guest(withId: guest.id) ?? lastKnownGuest ?? guest
    }

    /// `.exited` durumundan çıkış, giriş/çıkış kaydını silen sıfırlamadır: yalnızca yönetici.
    private var canToggleStatus: Bool {
        current.status != .exited || eventVM.isAdminDevice
    }

    private var isRedList: Bool {
        current.isRedListPending || eventVM.redListGuestIds.contains(current.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                photoHeader
                infoCard
                if !isPast { actionButtons }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.groupedBackground)
        .navigationTitle("Misafir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isPast {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Düzenle", systemImage: "pencil")
                        }
                        // Silme yalnızca yönetici cihazlarda görünür.
                        if eventVM.isAdminDevice {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showTimesEditor) {
            GuestTimesEditor(guest: current, event: event)
        }
        .sheet(isPresented: $showEditSheet) {
            EditGuestView(guest: current, event: event)
        }
        .confirmationDialog("Misafir silinsin mi?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                Task {
                    await eventVM.deleteGuest(guestId: current.id, eventId: event.id, currentEvent: event)
                    dismiss()
                }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("Heyetten çıkarılsın mı?", isPresented: $showRemoveSectionConfirm, titleVisibility: .visible) {
            Button("Çıkar", role: .destructive) {
                Task { await eventVM.removeGuestFromDelegation(guestId: current.id, currentEvent: event) }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog(
            GuestStatusChangePrompt.title(for: current),
            isPresented: $showStatusConfirm,
            titleVisibility: .visible
        ) {
            Button(
                GuestStatusChangePrompt.confirmLabel(for: current),
                role: GuestStatusChangePrompt.isDestructive(current) ? .destructive : nil
            ) {
                Task { await eventVM.updateGuestStatus(guestId: current.id, eventId: event.id, currentEvent: event) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            if let message = GuestStatusChangePrompt.message(for: current) {
                Text(message)
            }
        }
        .onAppear { syncLastKnownGuest() }
        .onChange(of: photoItem) { _, newValue in
            Task { await updatePhoto(newValue) }
        }
        // Tüm misafir dizisini değil yalnızca bu misafiri izler.
        .onChange(of: eventVM.guest(withId: guest.id)) { _, newValue in
            if let newValue { lastKnownGuest = newValue }
        }
        .onChange(of: eventVM.uiEventNonce) { _, _ in
            if let message = eventVM.uiEvent.toastMessage { toast = message }
        }
        .toast($toast)
    }

    private func syncLastKnownGuest() {
        if let latest = eventVM.guest(withId: guest.id) {
            lastKnownGuest = latest
        }
    }

    // MARK: - Sections

    private var photoHeader: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            avatar
            if !isPast {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Fotoğrafı Değiştir", systemImage: "camera")
                        .font(.caption)
                }
            }
            Text(current.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            if !current.title.isEmpty {
                Text(current.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            StatusBadge(status: current.status)
            if isRedList {
                Label("Kırmızı Liste", systemImage: "flag.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.redList)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoUri = current.photoUri, let url = URL(string: photoUri), photoUri.hasPrefix("http") {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(Circle())
        } else {
            placeholder.frame(width: 110, height: 110)
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(AppTheme.Colors.accentSoft)
            Image(systemName: "person.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Colors.accent)
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow("Geliş", current.arrivalMethod.displayName, icon: current.arrivalMethod.iconName)
            if let plate = current.plate, !plate.isEmpty {
                Divider()
                infoRow("Plaka", plate, icon: "number")
            }
            if let model = current.model, !model.isEmpty {
                Divider()
                infoRow("Araç", model, icon: "car")
            }
            if let section = current.sectionTitle, !section.isEmpty {
                Divider()
                infoRow("Heyet", section, icon: "person.3")
            }
            if let expectedTime = current.expectedTime, !expectedTime.isEmpty {
                Divider()
                infoRow("Beklenen Toplantı", expectedTime, icon: "clock")
            }
            Divider()
            infoRow("Güvenlik", current.securityCheck ? "Arama Gerekli" : "VIP / Hızlı Geçiş", icon: "shield")
            if let category = current.participationCategory {
                Divider()
                infoRow("Kategori", category.displayName, icon: "tag")
            }
            Divider()
            infoRow("Giriş", Validators.formatTimeForDisplay(current.entryTime) ?? "—", icon: "arrow.right.to.line")
            Divider()
            infoRow("Çıkış", Validators.formatTimeForDisplay(current.exitTime) ?? "—", icon: "arrow.left.to.line")
            if let note = current.note, !note.isEmpty {
                Divider()
                infoRow("Not", note, icon: "note.text")
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    private func infoRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var actionButtons: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            if current.status != .pendingApproval, canToggleStatus {
                Button {
                    showStatusConfirm = true
                } label: {
                    Label(GuestStatusChangePrompt.confirmLabel(for: current), systemImage: "arrow.left.arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Colors.accent)
            }

            Button {
                showTimesEditor = true
            } label: {
                Label("Saat Düzenle", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let section = current.sectionTitle, !section.isEmpty {
                Button(role: .destructive) {
                    showRemoveSectionConfirm = true
                } label: {
                    Label("Heyetten Çıkar", systemImage: "person.3.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if isRedList {
                Button(role: .destructive) {
                    Task { await eventVM.removeFromRedList(guestId: current.id) }
                } label: {
                    Label("Kırmızı Listeden Çıkar", systemImage: "flag.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func updatePhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("guest_\(UUID().uuidString).jpg")
        guard (try? data.write(to: tempURL)) != nil else { return }
        await eventVM.updateGuestPhoto(guestId: current.id, localURL: tempURL)
    }
}

// MARK: - Saat düzenleyici

@MainActor
private struct GuestTimesEditor: View {
    let guest: Guest
    let event: Event

    @Environment(EventViewModel.self) private var eventVM
    @Environment(\.dismiss) private var dismiss

    @State private var hasEntry: Bool
    @State private var hasExit: Bool
    @State private var entryTime: Date
    @State private var exitTime: Date
    @State private var isSaving = false
    @State private var toast: ToastMessage?

    init(guest: Guest, event: Event) {
        self.guest = guest
        self.event = event
        _hasEntry = State(initialValue: guest.entryTime != nil)
        _hasExit = State(initialValue: guest.exitTime != nil)
        _entryTime = State(initialValue: Validators.parseISO8601(guest.entryTime ?? "") ?? Date())
        _exitTime = State(initialValue: Validators.parseISO8601(guest.exitTime ?? "") ?? Date())
    }

    /// Kayıtlı bir saati tamamen silmek kısmi sıfırlamadır; yalnızca yönetici yapabilir.
    private var canClearEntry: Bool { eventVM.isAdminDevice || guest.entryTime == nil }
    private var canClearExit: Bool { eventVM.isAdminDevice || guest.exitTime == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Giriş") {
                    Toggle("Giriş saati", isOn: $hasEntry)
                        .disabled(!canClearEntry)
                    if hasEntry {
                        DatePicker("Saat", selection: $entryTime, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Çıkış") {
                    Toggle("Çıkış saati", isOn: $hasExit)
                        .disabled(!canClearExit)
                    if hasExit {
                        DatePicker("Saat", selection: $exitTime, displayedComponents: .hourAndMinute)
                    }
                }
                if !eventVM.isAdminDevice {
                    Section {
                        Text("Saatleri değiştirebilirsiniz; kayıtlı bir saati silme yetkisi yalnızca yöneticidedir.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Saat Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(isSaving)
                }
            }
            // Sayfa hata hâlinde açık kaldığı için bildirimi kendi içinde göstermeli:
            // `sheet` sunucu görünümün `.toast` katmanını devralmaz.
            .onChange(of: eventVM.uiEventNonce) { _, _ in
                if let message = eventVM.uiEvent.toastMessage { toast = message }
            }
            .toast($toast)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await eventVM.updateGuestTimes(
                guestId: guest.id,
                eventId: event.id,
                entryDate: hasEntry ? entryTime : nil,
                exitDate: hasExit ? exitTime : nil,
                currentEvent: event
            )
            isSaving = false
            // Başarısızsa sayfa açık kalır ki kullanıcı hatayı görüp tekrar deneyebilsin.
            if saved { dismiss() }
        }
    }
}

#Preview {
    NavigationStack {
        GuestDetailView(guest: .previewCheckedIn, event: .previewActive)
            .environment(AppDependencies.makeEventViewModel())
    }
}
