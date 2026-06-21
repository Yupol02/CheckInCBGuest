import SwiftUI

/// Kırmızı liste misafir detayı — salt okunur (Android `RedListGuestDetailScreen`).
@MainActor
struct RedListGuestDetailView: View {

    let guest: Guest
    let event: Event

    @Environment(EventViewModel.self) private var eventVM

    private var current: Guest {
        eventVM.mergedGuests.first { $0.id == guest.id } ?? guest
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                warningBanner
                infoCard
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.groupedBackground)
        .navigationTitle("Şüpheli Misafir")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var warningBanner: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.Colors.redList)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kırmızı Liste Uyarısı")
                    .font(.subheadline.weight(.bold))
                Text("Bu misafir özel izin gerektirir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.redList.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            row("Ad Soyad", current.name, icon: "person.fill")
            Divider()
            row("Unvan", current.title.isEmpty ? "—" : current.title, icon: "briefcase")
            Divider()
            row("Durum", current.status.displayName, icon: "info.circle")
            Divider()
            row("Geliş", current.arrivalMethod.displayName, icon: current.arrivalMethod.iconName)
            if let plate = current.plate, !plate.isEmpty {
                Divider()
                row("Plaka", plate, icon: "number")
            }
            if let note = current.note, !note.isEmpty {
                Divider()
                row("Not", note, icon: "note.text")
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    private func row(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.Colors.redList)
                .frame(width: 24)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}

#Preview {
    NavigationStack {
        RedListGuestDetailView(guest: .previewPendingApproval, event: .previewActive)
            .environment(AppDependencies.makeEventViewModel())
    }
}
