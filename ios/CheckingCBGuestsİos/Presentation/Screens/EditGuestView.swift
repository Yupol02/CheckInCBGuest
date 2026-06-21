import SwiftUI

/// Mevcut misafir bilgilerini düzenleme formu (Android `GuestDetailScreen` düzenleme akışı).
@MainActor
struct EditGuestView: View {

    let guest: Guest
    let event: Event

    @Environment(EventViewModel.self) private var eventVM
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var title: String
    @State private var arrivalMethod: ArrivalMethod
    @State private var plate: String
    @State private var model: String
    @State private var sectionTitle: String
    @State private var note: String
    @State private var participationCategory: ParticipationCategory

    init(guest: Guest, event: Event) {
        self.guest = guest
        self.event = event
        _name = State(initialValue: guest.name)
        _title = State(initialValue: guest.title)
        _arrivalMethod = State(initialValue: guest.arrivalMethod)
        _plate = State(initialValue: guest.plate ?? "")
        _model = State(initialValue: guest.model ?? "")
        _sectionTitle = State(initialValue: guest.sectionTitle ?? "")
        _note = State(initialValue: guest.note ?? "")
        _participationCategory = State(initialValue: guest.participationCategory ?? .protokolDavetli)
    }

    private var isValid: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && (arrivalMethod == .pedestrian || !plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Misafir Bilgileri") {
                    TextField("Ad Soyad", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Unvan / Kurum", text: $title)
                }
                Section("Geliş") {
                    Picker("Geliş Yöntemi", selection: $arrivalMethod) {
                        ForEach(ArrivalMethod.allCases, id: \.self) { method in
                            Label(method.displayName, systemImage: method.iconName).tag(method)
                        }
                    }
                    if arrivalMethod == .vehicle {
                        TextField("Plaka", text: $plate)
                            .textInputAutocapitalization(.characters)
                        TextField("Araç Modeli", text: $model)
                    }
                }
                Section("Detaylar") {
                    Picker("Kategori", selection: $participationCategory) {
                        ForEach(ParticipationCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    TextField("Heyet (opsiyonel)", text: $sectionTitle)
                    TextField("Not (opsiyonel)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Düzenle")
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
        let trimmedSection = sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlate = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        var updated = guest
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.arrivalMethod = arrivalMethod
        updated.plate = trimmedPlate.isEmpty ? nil : trimmedPlate.uppercased(with: Locale(identifier: "tr_TR"))
        updated.model = trimmedModel.isEmpty ? nil : trimmedModel
        updated.sectionTitle = trimmedSection.isEmpty ? nil : trimmedSection
        updated.note = trimmedNote.isEmpty ? nil : trimmedNote
        updated.participationCategory = participationCategory

        let finalGuest = updated
        Task {
            await eventVM.updateGuestDetails(finalGuest, currentEvent: event)
            dismiss()
        }
    }
}

#Preview {
    EditGuestView(guest: .previewCheckedIn, event: .previewActive)
        .environment(AppDependencies.makeEventViewModel())
}
