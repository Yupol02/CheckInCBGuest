import SwiftUI

/// Etkinlik içi kırmızı liste onay paneli (Android `RedListGuestsListScreen`).
@MainActor
struct RedListGuestsListView: View {

    let event: Event

    @Environment(EventViewModel.self) private var eventVM

    @State private var pendingGuests: [Guest] = []
    @State private var pinPromptGuestId: String?
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
                                onToggleStatus: {
                                    Task { await eventVM.updateGuestStatus(guestId: guest.id, eventId: event.id, currentEvent: event) }
                                }
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
        .task(id: event.id) {
            for await guests in eventVM.pendingRedListGuestsStream(for: event.id) {
                pendingGuests = guests
            }
        }
        .onChange(of: eventVM.uiEvent) { _, newValue in
            switch newValue {
            case .showRedListPermissionRequired(let id):
                pinPromptGuestId = id
            default:
                if let message = newValue.toastMessage { toast = message }
            }
        }
        .toast($toast)
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

                Button(role: .destructive) {
                    Task { await eventVM.rejectRedListGuest(guestId: guest.id, currentEvent: event) }
                } label: {
                    Label("Reddet", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
}

#Preview {
    NavigationStack {
        RedListGuestsListView(event: .previewActive)
            .environment(AppDependencies.makeEventViewModel())
    }
}
