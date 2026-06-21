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

    var body: some View {
        Group {
            if eventVM.isBootstrapping {
                bootstrappingContent
            } else if filteredEvents.isEmpty {
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
        .onChange(of: eventVM.uiEvent) { _, newValue in
            if let message = newValue.toastMessage { toast = message }
        }
        .toast($toast)
    }

    // MARK: - Content

    /// List, ekranın birincil kaydırma kaynağı olmalıdır (`VStack` içine gömülmemeli).
    /// Arama alanı `safeAreaInset` ile sabitlenir; büyük başlık + kaydırma birlikte çalışır.
    private var eventListContent: some View {
        List {
            ForEach(filteredEvents) { event in
                row(for: event)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            listTopInset
        }
        .refreshable { await eventVM.refreshEvents() }
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
                    onDelete: { showDeleteConfirm = true },
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
                    : "Aramanızla eşleşen etkinlik bulunamadı."
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
        SearchField(text: $searchText, placeholder: "Etkinlik ara…")
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
                    onTap: { navigationPath?.push(.eventDetail(event)) },
                    onLongPress: {
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

#Preview {
    NavigationStack {
        EventListView()
            .environment(AppDependencies.makeEventViewModel())
            .environment(AppDependencies.authViewModel)
    }
}
