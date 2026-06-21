import FirebaseStorage
import Foundation
import UniformTypeIdentifiers
import os.log

// MARK: - Sonuç tipi

/// Misafir fotoğrafı yükleme sonucu (Android `PhotoUploadResult`).
enum PhotoUploadResult: Sendable {
    case success(downloadURL: String)
    case failure(message: String)

    var downloadURL: String? {
        if case .success(let url) = self { return url }
        return nil
    }
}

// MARK: - Firebase Storage yardımcı

/// Misafir fotoğraflarını Firebase Storage'a yükler (Android `FirebaseModule` Storage bölümü).
///
/// Storage yolu: `guest_photos/{eventId}/{guestId}.jpg` — Android ile birebir aynıdır.
/// Kaydedilen değer Firestore `photoUri` alanına yazılacak indirme (download) URL'sidir.
enum GuestPhotoStorage {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "GuestPhotoStorage")

    /// Android `StorageConstants` eşleniği.
    enum Constants {
        static let guestPhotosPath = "guest_photos"
        static let maxFileSizeBytes: Int64 = 10 * 1024 * 1024 // 10 MB
        static let defaultContentType = "image/jpeg"
        static let fileExtension = "jpg"
    }

    /// `guest_photos/{eventId}/{guestId}.jpg` referansını döndürür.
    static func guestPhotoReference(eventId: String, guestId: String) throws -> StorageReference {
        guard !eventId.isEmpty, !guestId.isEmpty else {
            throw PhotoStorageError.invalidParameters
        }
        guard !eventId.contains("/"), !guestId.contains("/") else {
            throw PhotoStorageError.invalidParameters
        }
        return Storage.storage().reference()
            .child(Constants.guestPhotosPath)
            .child(eventId)
            .child("\(guestId).\(Constants.fileExtension)")
    }

    /// Yerel dosya URL'sinden fotoğraf yükler. Başarılıysa indirme URL'si döner.
    static func uploadGuestPhoto(
        localURL: URL,
        eventId: String,
        guestId: String
    ) async -> PhotoUploadResult {
        do {
            let needsScopedAccess = localURL.startAccessingSecurityScopedResource()
            defer { if needsScopedAccess { localURL.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: localURL)
            let contentType = resolveContentType(for: localURL)
            return await uploadGuestPhoto(
                data: data,
                contentType: contentType,
                eventId: eventId,
                guestId: guestId
            )
        } catch {
            logger.error("Photo read error: \(error.localizedDescription, privacy: .public)")
            return .failure(message: "Fotoğraf okunamadı: \(error.localizedDescription)")
        }
    }

    /// Ham veriden fotoğraf yükler. Başarılıysa indirme URL'si döner.
    static func uploadGuestPhoto(
        data: Data,
        contentType: String = Constants.defaultContentType,
        eventId: String,
        guestId: String
    ) async -> PhotoUploadResult {
        guard Int64(data.count) <= Constants.maxFileSizeBytes else {
            let sizeMB = data.count / 1024 / 1024
            return .failure(message: "Dosya boyutu çok büyük: \(sizeMB) MB. Maksimum \(Constants.maxFileSizeBytes / 1024 / 1024) MB olmalı.")
        }
        guard contentType.hasPrefix("image/") else {
            return .failure(message: "Dosya resim formatında değil: \(contentType)")
        }

        do {
            let ref = try guestPhotoReference(eventId: eventId, guestId: guestId)
            let metadata = StorageMetadata()
            metadata.contentType = contentType
            metadata.customMetadata = [
                "eventId": eventId,
                "guestId": guestId,
                "uploadedAt": String(Int(Date().timeIntervalSince1970 * 1000)),
            ]
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let url = try await ref.downloadURL()
            return .success(downloadURL: url.absoluteString)
        } catch {
            logger.error("Photo upload error: \(error.localizedDescription, privacy: .public)")
            return .failure(message: "Fotoğraf yüklenemedi: \(error.localizedDescription)")
        }
    }

    /// Bir `photoUri` değeri yerel dosya mı (henüz yüklenmemiş) yoksa uzak URL mi?
    static func isLocalURI(_ photoUri: String?) -> Bool {
        guard let photoUri, !photoUri.isEmpty else { return false }
        return !photoUri.hasPrefix("http")
    }

    private static func resolveContentType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType,
           mime.hasPrefix("image/") {
            return mime
        }
        return Constants.defaultContentType
    }
}

enum PhotoStorageError: Error, Sendable {
    case invalidParameters
}
