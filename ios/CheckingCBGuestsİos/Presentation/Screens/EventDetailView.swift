import SwiftUI

/// Etkinlik detayı ve misafir yönetimi (Android `EventDetailScreen`).
@MainActor
struct EventDetailView: View {

    let event: Event

    @Environment(EventViewModel.self) private var eventVM
    @Environment(\.appNavigationPath) private var navigationPath

    @State private var filter: GuestFilter = .all
    @State private var showAddGuest = false
    @State private var showAssignSection = false
    @State private var showDeleteConfirm = false
    @State private var pinPromptGuestId: String?
    @State private var approvalGuest: Guest?
    @State private var pendingCount = 0
    @State private var toast: ToastMessage?

    private var isPast: Bool { event.isExpired || event.status == .past }

    private var eventGuests: [Guest] {
        eventVM.mergedGuests.filter {
            $0.eventId == event.id && !$0.isRedListPending && $0.status != .pendingApproval
        }
    }

    private var visibleGuests: [Guest] {
        eventVM.filteredGuests(for: event.id, currentEvent: event)
    }

    private var groupedListItems: [GuestListUiItem] {
        GuestListGrouping.build(from: visibleGuests)
    }

    private var existingSectionTitles: [String] {
        Array(Set(
            visibleGuests
                .compactMap { $0.sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )).sorted()
    }

    var body: some View {
        @Bindable var eventVM = eventVM

        // Android: sabit başlık + LazyColumn(weight=1). iOS'ta List VStack içinde bozulduğu
        // için üst kısım sabit, misafirler ScrollView + LazyVStack ile kaydırılır.
        VStack(spacing: 0) {
            if eventVM.isSelectionMode {
                SelectionToolbar(
                    selectedCount: eventVM.selectedGuestIds.count,
                    totalCount: visibleGuests.count,
                    onSelectAll: {
                        eventVM.selectAllGuests(ids: visibleGuests.map(\.id))
                    },
                    onClearSelection: { eventVM.clearSelection() },
                    onDelete: { showDeleteConfirm = true },
                    onDone: { eventVM.toggleSelectionMode() },
                    canDelete: !isPast && !eventVM.selectedGuestIds.isEmpty,
                    onAddGroup: isPast ? nil : { showAssignSection = true }
                )
            }
            headerCard
            SearchField(text: $eventVM.searchQuery, placeholder: "Misafir ara…")
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.sm)
            filterPicker
            guestList
        }
        .background(AppTheme.Colors.groupedBackground)
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddGuest) {
            AddGuestView(event: event)
        }
        .sheet(item: pinPromptBinding) { wrapper in
            PinPromptSheet { pin in
                _ = eventVM.grantRedListPermission(pin: pin)
                Task { await eventVM.updateGuestStatus(guestId: wrapper.id, eventId: event.id, currentEvent: event) }
            }
        }
        .sheet(isPresented: $showAssignSection) {
            SectionTitleSheet(existingSectionTitles: existingSectionTitles) { title in
                Task { await eventVM.assignSectionToSelectedGuests(sectionTitle: title, currentEvent: event) }
            }
        }
        .confirmationDialog("Misafir Silme", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                Task { await eventVM.deleteSelectedGuests(currentEvent: event) }
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("\(eventVM.selectedGuestIds.count) misafiri silmek istediğinize emin misiniz?\n\nBu işlem geri alınamaz.")
        }
        .confirmationDialog(
            "Bu misafir kırmızı listeyle eşleşti",
            isPresented: approvalDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Amir Onayına Gönder") {
                if let guest = approvalGuest {
                    Task { await eventVM.addGuestAsPendingApproval(guest, currentEvent: event) }
                }
                approvalGuest = nil
            }
            Button("İptal", role: .cancel) { approvalGuest = nil }
        } message: {
            Text("Misafir onaya gönderilsin mi?")
        }
        .task(id: event.id) {
            for await guests in eventVM.pendingRedListGuestsStream(for: event.id) {
                pendingCount = guests.count
            }
        }
        .onChange(of: eventVM.uiEvent) { _, newValue in
            handleUiEvent(newValue)
        }
        .toast($toast)
    }

    // MARK: - Sections

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Label(event.date, systemImage: "calendar")
                Spacer()
                Label(event.startTime, systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Label(event.location, systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: AppTheme.Spacing.lg) {
                Label("\(eventGuests.count) misafir", systemImage: "person.2.fill")
                Label("\(eventGuests.filter { $0.status == .checkedIn }.count) içeride", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.Colors.success)
            }
            .font(.caption)

            if eventVM.isAdminDevice, pendingCount > 0 {
                NavigationLink(value: AppRoute.redListGuestsList(event: event)) {
                    HStack {
                        Image(systemName: "exclamationmark.shield.fill")
                        Text("\(pendingCount) onay bekleyen şüpheli")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.danger)
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.Colors.danger.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var filterPicker: some View {
        Picker("Filtre", selection: $filter) {
            ForEach(GuestFilter.allCases, id: \.self) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.sm)
        .onChange(of: filter) { _, newValue in
            eventVM.onFilterTabChanged(newValue.status)
        }
    }

    @ViewBuilder
    private var guestList: some View {
        if visibleGuests.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "Misafir yok",
                    message: isPast ? nil : "Sağ üstten misafir ekleyin veya Excel'den içe aktarın."
                )
                .padding(.top, AppTheme.Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshable { await eventVM.refreshEvents() }
        } else {
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(groupedListItems) { item in
                        groupedRow(item)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshable { await eventVM.refreshEvents() }
        }
    }

    @ViewBuilder
    private func groupedRow(_ item: GuestListUiItem) -> some View {
        switch item {
        case .sectionHeader(let title, let count):
            DelegationSectionHeader(title: title, guestCount: count)
                .padding(.top, AppTheme.Spacing.sm)
        case .timeHeader(let time, _):
            MeetingTimeHeader(time: time)
                .padding(.leading, AppTheme.Spacing.sm)
        case .guest(let guest, let context):
            guestRow(guest, context: context)
                .padding(.leading, context.isInDelegationSection ? AppTheme.Spacing.md : 0)
                .background {
                    if context.isInDelegationSection {
                        RoundedRectangle(
                            cornerRadius: context.isLastInSection ? AppTheme.Radius.md : 0,
                            style: .continuous
                        )
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .padding(.horizontal, AppTheme.Spacing.sm)
                    }
                }
            if context.isLastInSection && context.isInDelegationSection {
                Divider()
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private func guestRow(_ guest: Guest, context: GuestRowContext? = nil) -> some View {
        let rowContext = context ?? GuestRowContext(
            orderNumber: 0,
            isLastInSection: false,
            sectionKey: "",
            isInDelegationSection: false
        )

        if eventVM.isSelectionMode {
            GuestCard(
                guest: guest,
                isRedList: eventVM.redListGuestIds.contains(guest.id),
                isSelectionMode: true,
                isSelected: eventVM.selectedGuestIds.contains(guest.id),
                isInDelegationSection: rowContext.isInDelegationSection
            )
            .rowTapAndLongPress {
                eventVM.toggleGuestSelection(id: guest.id)
            }
        } else {
            GuestCard(
                guest: guest,
                isRedList: eventVM.redListGuestIds.contains(guest.id),
                orderNumber: rowContext.orderNumber,
                isInDelegationSection: rowContext.isInDelegationSection,
                onToggleStatus: isPast ? nil : {
                    Task { await eventVM.updateGuestStatus(guestId: guest.id, eventId: event.id, currentEvent: event) }
                }
            )
            .rowTapAndLongPress(
                onTap: { navigationPath?.push(.guestDetail(guest: guest, event: event)) },
                onLongPress: isPast ? nil : {
                    eventVM.toggleSelectionMode()
                    eventVM.toggleGuestSelection(id: guest.id)
                }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !eventVM.isSelectionMode && !isPast {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddGuest = true
                    } label: {
                        Label("Misafir Ekle", systemImage: "person.badge.plus")
                    }
                    Button {
                        navigationPath?.push(.excelImport(event: event))
                    } label: {
                        Label("Excel'den İçe Aktar", systemImage: "tablecells")
                    }
                    if eventVM.isAdminDevice {
                        Button {
                            navigationPath?.push(.redListGuestsList(event: event))
                        } label: {
                            Label("Kırmızı Liste Paneli", systemImage: "flag.fill")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: - Bindings & events

    private var pinPromptBinding: Binding<IdentifiableString?> {
        Binding(
            get: { pinPromptGuestId.map(IdentifiableString.init) },
            set: { pinPromptGuestId = $0?.id }
        )
    }

    private var approvalDialogBinding: Binding<Bool> {
        Binding(
            get: { approvalGuest != nil },
            set: { if !$0 { approvalGuest = nil } }
        )
    }

    private func handleUiEvent(_ event: UiEvent) {
        switch event {
        case .showRedListPermissionRequired(let guestId):
            pinPromptGuestId = guestId
        case .showRedListAddPermissionRequired(let guest):
            approvalGuest = guest
        default:
            if let message = event.toastMessage { toast = message }
        }
    }
}

// MARK: - Filter

enum GuestFilter: CaseIterable, Hashable {
    case all, pending, inside, exited

    var label: String {
        switch self {
        case .all: return "Tümü"
        case .pending: return "Bekleyen"
        case .inside: return "İçeride"
        case .exited: return "Çıkan"
        }
    }

    var status: GuestStatus? {
        switch self {
        case .all: return nil
        case .pending: return .pending
        case .inside: return .checkedIn
        case .exited: return .exited
        }
    }
}

struct IdentifiableString: Identifiable {
    let id: String
}

#Preview {
    NavigationStack {
        EventDetailView(event: .previewActive)
            .environment(AppDependencies.makeEventViewModel())
    }
}
