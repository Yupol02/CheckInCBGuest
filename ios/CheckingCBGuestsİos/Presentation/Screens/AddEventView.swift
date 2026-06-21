import SwiftUI

/// Yeni etkinlik ekleme formu (Android `AddEventScreen`).
@MainActor
struct AddEventView: View {

    @Environment(EventViewModel.self) private var eventVM
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var location = ""
    @State private var date = Date()
    @State private var time = Date()
    @State private var errorMessage: String?

    private var isValid: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Etkinlik Bilgileri") {
                    TextField("Etkinlik Adı", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Toplantı içeriği", text: $location)
                }

                Section("Tarih ve Saat") {
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                    DatePicker("Saat", selection: $time, displayedComponents: .hourAndMinute)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle("Yeni Etkinlik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)

        let dateString = Self.dateFormatter.string(from: date)
        let timeString = Self.timeFormatter.string(from: time)

        let event = Event(
            title: trimmedTitle,
            date: dateString,
            location: trimmedLocation,
            startTime: timeString,
            status: status(for: date)
        )
        Task {
            await eventVM.addEvent(event)
            dismiss()
        }
    }

    private func status(for date: Date) -> EventStatus {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let eventDay = calendar.startOfDay(for: date)
        if eventDay < today { return .past }
        if eventDay == today { return .active }
        return .upcoming
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

#Preview {
    AddEventView()
        .environment(AppDependencies.makeEventViewModel())
}
