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

        let event = Event(
            title: trimmedTitle,
            date: eventDateFormatter.string(from: date),
            location: trimmedLocation,
            startTime: eventTimeFormatter.string(from: time),
            status: eventStatus(for: date)
        )
        Task {
            await eventVM.addEvent(event)
            dismiss()
        }
    }
}

/// Var olan etkinliğin adını, içeriğini, tarihini ve saatini düzenler.
///
/// YALNIZCA YÖNETİCİ: ekran zaten yalnızca yöneticide açılan uzun basma menüsünden
/// çağrılır, ayrıca `EventViewModel.updateEvent` kapıyı bir kez daha kontrol eder.
///
/// GEÇMİŞ TARİH SEÇİLEMEZ: takvimin alt sınırı bugündür. Sebep, geçmiş etkinliklerin
/// düzenlemeye KİLİTLİ olmasıdır — yanlışlıkla geçmişe taşınan bir etkinlik bir daha
/// hiç düzeltilemez hâle gelirdi. Kilit ile takvim sınırı bilerek aynı ölçütü kullanır.
@MainActor
struct EditEventView: View {

    let event: Event

    @Environment(EventViewModel.self) private var eventVM
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var location: String
    @State private var date: Date
    @State private var time: Date

    init(event: Event) {
        self.event = event
        _title = State(initialValue: event.title)
        _location = State(initialValue: event.location)
        _date = State(initialValue: eventDateFormatter.date(from: event.date) ?? Date())
        _time = State(initialValue: eventTimeFormatter.date(from: event.startTime) ?? Date())
    }

    private var isValid: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Takvimin alt sınırı: bugünün başlangıcı. Bugün seçilebilir, dün seçilemez.
    private var earliestSelectableDate: Date {
        Calendar(identifier: .gregorian).startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Etkinlik Bilgileri") {
                    TextField("Etkinlik Adı", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Toplantı içeriği", text: $location)
                }

                Section {
                    DatePicker(
                        "Tarih",
                        selection: $date,
                        in: earliestSelectableDate...,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                    DatePicker("Saat", selection: $time, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Tarih ve Saat")
                } footer: {
                    Text("Etkinlik geçmiş bir tarihe taşınamaz; geçmiş etkinlikler düzenlemeye kapalıdır.")
                }
            }
            .navigationTitle("Etkinliği Düzenle")
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
        // Kimlik, silinme durumu ve sayaçlar KORUNUR; yalnızca dört alan değişir.
        // `status` tarihe göre yeniden hesaplanır ki liste sıralaması ile rozet,
        // yeni tarihle tutarlı olsun.
        let updated = Event(
            id: event.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: eventDateFormatter.string(from: date),
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            startTime: eventTimeFormatter.string(from: time),
            status: eventStatus(for: date),
            deletedAt: event.deletedAt,
            participatedCount: event.participatedCount,
            totalGuestCount: event.totalGuestCount
        )
        Task {
            await eventVM.updateEvent(updated)
            dismiss()
        }
    }
}

// MARK: - Ortak biçimlendiriciler

/// Firestore'daki `date` alanının biçimi: "2 Eylül 2026".
///
/// `Event.dayKey` bu metni AYNI biçimle geri ayrıştırır; buradaki biçim değişirse
/// gün anahtarı üretilemez ve etkinlik yönetici olmayan cihazlarda görünmez olur.
let eventDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "tr_TR")
    formatter.dateFormat = "d MMMM yyyy"
    return formatter
}()

let eventTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "tr_TR")
    formatter.dateFormat = "HH:mm"
    return formatter
}()

/// Tarihe göre etkinlik durumu. `Event.computedStatus` ile aynı ölçüt.
func eventStatus(for date: Date) -> EventStatus {
    let calendar = Calendar(identifier: .gregorian)
    let today = calendar.startOfDay(for: Date())
    let eventDay = calendar.startOfDay(for: date)
    if eventDay < today { return .past }
    if eventDay == today { return .active }
    return .upcoming
}

#Preview {
    AddEventView()
        .environment(AppDependencies.makeEventViewModel())
}
