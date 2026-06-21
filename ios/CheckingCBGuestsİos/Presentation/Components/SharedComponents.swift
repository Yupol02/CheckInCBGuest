import SwiftUI
import UIKit

// MARK: - Selection toolbar

/// Android `SelectionToolbar` / `SelectionTopBar` eşleniği.
struct SelectionToolbar: View {
    let selectedCount: Int
    let totalCount: Int
    let onSelectAll: () -> Void 
    let onClearSelection: () -> Void
    let onDelete: () -> Void
    let onDone: () -> Void
    var canDelete: Bool = true
    var onAddGroup: (() -> Void)?

    private let barBackground = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)

    var body: some View {
        HStack {
            Text("\(selectedCount) seçili")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)

            Spacer(minLength: AppTheme.Spacing.sm)

            if selectedCount < totalCount {
                Button("Tümünü Seç", action: onSelectAll)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            } else {
                Button("Seçimi Kaldır", action: onClearSelection)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            if let onAddGroup {
                Button(action: onAddGroup) {
                    Image(systemName: "person.3")
                        .foregroundStyle(selectedCount > 0 ? .white : .white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(canDelete ? AppTheme.Colors.danger : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)

            Button(action: onDone) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(barBackground)
    }
}

// MARK: - Row gestures

extension View {
    /// `Button` + `onLongPressGesture` çakışması olmadan kısa dokunma ve uzun basma (Android `combinedClickable`).
    func rowTapAndLongPress(
        onTap: @escaping () -> Void,
        onLongPress: (() -> Void)? = nil,
        longPressDuration: Double = 0.45
    ) -> some View {
        modifier(RowTapAndLongPressModifier(
            onTap: onTap,
            onLongPress: onLongPress,
            longPressDuration: longPressDuration
        ))
    }
}

private struct RowTapAndLongPressModifier: ViewModifier {
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    let longPressDuration: Double

    func body(content: Content) -> some View {
        if let onLongPress {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .onLongPressGesture(minimumDuration: longPressDuration) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPress()
                }
        } else {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        }
    }
}

// MARK: - Form validation hint

struct ValidationHint: View {
    let result: InputValidationResult

    var body: some View {
        if let message = result.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.danger)
        }
    }
}

// MARK: - Guest list grouping

struct GuestRowContext: Hashable {
    let orderNumber: Int
    let isLastInSection: Bool
    let sectionKey: String
    let isInDelegationSection: Bool
}

enum GuestListUiItem: Identifiable {
    case sectionHeader(String, guestCount: Int)
    case timeHeader(String?, sectionKey: String)
    case guest(Guest, context: GuestRowContext)

    var id: String {
        switch self {
        case .sectionHeader(let title, _):
            return "section-\(title)"
        case .timeHeader(let time, let sectionKey):
            return "time-\(sectionKey)-\(time ?? "none")"
        case .guest(let guest, _):
            return "guest-\(guest.id)"
        }
    }
}

