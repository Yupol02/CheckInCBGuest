import Foundation

/// Form giriş doğrulama sonucu (Android `ValidationResult` eşleniği).
///
/// Not: `FirestoreDataValidator.ValidationResult` (nested, generic) Firestore belge
/// dönüşümleri için kullanılır. Bu tip ise UI form girişleri içindir; isim çakışmasını
/// önlemek için `InputValidationResult` olarak adlandırılmıştır.
enum InputValidationResult: Equatable, Sendable {
    case success
    case error(String)

    var isValid: Bool {
        if case .success = self { return true }
        return false
    }

    var errorMessage: String? {
        if case let .error(message) = self { return message }
        return nil
    }
}

/// Giriş doğrulama yardımcıları (Android `Validators`).
enum Validators {

    private static let namePattern = "^[a-zA-ZğüşıöçĞÜŞİÖÇ\\s]+$"
    private static let platePattern = "^[0-9]{2}\\s?[A-Z]{1,3}\\s?[0-9]{2,4}$"
    private static let timePattern = "^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$"

    /// ISO 8601 zaman damgasını UI için `HH:mm` formatına dönüştürür.
    ///
    /// `entryTime`/`exitTime` Firestore'da ISO 8601 olarak saklanır
    /// (ör. `2024-01-01T12:23:00Z`), UI ise `12:23` gösterir.
    static func formatTimeForDisplay(_ iso8601Timestamp: String?) -> String? {
        guard let value = iso8601Timestamp?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }

        if let date = parseISO8601(value) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "tr_TR")
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }

        // Eski/yedek veri: zaten HH:mm formatındaysa olduğu gibi döndür.
        if value.range(of: "^\\d{2}:\\d{2}$", options: .regularExpression) != nil {
            return value
        }
        return nil
    }

    /// Ad soyad doğrulama: boş değil, 2-200 karakter, yalnızca harf ve boşluk (Türkçe destekli).
    static func validateName(_ name: String?) -> InputValidationResult {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Ad soyad boş olamaz")
        }
        if name.count < AppConstants.Validation.minNameLength {
            return .error("Ad soyad en az \(AppConstants.Validation.minNameLength) karakter olmalıdır")
        }
        if name.count > AppConstants.Validation.maxNameLength {
            return .error("Ad soyad en fazla \(AppConstants.Validation.maxNameLength) karakter olabilir")
        }
        if name.range(of: namePattern, options: .regularExpression) == nil {
            return .error("Ad soyad sadece harf ve boşluk içerebilir")
        }
        return .success
    }

    /// Ünvan doğrulama: boş değil, 2-200 karakter.
    static func validateTitle(_ title: String?) -> InputValidationResult {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Ünvan boş olamaz")
        }
        if title.count < AppConstants.Validation.minTitleLength {
            return .error("Ünvan en az \(AppConstants.Validation.minTitleLength) karakter olmalıdır")
        }
        if title.count > AppConstants.Validation.maxTitleLength {
            return .error("Ünvan en fazla \(AppConstants.Validation.maxTitleLength) karakter olabilir")
        }
        return .success
    }

    /// Türk plaka formatı doğrulama (ör. `34 AB 123`, `06ABC1234`).
    static func validatePlate(_ plate: String?) -> InputValidationResult {
        guard let plate, !plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Plaka boş olamaz")
        }
        if plate.count < 4 {
            return .error("Plaka geçerli değil (çok kısa)")
        }
        if plate.count > 10 {
            return .error("Plaka geçerli değil (çok uzun)")
        }
        if plate.range(of: platePattern, options: .regularExpression) == nil {
            return .error("Plaka formatı geçersiz. Örnek: 34 AB 123 veya 06ABC1234")
        }
        return .success
    }

    /// Tarih doğrulama (yalnızca boş kontrolü).
    static func validateDate(_ date: String?) -> InputValidationResult {
        guard let date, !date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Tarih boş olamaz")
        }
        return .success
    }

    /// Saat doğrulama (24 saatlik `HH:mm` formatı).
    static func validateTime(_ time: String?) -> InputValidationResult {
        guard let time, !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Saat boş olamaz")
        }
        if time.range(of: timePattern, options: .regularExpression) == nil {
            return .error("Saat formatı geçersiz. 24 saatlik format kullanın (örn: 09:00, 23:59)")
        }
        return .success
    }

    /// Lokasyon/toplantı içeriği doğrulama: boş değil, min 2 karakter.
    static func validateLocation(_ location: String?) -> InputValidationResult {
        guard let location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Toplantı içeriği boş olamaz")
        }
        if location.count < 2 {
            return .error("Toplantı içeriği en az 2 karakter olmalıdır")
        }
        return .success
    }

    /// Etkinlik başlığı doğrulama: boş değil, 3-100 karakter.
    static func validateEventTitle(_ title: String?) -> InputValidationResult {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Etkinlik başlığı boş olamaz")
        }
        if title.count < 3 {
            return .error("Etkinlik başlığı en az 3 karakter olmalıdır")
        }
        if title.count > 100 {
            return .error("Etkinlik başlığı en fazla 100 karakter olabilir")
        }
        return .success
    }

    // MARK: - Private

    private static func parseISO8601(_ value: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

/// Tarih yardımcıları (Android `DateUtils`).
enum DateUtils {

    /// Etkinlik (tarih + başlangıç saati) geçmişte mi?
    ///
    /// Android `DateUtils.isEventPast` `dd.MM.yyyy HH:mm` bekliyordu ancak gerçek
    /// `Event.date` formatı `d MMMM yyyy` (tr_TR). Bu nedenle iOS tarafında doğru
    /// formatla (`d MMMM yyyy HH:mm`) parse edilir; başarısız olursa tarih bazlı
    /// `Event.isExpired` fallback'ine düşülür.
    static func isEventPast(_ event: Event?) -> Bool {
        guard let event else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy HH:mm"
        let combined = "\(event.date) \(event.startTime)"
        if let eventDateTime = formatter.date(from: combined) {
            return Date() > eventDateTime
        }
        return event.isExpired
    }
}
