import Foundation

// MARK: - Event

enum EventStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case active = "ACTIVE"
    case upcoming = "UPCOMING"
    case past = "PAST"
}

// MARK: - Guest

/// Katılım kategorisi — misafir türünü belirler.
enum ParticipationCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case protokolDavetli = "PROTOKOL_DAVETLI"
    case teknikEkip = "TEKNIK_EKIP"
    case operasyonLojistik = "OPERASYON_LOJISTIK"
    case guvenlikKoruma = "GUVENLIK_KORUMA"
    case basinMedya = "BASIN_MEDYA"
    case hizmetTedarik = "HIZMET_TEDARIK"
    case diger = "DIGER"

    var displayName: String {
        switch self {
        case .protokolDavetli: return "Protokol / Davetli"
        case .teknikEkip: return "Teknik Ekip"
        case .operasyonLojistik: return "Operasyon & Lojistik"
        case .guvenlikKoruma: return "Güvenlik & Koruma"
        case .basinMedya: return "Basın / Medya"
        case .hizmetTedarik: return "Hizmet / Tedarik"
        case .diger: return "Diğer"
        }
    }

    var shortName: String {
        switch self {
        case .protokolDavetli: return "Protokol"
        case .teknikEkip: return "Teknik Ekip"
        case .operasyonLojistik: return "Operasyon & Lojistik"
        case .guvenlikKoruma: return "Güvenlik & Koruma"
        case .basinMedya: return "Basın / Medya"
        case .hizmetTedarik: return "Hizmet / Tedarik"
        case .diger: return "Diğer"
        }
    }
}

/// Misafir geliş yöntemi.
enum ArrivalMethod: String, Codable, Sendable, Hashable, CaseIterable {
    /// Yaya girişi
    case pedestrian = "PEDESTRIAN"
    /// Araç ile giriş
    case vehicle = "VEHICLE"
}

/// Misafir durumu.
enum GuestStatus: String, Codable, Sendable, Hashable, CaseIterable {
    /// Beklemede — henüz giriş yapılmadı
    case pending = "PENDING"
    /// Giriş yapıldı
    case checkedIn = "CHECKED_IN"
    /// Çıkış yapıldı
    case exited = "EXITED"
    /// Admin onayı bekliyor (kırmızı liste şüphesi veya riskli kayıt)
    case pendingApproval = "PENDING_APPROVAL"
}

// MARK: - Red List

/// Kırmızı listeye ekleme sebebi.
enum RedListEntryReason: String, Codable, Sendable, Hashable, CaseIterable {
    case vip = "VIP"
    case security = "SECURITY"
    case special = "SPECIAL"
    case media = "MEDIA"
    case sponsor = "SPONSOR"
    case staff = "STAFF"

    /// Kullanıcıya gösterilecek Türkçe etiket.
    var displayName: String {
        switch self {
        case .vip: return "VIP"
        case .security: return "Güvenlik"
        case .special: return "Özel"
        case .media: return "Medya"
        case .sponsor: return "Sponsor"
        case .staff: return "Personel"
        }
    }
}
