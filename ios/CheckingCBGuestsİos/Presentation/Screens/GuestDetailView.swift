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
    @State private var photoItem: PhotosPickerItem?
    @State private var toast: ToastMessage?

    private var isPast: Bool { event.isExpired || event.status == .past }

    /// Listedeki güncel hâli (yoksa parametreyle gelen anlık görüntü).
    private var current: Guest {
        eventVM.mergedGuests.first { $0.id == guest.id } ?? guest
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
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Sil", systemImage: "trash")
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
        .onChange(of: photoItem) { _, newValue in
            Task { await updatePhoto(newValue) }
        }
        .onChange(of: eventVM.uiEvent) { _, newValue in
            if let message = newValue.toastMessage { toast = message }
        }
        .toast($toast)
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
            if current.status != .pendingApproval {
                Button {
                    Task { await eventVM.updateGuestStatus(guestId: current.id, eventId: event.id, currentEvent: event) }
                } label: {
                    Label(toggleLabel, systemImage: "arrow.left.arrow.right.circle")
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

    private var toggleLabel: String {
        switch current.status {
        case .pending: return "Giriş Yaptır"
        case .checkedIn: return "Çıkış Yaptır"
        case .exited: return "Durumu Sıfırla"
        case .pendingApproval: return "Onay Bekliyor"
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

private struct GuestTimesEditor: View {
    let guest: Guest
    let event: Event

    @Environment(EventViewModel.self) private var eventVM
    @Environment(\.dismiss) private var dismiss

    @State private var hasEntry: Bool
    @State private var hasExit: Bool
    @State private var entryTime: Date
    @State private var exitTime: Date

    init(guest: Guest, event: Event) {
        self.guest = guest
        self.event = event
        _hasEntry = State(initialValue: guest.entryTime != nil)
        _hasExit = State(initialValue: guest.exitTime != nil)
        _entryTime = State(initialValue: Self.parse(guest.entryTime) ?? Date())
        _exitTime = State(initialValue: Self.parse(guest.exitTime) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Giriş") {
                    Toggle("Giriş saati", isOn: $hasEntry)
                    if hasEntry {
                        DatePicker("Saat", selection: $entryTime, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Çıkış") {
                    Toggle("Çıkış saati", isOn: $hasExit)
                    if hasExit {
                        DatePicker("Saat", selection: $exitTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle("Saat Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        let entry = hasEntry ? Self.format(entryTime) : nil
                        let exit = hasExit ? Self.format(exitTime) : nil
                        Task {
                            await eventVM.updateGuestTimes(
                                guestId: guest.id,
                                eventId: event.id,
                                entryTime: entry,
                                exitTime: exit
                            )
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        GuestDetailView(guest: .previewCheckedIn, event: .previewActive)
            .environment(AppDependencies.makeEventViewModel())
    }
}
