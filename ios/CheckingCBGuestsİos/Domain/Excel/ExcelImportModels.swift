import Foundation

// MARK: - Import result

struct ImportResult: Equatable, Sendable {
    let successCount: Int
    let errorCount: Int
    let redListHits: Int
    let errors: [ImportError]
    let skippedRows: [Int]

    init(
        successCount: Int,
        errorCount: Int,
        redListHits: Int = 0,
        errors: [ImportError],
        skippedRows: [Int] = []
    ) {
        self.successCount = successCount
        self.errorCount = errorCount
        self.redListHits = redListHits
        self.errors = errors
        self.skippedRows = skippedRows
    }

    var totalProcessed: Int {
        successCount + errorCount + redListHits
    }

    var successRate: Float {
        totalProcessed > 0 ? Float(successCount) / Float(totalProcessed) : 0
    }
}

struct ImportError: Equatable, Sendable {
    let rowNumber: Int
    let field: String?
    let message: String
    let rawData: [String: String]?
}

// MARK: - Progress

struct ImportProgress: Equatable, Sendable {
    let currentRow: Int
    let totalRows: Int
    let percentage: Float

    static func create(current: Int, total: Int) -> ImportProgress {
        let percentage: Float = total > 0 ? (Float(current) / Float(total)) * 100 : 0
        return ImportProgress(currentRow: current, totalRows: total, percentage: percentage)
    }
}

// MARK: - Parse

struct ParseResult: Equatable, Sendable {
    let validRows: [GuestRow]
    let invalidRows: [InvalidRow]
    let totalRows: Int

    var validCount: Int { validRows.count }
    var invalidCount: Int { invalidRows.count }
}

struct GuestRow: Equatable, Sendable, Identifiable {
    var id: Int { rowNumber }
    let rowNumber: Int
    let name: String
    let title: String
    let plate: String?
    let model: String?
    let arrivalMethod: ArrivalMethod
    let notes: String?
}

struct InvalidRow: Equatable, Sendable {
    let rowNumber: Int
    let errors: [ValidationError]
    let rawData: [String: String]
}

struct ValidationError: Equatable, Sendable {
    let field: String
    let message: String
}

// MARK: - File validation

enum FileValidationResult: Equatable, Sendable {
    case success(fileName: String, fileSize: Int64)
    case error(message: String, errorType: FileValidationErrorType)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

enum FileValidationErrorType: String, Equatable, Sendable {
    case fileNotFound = "FILE_NOT_FOUND"
    case invalidFormat = "INVALID_FORMAT"
    case fileTooLarge = "FILE_TOO_LARGE"
    case fileCorrupted = "FILE_CORRUPTED"
    case permissionDenied = "PERMISSION_DENIED"
}

// MARK: - Preview

struct PreviewResult: Equatable, Sendable {
    let rows: [GuestRow]
    let totalRows: Int
    let hasMore: Bool
}

// MARK: - Constants

enum ExcelImportConstants {
    static let maxFileSizeBytes: Int64 = 10 * 1024 * 1024
    static let previewRowCount = 10
}
