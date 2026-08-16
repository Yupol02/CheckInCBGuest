import SwiftUI

/// Etkinlik içi kırmızı liste onay paneli (Android `RedListGuestsListScreen`).
@MainActor
struct RedListGuestsListView: View {

    let event: Event

    @Environment(EventViewModel.self) private var eventVM

    @State private var pendingGuests: [Guest] = []
    @State private var pinPromptGuestId: String?
    @State private var pendingStatusChange: Guest?
    @State private var rejectCandidate: Guest?
    @State private var toast: ToastMessage?

    private var redListGuests: [Guest] {
        eventVM.mergedGuests.filter {
            $0.eventId == event.id
                && eventVM.redListGuestIds.contains($0.id)
                && $0.status != .pendingApproval
        }
    }

    var body: some View {
        List {
            if !pendingGuests.isEmpty {
                Section("Onay Bekleyen Şüpheliler") {
                    ForEach(pendingGuests) { guest in
                        pendingRow(guest)
                    }
                }
            }

            Section("Kırmızı Liste Misafirleri") {
                if redListGuests.isEmpty {
                    Text("Kayıt yok")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(redListGuests) { guest in
                        NavigationLink(value: AppRoute.redListGuestDetail(guest: guest, event: event)) {
                            GuestCard(
                                guest: guest,
                                isRedList: true,
                                onToggleStatus: toggleAction(for: guest)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Kırmızı Liste Paneli")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: pinPromptBinding) { wrapper in
            PinPromptSheet { pin in
                _ = eventVM.grantRedListPermission(pin: pin)
                Task { await eventVM.updateGuestStatus(guestId: wrapper.id, eventId: event.id, currentEvent: event) }
            }
        }
        .confirmationDialog(
            pendingStatusChange.map(GuestStatusChangePrompt.title) ?? "",
            isPresented: statusChangeBinding,
            titleVisibility: .visible,
            presenting: pendingStatusChange
        ) { guest in
            Button(
                GuestStatusChangePrompt.confirmLabel(for: guest),
                role: GuestStatusChangePrompt.isDestructive(guest) ? .destructive : nil
            ) {
                pendingStatusChange = nil
                Task { await eventVM.updateGuestStatus(guestId: guest.id, eventId: event.id, currentEvent: event) }
            }
            Button("Vazgeç", role: .cancel) { pendingStatusChange = nil }
        } message: { guest in
            if let message = GuestStatusChangePrompt.message(for: guest) {
                Text(message)
            }
        }
        .confirmationDialog(
            "Misafir reddedilsin mi?",
            isPresented: rejectDialogBinding,
            titleVisibility: .visible,
            presenting: rejectCandidate
        ) { guest in
            Button("Reddet", role: .destructive) {
                rejectCandidate = nil
                Task { await eventVM.rejectRedListGuest(guestId: guest.id, currentEvent: event) }
            }
            Button("Vazgeç", role: .cancel) { rejectCandidate = nil }
        } message: { guest in
            Text("\(guest.name) kalıcı olarak silinecek. Bu işlem geri alınamaz.")
        }
        .task(id: event.id) {
            for await guests in eventVM.pendingRedListGuestsStream(for: event.id) {
                pendingGuests = guests
            }
        }
        .onChange(of: eventVM.uiEventNonce) { _, _ in
            switch eventVM.uiEvent {
            case .showRedListPermissionRequired(let id):
                pinPromptGuestId = id
            case let uiEvent:
                if let message = uiEvent.toastMessage { toast = message }
            }
        }
        .toast($toast)
    }

    /// `.exited` durumundan sıfırlama yalnızca yöneticiye açıktır; yetkisizde rozet tıklanamaz.
    private func toggleAction(for guest: Guest) -> (() -> Void)? {
        guard guest.status != .exited || eventVM.isAdminDevice else { return nil }
        return { pendingStatusChange = guest }
    }

    private func pendingRow(_ guest: Guest) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(guest.name).font(.subheadline.weight(.semibold))
                    if !guest.title.isEmpty {
                        Text(guest.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(AppTheme.Colors.danger)
            }
            HStack(spacing: AppTheme.Spacing.md) {
                Button {
                    Task { await eventVM.approveGuest(guest, currentEvent: event) }
                } label: {
                    Label("Onayla", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Colors.success)

                // "Reddet" misafiri kalıcı olarak siler: yalnızca yönetici cihazlarda görünür.
                if eventVM.isAdminDevice {
                    Button(role: .destructive) {
                        rejectCandidate = guest
                    } label: {
                        Label("Reddet", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private var pinPromptBinding: Binding<IdentifiableString?> {
        Binding(
            get: { pinPromptGuestId.map(IdentifiableString.init) },
            set: { pinPromptGuestId = $0?.id }
        )
    }

    private var statusChangeBinding: Binding<Bool> {
        Binding(
            get: { pendingStatusChange != nil },
            set: { if !$0 { pendingStatusChange = nil } }
        )
    }

    private var rejectDialogBinding: Binding<Bool> {
        Binding(
            get: { rejectCandidate != nil },
            set: { if !$0 { rejectCandidate = nil } }
        )
    }
}

#Preview {
    NavigationStack {
        RedListGuestsListView(event: .previewActive)
            .environment(AppDependencies.makeEventViewModel())
    }
}
