import SwiftUI

/// Kırmızı liste yönetim ekranı (Android `RedListManagementScreen`).
@MainActor
struct RedListManagementView: View {

    @State private var viewModel: RedListViewModel
    @State private var showAdd = false
    @State private var showPin = false

    init() {
        _viewModel = State(initialValue: AppDependencies.makeRedListViewModel())
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            if viewModel.hasPermission {
                SearchField(text: $viewModel.searchQuery, placeholder: "İsim, sebep veya not ara…")
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.sm)
                memberList
            } else {
                lockedState
            }
        }
        .background(AppTheme.Colors.groupedBackground)
        .navigationTitle("Kırmızı Liste")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.hasPermission {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddToRedListSheet { name, reason, notes in
                Task { _ = await viewModel.addMemberToRedList(guestName: name, reason: reason, notes: notes) }
            }
        }
        .sheet(isPresented: $showPin) {
            PinPromptSheet { pin in
                _ = viewModel.grantPermissionWithPin(pin)
                viewModel.loadRedListMembers()
            }
        }
    }

    @ViewBuilder
    private var memberList: some View {
        if viewModel.filteredMembers.isEmpty {
            EmptyStateView(
                icon: "flag.slash",
                title: "Kırmızı liste boş",
                message: "Sağ üstten üye ekleyin."
            )
            Spacer()
        } else {
            List {
                ForEach(viewModel.filteredMembers) { member in
                    RedListMemberCard(member: member)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: AppTheme.Spacing.lg, bottom: 4, trailing: AppTheme.Spacing.lg))
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.removeFromRedListByMemberId(memberId: member.id)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
    }

    private var lockedState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.Colors.accent)
            Text("Bu panel için yetki gerekli")
                .font(.headline)
            Button {
                showPin = true
            } label: {
                Label("PIN ile Giriş", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.Colors.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Member card

private struct RedListMemberCard: View {
    let member: RedListMember

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "flag.fill")
                .foregroundStyle(AppTheme.Colors.redList)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.guestName)
                    .font(.subheadline.weight(.semibold))
                if let notes = member.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(member.reason.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .foregroundStyle(AppTheme.Colors.redList)
                .background(AppTheme.Colors.redList.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        RedListManagementView()
    }
}
