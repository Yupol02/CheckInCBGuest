import Foundation

/// Excel dosyası format ve boyut doğrulaması (Android `ValidateExcelFileUseCase`).
protocol ValidateExcelFileUseCase: Sendable {
    func execute(fileURL: URL) async -> FileValidationResult
}

/// Excel dosyasını ayrıştırma ve önizleme (Android `ParseExcelFileUseCase`).
protocol ParseExcelFileUseCase: Sendable {
    func execute(fileURL: URL) async throws -> ParseResult
    func preview(fileURL: URL, rowCount: Int) async throws -> PreviewResult
}

/// Misafirleri Excel'den etkinliğe aktarma (Android `ImportGuestsFromExcelUseCase`).
protocol ImportGuestsFromExcelUseCase: Sendable {
    func execute(
        fileURL: URL,
        eventId: String,
        onProgress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> ImportResult
}
