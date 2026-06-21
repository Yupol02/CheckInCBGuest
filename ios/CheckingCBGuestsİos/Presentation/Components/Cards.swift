import SwiftUI

// MARK: - Event card

struct EventCard: View {
    let event: Event
    var isSelectionMode: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: AppTheme.Spacing.sm)
                    statusBadge
                }

                Label(event.date, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(event.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: AppTheme.Spacing.lg) {
                    Label(event.startTime, systemImage: "clock")
                    Label("\(event.participatedCount)/\(event.totalGuestCount)", systemImage: "person.2.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(isSelected ? AppTheme.Colors.accentSoft : AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(isSelected ? AppTheme.Colors.accent.opacity(0.8) : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var statusBadge: some View {
        let status = event.computedStatus
        return Text(status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.14))
            .clipShape(Capsule())
    }
}

// MARK: - Guest card

struct GuestCard: View {
    let guest: Guest
    var isRedList: Bool = false
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var orderNumber: Int?
    var isInDelegationSection: Bool = false
    var onToggleStatus: (() -> Void)?

    private var statusIndicatorColor: Color {
        if isSelected || isRedList { return AppTheme.Colors.danger }
        switch guest.status {
        case .checkedIn: return AppTheme.Colors.success
        case .exited: return AppTheme.Colors.secondaryText
        default:
            return guest.securityCheck ? AppTheme.Colors.danger : AppTheme.Colors.warning
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statusIndicatorColor)
                .frame(width: 4)
                .padding(.vertical, AppTheme.Spacing.sm)

            HStack(spacing: AppTheme.Spacing.md) {
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
                }

                if let orderNumber, orderNumber > 0, !isSelectionMode {
                    Text("\(orderNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                }

                avatar

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text(guest.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if isRedList {
                            Image(systemName: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.redList)
                        }
                        if !guest.securityCheck {
                            securityBadge("VIP", color: AppTheme.Colors.warning)
                        } else if guest.status == .pending {
                            securityBadge("Arama", color: AppTheme.Colors.danger)
                        }
                    }

                    if !guest.title.isEmpty {
                        Text(guest.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        if !isInDelegationSection, let section = guest.sectionTitle, !section.isEmpty {
                            Label(section, systemImage: "person.3")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Label(guest.listArrivalLabel, systemImage: guest.arrivalMethod.iconName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let expectedTime = guest.expectedTime, !expectedTime.isEmpty {
                            Label(expectedTime, systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: AppTheme.Spacing.sm)

                if let onToggleStatus, !isSelectionMode {
                    Button(action: onToggleStatus) {
                        StatusBadge(status: guest.status)
                    }
                    .buttonStyle(.plain)
                } else if isSelectionMode {
                    EmptyView()
                } else {
                    StatusBadge(status: guest.status)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(isSelected ? AppTheme.Colors.accent : Color.clear, lineWidth: 2)
        )
    }

    private func securityBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoUri = guest.photoUri, let url = URL(string: photoUri), photoUri.hasPrefix("http") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderAvatar
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            placeholderAvatar
                .frame(width: 44, height: 44)
        }
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle().fill(AppTheme.Colors.accentSoft)
            Text(initials)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.Colors.accent)
        }
    }

    private var initials: String {
        let parts = guest.name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }
}

#Preview {
    VStack(spacing: 12) {
        EventCard(event: .previewActive)
        GuestCard(guest: .previewCheckedIn)
        GuestCard(guest: .previewPendingApproval, isRedList: true)
    }
    .padding()
    .background(AppTheme.Colors.groupedBackground)
}
