import Foundation
import os.log

/// `.xlsx` ayrıştırma + doğrulama (Android `ApachePoiExcelParser` eşleniği).
///
/// Sabit sütun sırası yoktur: ilk 20 satır taranır, `name` eşlemesi bulunan satır
/// başlık kabul edilir ve mantıksal alanlar (`name/title/plate/model/arrivalMethod/notes`)
/// başlık varyantlarına göre eşlenir.
final class DefaultExcelParser: Sendable {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "DefaultExcelParser")

    private static let headerSearchLimit = 20
    private static let maxFileSizeBytes = ExcelImportConstants.maxFileSizeBytes

    /// Normalize edilmiş başlık → mantıksal alan eşlemesi (Android `columnMappings`).
    private static let columnMappings: [String: String] = [
        // name (zorunlu)
        "adsoyad": "name", "ad": "name", "soyad": "name", "isim": "name",
        "name": "name", "adi": "name", "soyadi": "name", "isimsoyisim": "name",
        // title (opsiyonel)
        "unvan": "title", "title": "title", "kurumadi": "title", "gorevi": "title",
        "pozisyon": "title", "firma": "title", "kurum": "title", "gorev": "title",
        // plate
        "plaka": "plate", "plate": "plate", "aracplakasi": "plate", "plakano": "plate",
        // model
        "aracmodeli": "model", "model": "model", "arac": "model", "vehicle": "model", "car": "model",
        // arrivalMethod
        "gelisyontemi": "arrivalMethod", "gelis": "arrivalMethod", "ulasim": "arrivalMethod",
        "arrivalmethod": "arrivalMethod",
        // notes
        "notlar": "notes", "notes": "notes", "aciklama": "notes", "not": "notes",
    ]

    // MARK: - Validate

    func validateFormat(fileURL: URL) async -> FileValidationResult {
        let ext = fileURL.pathExtension.lowercased()
        guard ext == "xlsx" || ext == "xls" else {
            return .error(message: "Geçersiz format. .xlsx gerekli.", errorType: .invalidFormat)
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .error(message: "Dosya açılamadı.", errorType: .fileNotFound)
        }

        guard Int64(data.count) <= Self.maxFileSizeBytes else {
            return .error(message: "Dosya çok büyük. Maksimum 10 MB.", errorType: .fileTooLarge)
        }

        // .xls (eski binary) bu okuyucu ile desteklenmez.
        guard data.count >= 2, data[data.startIndex] == 0x50, data[data.startIndex + 1] == 0x4b else {
            return .error(
                message: "Eski .xls formatı desteklenmiyor. Lütfen .xlsx kaydedip tekrar deneyin.",
                errorType: .fileCorrupted
            )
        }

        do {
            let sheet = try MinimalXLSXReader(data: data).readFirstSheet()
            if sheet.isEmpty {
                return .error(message: "Dosya boş veya okunamıyor.", errorType: .fileCorrupted)
            }
        } catch {
            return .error(message: "Dosya bozuk veya okunamıyor.", errorType: .fileCorrupted)
        }

        return .success(fileName: fileURL.lastPathComponent, fileSize: Int64(data.count))
    }

    // MARK: - Parse

    func parseFile(fileURL: URL) async throws -> ParseResult {
        let data = try Data(contentsOf: fileURL)
        let sheet = try MinimalXLSXReader(data: data).readFirstSheet()

        guard let headerInfo = detectHeader(in: sheet) else {
            let invalid = InvalidRow(
                rowNumber: 0,
                errors: [ValidationError(field: "header", message: "Geçerli başlık bulunamadı (Ad Soyad sütunu gerekli)")],
                rawData: [:]
            )
            return ParseResult(validRows: [], invalidRows: [invalid], totalRows: 0)
        }

        var validRows: [GuestRow] = []
        var invalidRows: [InvalidRow] = []
        var dataRowCount = 0

        let dataStartIndex = headerInfo.rowIndex + 1
        guard dataStartIndex < sheet.count else {
            return ParseResult(validRows: [], invalidRows: [], totalRows: 0)
        }

        for rowIndex in dataStartIndex..<sheet.count {
            let cells = sheet[rowIndex]
            if cells.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            dataRowCount += 1
            let rowNumber = rowIndex + 1

            switch parseRow(cells: cells, rowNumber: rowNumber, columnIndexes: headerInfo.columns) {
            case .success(let guestRow):
                validRows.append(guestRow)
            case .failure(let invalidRow):
                invalidRows.append(invalidRow)
            }
        }

        return ParseResult(validRows: validRows, invalidRows: invalidRows, totalRows: dataRowCount)
    }

    func preview(fileURL: URL, rowCount: Int) async throws -> PreviewResult {
        let parsed = try await parseFile(fileURL: fileURL)
        let rows = Array(parsed.validRows.prefix(rowCount))
        return PreviewResult(
            rows: rows,
            totalRows: parsed.validCount,
            hasMore: parsed.validCount > rowCount
        )
    }

    // MARK: - Header detection

    private struct HeaderInfo {
        let rowIndex: Int
        let columns: [String: Int]
    }

    private func detectHeader(in sheet: [[String]]) -> HeaderInfo? {
        let limit = min(Self.headerSearchLimit, sheet.count)
        for rowIndex in 0..<limit {
            let cells = sheet[rowIndex]
            var columns: [String: Int] = [:]
            for (colIndex, cell) in cells.enumerated() {
                let key = Self.normalizeHeader(cell)
                guard !key.isEmpty, let field = Self.columnMappings[key] else { continue }
                if columns[field] == nil {
                    columns[field] = colIndex
                }
            }
            if columns["name"] != nil {
                return HeaderInfo(rowIndex: rowIndex, columns: columns)
            }
        }
        return nil
    }

    // MARK: - Row parse

    private enum RowParseResult {
        case success(GuestRow)
        case failure(InvalidRow)
    }

    private func parseRow(cells: [String], rowNumber: Int, columnIndexes: [String: Int]) -> RowParseResult {
        func value(_ field: String) -> String? {
            guard let col = columnIndexes[field], col < cells.count else { return nil }
            let trimmed = cells[col].trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let name = value("name")
        let title = value("title") ?? ""
        let plate = value("plate")
        let model = value("model")
        let notes = value("notes")

        let arrivalRaw = value("arrivalMethod")?.lowercased(with: Locale(identifier: "tr_TR"))
        let arrivalMethod: ArrivalMethod
        if let arrivalRaw, arrivalRaw.contains("araç") || arrivalRaw.contains("arac") || arrivalRaw.contains("vehicle") {
            arrivalMethod = .vehicle
        } else if let arrivalRaw, arrivalRaw.contains("yaya") || arrivalRaw.contains("walk") {
            arrivalMethod = .pedestrian
        } else if let plate, !plate.isEmpty {
            arrivalMethod = .vehicle
        } else {
            arrivalMethod = .pedestrian
        }

        guard let name else {
            var raw: [String: String] = [:]
            for (field, col) in columnIndexes where col < cells.count {
                raw[field] = cells[col]
            }
            return .failure(InvalidRow(
                rowNumber: rowNumber,
                errors: [ValidationError(field: "name", message: "Ad Soyad eksik")],
                rawData: raw
            ))
        }

        return .success(GuestRow(
            rowNumber: rowNumber,
            name: name,
            title: title,
            plate: plate,
            model: model,
            arrivalMethod: arrivalMethod,
            notes: notes
        ))
    }

    // MARK: - Normalizasyon

    static func normalizeHeader(_ value: String) -> String {
        var result = value.lowercased(with: Locale(identifier: "tr_TR"))
        let replacements: [Character: Character] = [
            "ı": "i", "ş": "s", "ğ": "g", "ü": "u", "ö": "o", "ç": "c",
        ]
        result = String(result.map { replacements[$0] ?? $0 })
        result = result.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "/", with: "")
        return result
    }
}