enum GuestListGrouping {
    static func parseExpectedTimeToMinutes(_ time: String?) -> Int {
        guard let time, !time.isEmpty else { return Int.max }
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let minutes = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return Int.max }
        return hours * 60 + minutes
    }

    static func build(from guests: [Guest]) -> [GuestListUiItem] {
        let orderMap = Dictionary(
            uniqueKeysWithValues: guests
                .sorted { parseExpectedTimeToMinutes($0.expectedTime) < parseExpectedTimeToMinutes($1.expectedTime) }
                .enumerated()
                .map { (offset, guest) in (guest.id, offset + 1) }
        )

        let bySection = Dictionary(grouping: guests) { guest -> String in
            let trimmed = guest.sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "" : trimmed
        }

        let sectionKeys = bySection.keys.sorted { lhs, rhs in
            if lhs.isEmpty && !rhs.isEmpty { return false }
            if !lhs.isEmpty && rhs.isEmpty { return true }
            let lhsMin = (bySection[lhs] ?? []).compactMap(\.expectedTime).filter { !$0.isEmpty }
                .map(parseExpectedTimeToMinutes).min() ?? Int.max
            let rhsMin = (bySection[rhs] ?? []).compactMap(\.expectedTime).filter { !$0.isEmpty }
                .map(parseExpectedTimeToMinutes).min() ?? Int.max
            return lhsMin < rhsMin
        }

        var items: [GuestListUiItem] = []
        for sectionKey in sectionKeys {
            guard let sectionGuests = bySection[sectionKey] else { continue }
            let isIndividual = sectionKey.caseInsensitiveCompare("Bireysel Ziyaretçi") == .orderedSame
            let hasSection = !sectionKey.isEmpty && !isIndividual
            let byTime = Dictionary(grouping: sectionGuests) { $0.expectedTime }
            let sortedTimes = byTime.keys.sorted { parseExpectedTimeToMinutes($0) < parseExpectedTimeToMinutes($1) }
            let totalInSection = sectionGuests.count

            if hasSection {
                items.append(.sectionHeader(sectionKey, guestCount: totalInSection))
            }

            var guestIndex = 0
            for time in sortedTimes {
                let timeGuests = (byTime[time] ?? []).sorted {
                    $0.name.localizedCompare($1.name) == .orderedAscending
                }
                items.append(.timeHeader(time, sectionKey: sectionKey))
                for guest in timeGuests {
                    guestIndex += 1
                    items.append(.guest(
                        guest,
                        context: GuestRowContext(
                            orderNumber: orderMap[guest.id] ?? 0,
                            isLastInSection: guestIndex == totalInSection && hasSection,
                            sectionKey: sectionKey,
                            isInDelegationSection: hasSection
                        )
                    ))
                }
            }
        }
        return items
    }
}

struct DelegationSectionHeader: View {
    let title: String
    let guestCount: Int

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "person.3.fill")
                .foregroundStyle(AppTheme.Colors.success)
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(guestCount) misafir")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(AppTheme.Colors.success.opacity(0.35), lineWidth: 1)
        )
    }
}

struct MeetingTimeHeader: View {
    let time: String?

    var body: some View {
        if let time, !time.isEmpty {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "clock")
                    .foregroundStyle(AppTheme.Colors.warning)
                Text("Toplantı: \(time.replacingOccurrences(of: ":", with: "."))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.warning)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.warning.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
        } else {
            HStack(spacing: AppTheme.Spacing.sm) {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 4, height: 4)
                Text("Saat Belirtilmemiş")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
    }
}

// MARK: - Status badge

/// Misafir durumu için renkli rozet.
struct StatusBadge: View {
    let status: GuestStatus

    var body: some View {
        Label(status.displayName, systemImage: status.iconName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.14))
            .clipShape(Capsule())
    }
}

// MARK: - Search field

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Ara…"

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm + 2)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.xl)
    }
}

// MARK: - Loading overlay

struct LoadingOverlay: View {
    var message: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: AppTheme.Spacing.md) {
                ProgressView()
                    .controlSize(.large)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(AppTheme.Spacing.xl)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? "Yükleniyor")
    }
}

// MARK: - Toast

struct ToastMessage: Equatable {
    enum Kind { case success, error }
    let text: String
    let kind: Kind
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: ToastMessage?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    toastView(toast)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast) {
                            try? await Task.sleep(nanoseconds: AppConstants.UIDelays.snackbarAutoDismissNanos)
                            self.toast = nil
                        }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: toast)
    }

    private func toastView(_ message: ToastMessage) -> some View {
        let color = message.kind == .success ? AppTheme.Colors.success : AppTheme.Colors.danger
        let icon = message.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        return HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

extension View {
    func toast(_ toast: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

// MARK: - UiEvent köprüsü

extension UiEvent {
    /// Snackbar/toast için mesaj üretir; ilgili olmayan olaylar için `nil`.
    var toastMessage: ToastMessage? {
        switch self {
        case .showSuccess(let message):
            return ToastMessage(text: message, kind: .success)
        case .showError(let message):
            return ToastMessage(text: message, kind: .error)
        default:
            return nil
        }
    }
}
