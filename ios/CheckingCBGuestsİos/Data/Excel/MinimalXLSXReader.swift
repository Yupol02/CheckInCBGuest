import Compression
import Foundation

/// Harici bağımlılık olmadan `.xlsx` (Office Open XML) okuyan minimal ayrıştırıcı.
///
/// `.xlsx` aslında bir ZIP arşividir. Bu okuyucu ZIP merkezi dizinini elle çözer,
/// gerekli XML parçalarını Apple `Compression` (raw DEFLATE) ile açar ve
/// `XMLParser` ile sheet + sharedStrings içeriğini satır/sütun matrisine çevirir.
///
/// Sınırlamalar: ZIP64 ve eski binary `.xls` formatı desteklenmez.
struct MinimalXLSXReader {

    enum ReaderError: Error, Sendable {
        case notZipArchive
        case worksheetNotFound
        case decompressionFailed
    }

    private let bytes: [UInt8]

    init(data: Data) {
        self.bytes = [UInt8](data)
    }

    /// İlk çalışma sayfasını `[[String]]` (satır × sütun) olarak döndürür.
    func readFirstSheet() throws -> [[String]] {
        let entries = try extractEntries { name in
            name == "xl/sharedStrings.xml" || name.hasPrefix("xl/worksheets/")
        }

        let sharedStrings: [String]
        if let sharedData = entries["xl/sharedStrings.xml"] {
            sharedStrings = SharedStringsParser.parse(data: sharedData)
        } else {
            sharedStrings = []
        }

        let worksheetName = entries.keys
            .filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
            .sorted()
            .first

        guard let worksheetName, let sheetData = entries[worksheetName] else {
            throw ReaderError.worksheetNotFound
        }

        return SheetParser.parse(data: sheetData, sharedStrings: sharedStrings)
    }

    // MARK: - ZIP merkezi dizin ayrıştırma

    private func extractEntries(matching predicate: (String) -> Bool) throws -> [String: Data] {
        let n = bytes.count
        guard n >= 22 else { throw ReaderError.notZipArchive }

        // End Of Central Directory (EOCD) imzasını sondan ara: 0x06054b50
        var eocd = -1
        let minPos = max(0, n - 22 - 65_535)
        var i = n - 22
        while i >= minPos {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4b, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ReaderError.notZipArchive }

        let cdCount = u16(eocd + 10)
        let cdOffset = u32(eocd + 16)

        var result: [String: Data] = [:]
        var p = cdOffset

        for _ in 0..<cdCount {
            guard p + 46 <= n,
                  bytes[p] == 0x50, bytes[p + 1] == 0x4b, bytes[p + 2] == 0x01, bytes[p + 3] == 0x02 else {
                break
            }
            let method = u16(p + 10)
            let compSize = u32(p + 20)
            let uncompSize = u32(p + 24)
            let nameLen = u16(p + 28)
            let extraLen = u16(p + 30)
            let commentLen = u16(p + 32)
            let localOffset = u32(p + 42)
            let nameStart = p + 46

            guard nameStart + nameLen <= n else { break }
            let name = String(bytes: bytes[nameStart..<nameStart + nameLen], encoding: .utf8) ?? ""

            if predicate(name),
               let entryData = readLocalEntry(
                   localOffset: localOffset,
                   method: method,
                   compSize: compSize,
                   uncompSize: uncompSize
               ) {
                result[name] = entryData
            }

            p = nameStart + nameLen + extraLen + commentLen
        }

        return result
    }

    private func readLocalEntry(localOffset: Int, method: Int, compSize: Int, uncompSize: Int) -> Data? {
        let n = bytes.count
        let lh = localOffset
        guard lh + 30 <= n,
              bytes[lh] == 0x50, bytes[lh + 1] == 0x4b, bytes[lh + 2] == 0x03, bytes[lh + 3] == 0x04 else {
            return nil
        }
        let lNameLen = u16(lh + 26)
        let lExtraLen = u16(lh + 28)
        let dataStart = lh + 30 + lNameLen + lExtraLen
        let dataEnd = min(dataStart + compSize, n)
        guard dataStart <= dataEnd else { return nil }

        let chunk = Array(bytes[dataStart..<dataEnd])
        switch method {
        case 0:
            return Data(chunk)
        case 8:
            return inflate(chunk, expectedSize: uncompSize)
        default:
            return nil
        }
    }

