import SwiftUI
import UniformTypeIdentifiers

/// Excel'den misafir içe aktarma ekranı (Android `ExcelImportScreen`).
@MainActor
struct ExcelImportView: View {

    let event: Event

    @State private var viewModel: ExcelImportViewModel
    @State private var showImporter = false

    init(event: Event) {
        self.event = event
        _viewModel = State(initialValue: AppDependencies.makeExcelImportViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                fileCard

                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                if viewModel.isLoading {
                    ProgressView("Dosya okunuyor…")
                        .padding()
                }

                if let result = viewModel.importResult {
                    resultCard(result)
                } else if let parse = viewModel.parseResult {
                    previewCard(parse)
                }

                if viewModel.isImporting, let progress = viewModel.importProgress {
                    importProgressCard(progress)
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.groupedBackground)
        .navigationTitle("Excel İçe Aktar")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: ExcelImportViewModel.allowedDocumentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.onFileSelected(url)
            }
        }
        .onDisappear { viewModel.clearState() }
    }

    // MARK: - Sections

    private var fileCard: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Colors.accent)

            if let name = viewModel.fileName {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(byteString(viewModel.fileSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(".xlsx dosyası seçin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                showImporter = true
            } label: {
                Label("Dosya Seç", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.Colors.accent)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    private func previewCard(_ parse: ParseResult) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("Önizleme")
                    .font(.headline)
                Spacer()
                Text("\(parse.validCount) geçerli • \(parse.invalidCount) hatalı")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.previewResult?.rows ?? []) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.subheadline.weight(.medium))
                        if !row.title.isEmpty {
                            Text(row.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let plate = row.plate, !plate.isEmpty {
                        Text(plate).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }

            Button {
                viewModel.executeImport(eventId: event.id)
            } label: {
                Label("\(parse.validCount) Misafiri İçe Aktar", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.Colors.accent)
            .disabled(parse.validCount == 0 || viewModel.isImporting)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    private func importProgressCard(_ progress: ImportProgress) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ProgressView(value: Double(progress.percentage), total: 100)
            Text("İçe aktarılıyor: \(progress.currentRow)/\(progress.totalRows)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    private func resultCard(_ result: ImportResult) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.Colors.success)
            Text("İçe Aktarma Tamamlandı")
                .font(.headline)
            VStack(spacing: AppTheme.Spacing.xs) {
                summaryRow("Başarılı", "\(result.successCount)", color: AppTheme.Colors.success)
                if result.redListHits > 0 {
                    summaryRow("Kırmızı liste şüphesi", "\(result.redListHits)", color: AppTheme.Colors.redList)
                }
                if result.errorCount > 0 {
                    summaryRow("Hatalı satır", "\(result.errorCount)", color: AppTheme.Colors.warning)
                }
            }

            Button {
                viewModel.clearState()
            } label: {
                Text("Yeni Dosya")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    private func summaryRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color)
        }
        .font(.subheadline)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.Colors.danger)
            Text(message)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.danger.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    NavigationStack {
        ExcelImportView(event: .previewActive)
    }
}
