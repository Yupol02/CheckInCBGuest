import FirebaseFirestore
import Foundation
import os.log

/// Admin bildirim kuyruğuna yazma servisi (Android `EventViewModel.sendRedListNotification`).
///
/// `admin_notifications` koleksiyonuna belge eklenir; Cloud Function bunu `admin_alerts`
/// FCM topic'ine push olarak iletir. İstemci doğrudan FCM göndermez.
enum AdminNotificationService {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "AdminNotificationService")
    static let collectionName = "admin_notifications"

    /// Kırmızı liste şüphesiyle onaya gönderilen misafir için bildirim oluşturur.
    static func sendRedListNotification(event: Event?, guest: Guest) async {
        let eventName = event?.title ?? "Bilinmeyen Etkinlik"
        let body = "Bu \(eventName) isimli etkinliğe kırmızı listeden misafir eklendi"

        let data: [String: Any] = [
            "title": eventName,
            "body": body,
            "eventId": event?.id ?? "",
            "guestId": guest.id,
            "guestName": guest.name,
            "type": "RED_LIST_ALERT",
            "timestamp": FieldValue.serverTimestamp(),
            "isRead": false,
            "priority": "HIGH",
        ]

        do {
            try await Firestore.firestore()
                .collection(collectionName)
                .document()
                .setData(data)
        } catch {
            logger.error("Admin notification write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