    private func inflate(_ input: [UInt8], expectedSize: Int) -> Data? {
        guard !input.isEmpty else { return Data() }
        let dstCapacity = max(expectedSize, input.count * 4, 1)
        var dst = Data(count: dstCapacity)

        let written = dst.withUnsafeMutableBytes { dstRaw -> Int in
            guard let dstPtr = dstRaw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return input.withUnsafeBufferPointer { srcBuf -> Int in
                guard let srcPtr = srcBuf.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstPtr, dstCapacity,
                    srcPtr, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return dst.prefix(written)
    }

    // MARK: - Little-endian okuyucular

    private func u16(_ offset: Int) -> Int {
        Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }

    private func u32(_ offset: Int) -> Int {
        Int(bytes[offset])
            | (Int(bytes[offset + 1]) << 8)
            | (Int(bytes[offset + 2]) << 16)
            | (Int(bytes[offset + 3]) << 24)
    }
}

// MARK: - sharedStrings.xml

private final class SharedStringsParser: NSObject, XMLParserDelegate {

    static func parse(data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    private(set) var strings: [String] = []
    private var current = ""
    private var capturing = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        if elementName == "si" {
            current = ""
        } else if elementName == "t" {
            capturing = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { current += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "t" {
            capturing = false
        } else if elementName == "si" {
            strings.append(current)
            current = ""
        }
    }
}

// MARK: - worksheet xml

private final class SheetParser: NSObject, XMLParserDelegate {

    static func parse(data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = SheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    private let sharedStrings: [String]
    private(set) var rows: [[String]] = []

    private var currentRowCells: [Int: String] = [:]
    private var currentCellRef = ""
    private var currentCellType = ""
    private var currentValue = ""
    private var capturingValue = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "row":
            currentRowCells = [:]
        case "c":
            currentCellRef = attributeDict["r"] ?? ""
            currentCellType = attributeDict["t"] ?? ""
            currentValue = ""
        case "v", "t":
            capturingValue = true
            currentValue = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingValue { currentValue += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v":
            capturingValue = false
            let resolved: String
            if currentCellType == "s", let idx = Int(currentValue), idx >= 0, idx < sharedStrings.count {
                resolved = sharedStrings[idx]
            } else {
                resolved = currentValue
            }
            let col = Self.columnIndex(fromRef: currentCellRef)
            if col >= 0 { currentRowCells[col] = resolved }
        case "t":
            // inlineStr durumu: <c t="inlineStr"><is><t>...</t></is></c>
            capturingValue = false
            if currentCellType == "inlineStr" || currentCellType == "str" {
                let col = Self.columnIndex(fromRef: currentCellRef)
                if col >= 0 { currentRowCells[col] = currentValue }
            }
        case "row":
            let maxCol = currentRowCells.keys.max() ?? -1
            var rowArray = [String](repeating: "", count: maxCol + 1)
            for (col, value) in currentRowCells where col <= maxCol {
                rowArray[col] = value
            }
            rows.append(rowArray)
            currentRowCells = [:]
        default:
            break
        }
    }

    /// "B12" → 1, "AA3" → 26. Geçersizse -1.
    static func columnIndex(fromRef ref: String) -> Int {
        var result = 0
        var found = false
        for char in ref.uppercased() {
            guard let ascii = char.asciiValue, ascii >= 65, ascii <= 90 else {
                if found { break } else { continue }
            }
            found = true
            result = result * 26 + Int(ascii - 64)
        }
        return found ? result - 1 : -1
    }
}
