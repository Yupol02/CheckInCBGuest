import SwiftUI

#Preview("Event — Aktif") {
    Text(Event.previewActive.title)
        .font(.headline)
        .padding()
}

#Preview("Guest — İçeride") {
    VStack(alignment: .leading, spacing: 8) {
        Text(Guest.previewCheckedIn.name)
            .font(.headline)
        Text(Guest.previewCheckedIn.status.rawValue)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}

#Preview("RedListMember — VIP") {
    VStack(alignment: .leading, spacing: 8) {
        Text(RedListMember.previewVIP.guestName)
            .font(.headline)
        Text(RedListMember.previewVIP.reason.rawValue)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}
