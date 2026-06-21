import Foundation
import Observation
import os.log
import UniformTypeIdentifiers

/// Excel içe aktarma ekranı koordinatörü (Android `ExcelImportViewModel`).
@MainActor
@Observable
final class ExcelImportViewModel {

    private static let logger = Logger(subsystem: "com.checkingcbguests", category: "ExcelImportViewModel")

    /// `.fileImporter` için izin verilen Excel türleri.
    static var allowedDocumentTypes: [UTType] {
        [UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls")]
            .compactMap { $0 }
    }

    private let validateExcelFileUseCase: any ValidateExcelFileUseCase
    private let parseExcelFileUseCase: any ParseExcelFileUseCase
    private let importGuestsFromExcelUseCase: any ImportGuestsFromExcelUseCase
    private let autoSyncManager: AutoSyncManager?

    private var importTask: Task<Void, Never>?

    // MARK: - UI state (Android `ExcelImportUiState`)

    private(set) var isLoading = false
    private(set) var isImporting = false

    private(set) var selectedFileURL: URL?
    private(set) var fileName: String?
    private(set) var fileSize: Int64 = 0

    private(set) var validationResult: FileValidationResult?
    private(set) var parseResult: ParseResult?
    private(set) var previewResult: PreviewResult?
    private(set) var importProgress: ImportProgress?
    private(set) var importResult: ImportResult?

    private(set) var errorMessage: String?

    init(
        validateExcelFileUseCase: any ValidateExcelFileUseCase,
        parseExcelFileUseCase: any ParseExcelFileUseCase,
        importGuestsFromExcelUseCase: any ImportGuestsFromExcelUseCase,
        autoSyncManager: AutoSyncManager? = nil
    ) {
        self.validateExcelFileUseCase = validateExcelFileUseCase
        self.parseExcelFileUseCase = parseExcelFileUseCase
        self.importGuestsFromExcelUseCase = importGuestsFromExcelUseCase
        self.autoSyncManager = autoSyncManager
    }

    // MARK: - File selection

    /// Dosya seçiciden gelen URL (ör. `.fileImporter`).
    func onFileSelected(_ url: URL) {
        importTask?.cancel()
        importTask = Task { await validateAndPrepareFile(url: url) }
    }

    /// Metadata okuma, güvenlik kapsamı ve format doğrulaması.
    func validateAndPrepareFile(url: URL) async {
        selectedFileURL = url
        isLoading = true
        errorMessage = nil
        parseResult = nil
        previewResult = nil
        importResult = nil
        importProgress = nil
        validationResult = nil

        guard url.startAccessingSecurityScopedResource() else {
            isLoading = false
            errorMessage = "Dosyaya erişim izni alınamadı."
            validationResult = .error(
                message: "Dosyaya erişim izni alınamadı.",
                errorType: .permissionDenied
            )
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let resolvedName = Self.getFileName(from: url)
        let resolvedSize = Self.getFileSize(from: url)

        fileName = resolvedName
        fileSize = resolvedSize

        let validation = await validateExcelFileUseCase.execute(fileURL: url)
        validationResult = validation
        isLoading = false

        if case .success = validation {
            await parseExcelFile()
        } else if case .error(let message, let errorType) = validation {
            errorMessage = Self.userFacingValidationMessage(message: message, errorType: errorType)
        }
    }

    /// Tam parse + ilk N satır önizlemesi.
    func parseExcelFile() async {
        guard let url = selectedFileURL else {
            errorMessage = "Lütfen önce bir dosya seçin."
            return
        }

        isLoading = true

        guard url.startAccessingSecurityScopedResource() else {
            isLoading = false
            errorMessage = "Dosyaya erişim izni alınamadı."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let parsed = try await parseExcelFileUseCase.execute(fileURL: url)
            let preview = try await parseExcelFileUseCase.preview(
                fileURL: url,
                rowCount: ExcelImportConstants.previewRowCount
            )
            parseResult = parsed
            previewResult = preview
            isLoading = false
        } catch {
            Self.logger.error("Parse error: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            errorMessage = Self.parseErrorMessage(for: error)
        }
    }

    // MARK: - Import

    /// İçe aktarmayı başlatır (Android `startImport`).
    func executeImport(eventId: String) {
        guard let url = selectedFileURL else {
            errorMessage = "Lütfen önce bir dosya seçin"
            return
        }

        guard NetworkMonitor.shared.isConnected else {
            errorMessage = "İnternet bağlantısı gerekli. Lütfen bağlantınızı kontrol edin."
            return
        }

        importTask?.cancel()
        importTask = Task { await runImport(fileURL: url, eventId: eventId) }
    }

    private func runImport(fileURL url: URL, eventId: String) async {
        isImporting = true
        importProgress = ImportProgress(currentRow: 0, totalRows: 0, percentage: 0)
        importResult = nil
        errorMessage = nil

        guard url.startAccessingSecurityScopedResource() else {
            isImporting = false
            errorMessage = "Dosyaya erişim izni alınamadı."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let result = try await importGuestsFromExcelUseCase.execute(
                fileURL: url,
                eventId: eventId,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.importProgress = progress
                    }
                }
            )
            isImporting = false
            importResult = result
            if result.successCount > 0 || result.redListHits > 0 {
                autoSyncManager?.requestSync()
            }
        } catch {
            Self.logger.error("Import critical error: \(error.localizedDescription, privacy: .public)")
            isImporting = false
            errorMessage = "Import işlemi durduruldu: \(error.localizedDescription)"
        }
    }

    // MARK: - Reset

    func clearState() {
        importTask?.cancel()
        importTask = nil
        isLoading = false
        isImporting = false
        selectedFileURL = nil
        fileName = nil
        fileSize = 0
        validationResult = nil
        parseResult = nil
        previewResult = nil
        importProgress = nil
        importResult = nil
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - File metadata (iOS sandbox)

    static func getFileName(from url: URL) -> String {
        url.lastPathComponent
    }

    static func getFileSize(from url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values.fileSize ?? 0)
        } catch {
            logger.warning("Could not read file size: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    // MARK: - Error mapping

    private static func userFacingValidationMessage(
        message: String,
        errorType: FileValidationErrorType
    ) -> String {
        switch errorType {
        case .fileNotFound:
            return message.isEmpty ? "Dosya bulunamadı." : message
        case .invalidFormat:
            return message.isEmpty ? "Geçersiz format. .xlsx veya .xls gerekli." : message
        case .fileTooLarge:
            return message.isEmpty ? "Dosya çok büyük." : message
        case .fileCorrupted:
            return message.isEmpty ? "Dosya bozuk veya okunamıyor." : message
        case .permissionDenied:
            return message.isEmpty ? "Dosyaya erişim izni reddedildi." : message
        }
    }

    private static func parseErrorMessage(for error: Error) -> String {
        let description = error.localizedDescription
        if description.isEmpty {
            return "Dosya okuma hatası: Bilinmeyen hata"
        }
        return "Dosya okuma hatası: \(description)"
    }
}
