import Foundation
import os.log

// MARK: - Validate

/// Excel dosya doğrulama (Android `ValidateExcelFileUseCase`).
final class DefaultValidateExcelFileUseCase: ValidateExcelFileUseCase {
    private let parser: DefaultExcelParser

    init(parser: DefaultExcelParser) {
        self.parser = parser
    }

    func execute(fileURL: URL) async -> FileValidationResult {
        await parser.validateFormat(fileURL: fileURL)
    }
}

// MARK: - Parse

/// Excel ayrıştırma + önizleme (Android `ParseExcelFileUseCase`).
final class DefaultParseExcelFileUseCase: ParseExcelFileUseCase {
    private let parser: DefaultExcelParser

    init(parser: DefaultExcelParser) {
        self.parser = parser
    }

    func execute(fileURL: URL) async throws -> ParseResult {
        try await parser.parseFile(fileURL: fileURL)
    }

    func preview(fileURL: URL, rowCount: Int) async throws -> PreviewResult {
        try await parser.preview(fileURL: fileURL, rowCount: rowCount)
    }
}

// MARK: - Import

/// Excel'den misafir içe aktarma (Android `ImportGuestsFromExcelUseCase`).
///
/// Akış: kırmızı liste isimlerini çek → dosyayı ayrıştır → her satırı kırmızı liste ile
/// karşılaştır (eşleşme → onay bekleyen) → toplu Firestore yazımı.
final class DefaultImportGuestsFromExcelUseCase: ImportGuestsFromExcelUseCase {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "ImportGuestsUseCase")
    private static let progressInterval = AppConstants.ExcelImport.importChunkSize

    private let parser: DefaultExcelParser
    private let eventRepository: any EventRepository
    private let redListRepository: any RedListRepository

    init(
        parser: DefaultExcelParser,
        eventRepository: any EventRepository,
        redListRepository: any RedListRepository
    ) {
        self.parser = parser
        self.eventRepository = eventRepository
        self.redListRepository = redListRepository
    }

    func execute(
        fileURL: URL,
        eventId: String,
        onProgress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> ImportResult {
        // 1) Kırmızı liste isimleri (normalize edilmiş).
        let rawNames: Set<String>
        if await NetworkMonitor.shared.isConnected {
            rawNames = await redListRepository.fetchRedListDirectlyFromCloud()
        } else {
            rawNames = await redListRepository.getAllActiveRedListNames()
        }
        let redListNames = Set(rawNames.map { redListRepository.normalizeGuestName($0) })

        // 2) Dosyayı ayrıştır.
        let parseResult = try await parser.parseFile(fileURL: fileURL)

        var errors: [ImportError] = []
        for invalid in parseResult.invalidRows {
            errors.append(ImportError(
                rowNumber: invalid.rowNumber,
                field: invalid.errors.first?.field,
                message: invalid.errors.first?.message ?? "Geçersiz format",
                rawData: invalid.rawData
            ))
        }

        // 3) Satırları işle.
        var guestsToInsert: [Guest] = []
        var successCount = 0
        var redListHits = 0

        let total = parseResult.validRows.count
        for (index, row) in parseResult.validRows.enumerated() {
            let normalized = redListRepository.normalizeGuestName(row.name)
            let isSuspect = redListNames.contains(normalized)

            let guest = Guest(
                id: UUID().uuidString,
                eventId: eventId,
                name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                title: row.title.trimmingCharacters(in: .whitespacesAndNewlines),
                arrivalMethod: row.arrivalMethod,
                plate: row.plate?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "tr_TR")),
                model: row.model,
                status: isSuspect ? .pendingApproval : .pending,
                isRedListPending: isSuspect
            )
            guestsToInsert.append(guest)

            if isSuspect {
                redListHits += 1
            } else {
                successCount += 1
            }

            let processed = index + 1
            if processed % Self.progressInterval == 0 || processed == total {
                onProgress(ImportProgress.create(current: processed, total: total))
            }
        }

        // 4) Toplu yazım.
        if !guestsToInsert.isEmpty {
            await eventRepository.insertGuests(guestsToInsert)
        }

        return ImportResult(
            successCount: successCount,
            errorCount: errors.count,
            redListHits: redListHits,
            errors: errors,
            skippedRows: []
        )
    }
}
