import PhotosUI
import SwiftUI
import UIKit

/// Yeni misafir ekleme formu (Android `AddGuestScreen`).
@MainActor
struct AddGuestView: View {

    let event: Event

    @Environment(EventViewModel.self) private var eventVM
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var title = ""
    @State private var arrivalMethod: ArrivalMethod = .pedestrian
    @State private var plate = ""
    @State private var model = ""
    @State private var sectionTitle = ""
    @State private var note = ""
    @State private var participationCategory: ParticipationCategory = .protokolDavetli
    @State private var securityCheck = true
    @State private var includeExpectedTime = false
    @State private var expectedTime = Date()
    @State private var photoItem: PhotosPickerItem?
    @State private var photoImage: Image?
    @State private var photoLocalURL: URL?
    @State private var showValidationErrors = false
    @State private var isSaving = false

    private var nameValidation: InputValidationResult { Validators.validateName(name) }
    private var titleValidation: InputValidationResult { Validators.validateTitle(title) }
    private var plateValidation: InputValidationResult {
        arrivalMethod == .vehicle ? Validators.validatePlate(plate) : .success
    }

    private var isFormValid: Bool {
        nameValidation.isValid
            && titleValidation.isValid
            && plateValidation.isValid
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection

                Section("Zamanlama") {
                    Toggle("Beklenen toplantı saati", isOn: $includeExpectedTime)
                    if includeExpectedTime {
                        DatePicker("Saat", selection: $expectedTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Misafir Bilgileri") {
                    TextField("Ad Soyad", text: $name)
                        .textInputAutocapitalization(.words)
                    ValidationHint(result: showValidationErrors ? nameValidation : .success)

                    TextField("Ünvan / Şirket", text: $title)
                        .textInputAutocapitalization(.words)
                    ValidationHint(result: showValidationErrors ? titleValidation : .success)

                    Picker("Katılım Kategorisi *", selection: $participationCategory) {
                        ForEach(ParticipationCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
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
                            .onChange(of: plate) { _, newValue in
                                plate = newValue.uppercased(with: Locale(identifier: "tr_TR"))
                            }
                        ValidationHint(result: showValidationErrors ? plateValidation : .success)
                        TextField("Araç Modeli", text: $model)
                    }
                }

                Section("Güvenlik Protokolü") {
                    Toggle(isOn: $securityCheck) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(securityCheck ? "Arama Gerekli" : "VIP / Hızlı Geçiş")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(securityCheck ? AppTheme.Colors.danger : AppTheme.Colors.success)
                            Text(securityCheck ? "Standart güvenlik prosedürü" : "Protokol girişi, arama yok")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(securityCheck ? AppTheme.Colors.danger : AppTheme.Colors.success)
                }

                Section("Detaylar") {
                    TextField("Heyet (opsiyonel)", text: $sectionTitle)
                    TextField("Not (opsiyonel)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Misafir Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving || eventVM.isLoading {
                    LoadingOverlay(message: "Kaydediliyor…")
                }
            }
            .onChange(of: photoItem) { _, newValue in
                Task { await loadPhoto(newValue) }
            }
        }
    }

    private var photoSection: some View {
        Section {
            HStack {
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) {
                    if let photoImage {
                        photoImage
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle().fill(AppTheme.Colors.accentSoft)
                                .frame(width: 96, height: 96)
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        if let uiImage = UIImage(data: data) {
            photoImage = Image(uiImage: uiImage)
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("guest_\(UUID().uuidString).jpg")
        do {
            try data.write(to: tempURL)
            photoLocalURL = tempURL
        } catch {
            photoLocalURL = nil
        }
    }

    private func save() {
        showValidationErrors = true
        guard isFormValid else { return }

        let trimmedSection = sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlate = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        let expectedTimeString: String? = includeExpectedTime ? Self.timeFormatter.string(from: expectedTime) : nil

        let guest = Guest(
            eventId: event.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            arrivalMethod: arrivalMethod,
            plate: trimmedPlate.isEmpty ? nil : trimmedPlate,
            model: trimmedModel.isEmpty ? nil : trimmedModel,
            securityCheck: securityCheck,
            photoUri: photoLocalURL?.absoluteString,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            expectedTime: expectedTimeString,
            sectionTitle: trimmedSection.isEmpty ? nil : trimmedSection,
            participationCategory: participationCategory
        )

        isSaving = true
        Task {
            let success = await eventVM.insertGuest(guest, currentEvent: event)
            isSaving = false
            if success { dismiss() }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

#Preview {
    AddGuestView(event: .previewActive)
        .environment(AppDependencies.makeEventViewModel())
}
