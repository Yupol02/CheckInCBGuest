import SwiftUI

/// Etkinlik listesi ana ekranı (Android `EventListScreen`).
@MainActor
struct EventListView: View {

    @Environment(EventViewModel.self) private var eventVM
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.appNavigationPath) private var navigationPath

    @State private var searchText = ""
    @State private var showAddEvent = false
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var toast: ToastMessage?

    private var filteredEvents: [Event] {
        let events = eventVM.eventsWithCounts.filter { !$0.isDeleted }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = query.isEmpty ? events : events.filter {
            $0.title.lowercased().contains(query)
                || $0.location.lowercased().contains(query)
                || $0.date.lowercased().contains(query)
        }
        return base.sorted { statusOrder($0.computedStatus) < statusOrder($1.computedStatus) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Tüm etkinliklerdeki eşleşen kişiler; aynı kişi N etkinlikteyse N satır çıkar.
    private var guestResults: [GuestSearchResult] {
        isSearching ? eventVM.searchGuestsAcrossEvents(query: searchText) : []
    }

    /// Silme yalnızca yönetici cihazlarda; yetkisizde seçim moduna hiç girilmez.
    /// (Etkinlik seçim modunun tek işlevi silmektir.)
    private var eventDeleteAction: (() -> Void)? {
        guard eventVM.isAdminDevice else { return nil }
        return { showDeleteConfirm = true }
    }

    var body: some View {
        Group {
            if eventVM.isBootstrapping {
                bootstrappingContent
            } else if filteredEvents.isEmpty && guestResults.isEmpty {
                emptyContent
            } else {
                eventListContent
            }
        }
        .background(AppTheme.Colors.groupedBackground)
        .navigationTitle("Etkinlikler")
        .navigationBarTitleDisplayMode(eventVM.isEventSelectionMode ? .inline : .large)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddEvent) {
            AddEventView()
        }
        .confirmationDialog("Çıkış yapmak istiyor musunuz?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Çıkış Yap", role: .destructive) {
                Task { await authVM.logout() }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("Etkinlik Silme", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                Task { await eventVM.deleteSelectedEvents() }
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("\(eventVM.selectedEventIds.count) etkinliği silmek istediğinize emin misiniz?\n\nBu işlem geri alınamaz ve tüm misafirler de silinecektir.")
        }
        .onChange(of: eventVM.uiEventNonce) { _, _ in
            if let message = eventVM.uiEvent.toastMessage { toast = message }
        }
        .toast($toast)
    }

    // MARK: - Content

    /// List, ekranın birincil kaydırma kaynağı olmalıdır (`VStack` içine gömülmemeli).
    /// Arama alanı `safeAreaInset` ile sabitlenir; büyük başlık + kaydırma birlikte çalışır.
    private var eventListContent: some View {
        List {
            if isSearching {
                // Arama sırasında iki bölüm: etkinlik eşleşmeleri + tüm etkinliklerdeki kişiler.
                if !filteredEvents.isEmpty {
                    Section("Etkinlikler") { eventRows }
                }
                if !guestResults.isEmpty {
                    Section("Kişiler") { guestResultRows }
                }
            } else {
                // Arama yokken mevcut düzen birebir korunur (bölüm başlığı yok).
                eventRows
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            listTopInset
        }
        .refreshable { await eventVM.refreshEvents() }
    }

    @ViewBuilder
    private var eventRows: some View {
        ForEach(filteredEvents) { event in
            row(for: event)
                .modifier(PlainCardRow())
        }
    }

    @ViewBuilder
    private var guestResultRows: some View {
        ForEach(guestResults) { result in
            GuestSearchResultCard(guest: result.guest, eventTitle: result.event.title)
                .modifier(PlainCardRow())
                .rowTapAndLongPress {
                    navigationPath?.push(
                        .eventDetail(event: result.event, highlightGuestId: result.guest.id)
                    )
                }
        }
    }

    private var listTopInset: some View {
        VStack(spacing: 0) {
            if eventVM.isEventSelectionMode {
                SelectionToolbar(
                    selectedCount: eventVM.selectedEventIds.count,
                    totalCount: filteredEvents.count,
                    onSelectAll: {
                        eventVM.selectAllEvents(ids: filteredEvents.map(\.id))
                    },
                    onClearSelection: { eventVM.clearEventSelection() },
                    onDelete: eventDeleteAction,
                    onDone: { eventVM.toggleEventSelectionMode() },
                    canDelete: !eventVM.selectedEventIds.isEmpty
                )
            }
            if !eventVM.isEventSelectionMode {
                searchBar
            }
        }
    }

    private var emptyContent: some View {
        ScrollView {
            EmptyStateView(
                icon: "calendar.badge.plus",
                title: "Etkinlik yok",
                message: searchText.isEmpty
                    ? "Sağ üstten yeni etkinlik ekleyin."
                    : "Aramanızla eşleşen etkinlik veya kişi bulunamadı."
            )
            .padding(.top, AppTheme.Spacing.xxl)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            searchBar
        }
        .refreshable { await eventVM.refreshEvents() }
    }

    private var bootstrappingContent: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            searchBar
            Spacer()
            ProgressView()
            Text("Etkinlikler yükleniyor…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var searchBar: some View {
        SearchField(text: $searchText, placeholder: "Etkinlik veya kişi ara…")
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.groupedBackground)
    }

    @ViewBuilder
    private func row(for event: Event) -> some View {
        if eventVM.isEventSelectionMode {
            EventCard(
                event: event,
                isSelectionMode: true,
                isSelected: eventVM.selectedEventIds.contains(event.id)
            )
            .rowTapAndLongPress {
                eventVM.toggleEventSelection(id: event.id)
            }
        } else {
            EventCard(event: event)
                .rowTapAndLongPress(
                    onTap: { navigationPath?.push(.eventDetail(event: event, highlightGuestId: nil)) },
                    onLongPress: eventDeleteAction == nil ? nil : {
                        eventVM.toggleEventSelectionMode()
                        eventVM.toggleEventSelection(id: event.id)
                    }
                )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !eventVM.isEventSelectionMode {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if eventVM.isAdminDevice {
                        Button {
                            navigationPath?.push(.redListManagement)
                        } label: {
                            Label("Kırmızı Liste", systemImage: "flag.fill")
                        }
                    }
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddEvent = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func statusOrder(_ status: EventStatus) -> Int {
        switch status {
        case .active: return 0
        case .upcoming: return 1
        case .past: return 2
        }
    }
}

/// Etkinlik ve kişi satırlarının ortak `List` sunumu (ayraçsız, şeffaf zemin, kart aralığı).
private struct PlainCardRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(
                    top: 6,
                    leading: AppTheme.Spacing.lg,
                    bottom: 6,
                    trailing: AppTheme.Spacing.lg
                )
            )
    }
}

#Preview {
    NavigationStack {
        EventListView()
            .environment(AppDependencies.makeEventViewModel())
            .environment(AppDependencies.authViewModel)
    }
}
