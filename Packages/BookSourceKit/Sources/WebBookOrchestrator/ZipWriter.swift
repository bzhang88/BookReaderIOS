import Foundation

/// Standard CRC-32 (IEEE 802.3 / zlib polynomial, `0xEDB88320`) -- the checksum every ZIP local file
/// header and central directory entry must carry. Implemented directly rather than reaching for
/// `zlib`/`Compression` so `ZipWriter` has zero platform-specific dependencies and is fully testable
/// on Windows (this whole export path never touches an Apple-only API).
enum CRC32 {
    private static let table: [UInt32] = (0...255).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

/// Minimal ZIP archive writer -- STORE (uncompressed) entries only, no DEFLATE. This exists to build
/// EPUB files: an EPUB reader only requires a spec-valid ZIP container with "mimetype" as the first,
/// uncompressed entry -- nothing requires the *rest* of the archive to also be compressed, so skipping
/// DEFLATE entirely (bigger files, but far simpler and lower-risk to get right) is a deliberate
/// trade-off, not a missing feature. Also means this stays pure Foundation + arithmetic -- no
/// `Compression`/`AppleArchive` (both Apple-only, and neither actually produces the PKZIP container
/// format EPUB readers expect anyway), so it's real code this project can unit-test on Windows instead
/// of writing blind like the rest of this session's SwiftUI/UIKit work.
struct ZipWriter {
    private struct Entry {
        let name: String
        let size: UInt32
        let crc32: UInt32
        let offset: UInt32
    }

    private var entries: [Entry] = []
    private(set) var archive = Data()

    mutating func addEntry(name: String, data: Data) {
        let offset = UInt32(archive.count)
        let crc = CRC32.checksum(data)
        archive.append(Self.localFileHeader(name: name, size: UInt32(data.count), crc32: crc))
        archive.append(data)
        entries.append(Entry(name: name, size: UInt32(data.count), crc32: crc, offset: offset))
    }

    /// Appends the central directory + end-of-central-directory record and returns the complete
    /// archive. Only valid to call once -- `addEntry` after this would leave the recorded offsets
    /// pointing at stale positions.
    mutating func finalize() -> Data {
        let centralDirStart = UInt32(archive.count)
        for entry in entries {
            archive.append(Self.centralDirectoryHeader(entry: entry))
        }
        let centralDirSize = UInt32(archive.count) - centralDirStart
        archive.append(Self.endOfCentralDirectory(
            entryCount: entries.count, centralDirSize: centralDirSize, centralDirStart: centralDirStart
        ))
        return archive
    }

    private static func localFileHeader(name: String, size: UInt32, crc32: UInt32) -> Data {
        let nameData = Data(name.utf8)
        var header = Data()
        header.appendLE(UInt32(0x04034b50))
        header.appendLE(UInt16(20))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(crc32)
        header.appendLE(size)
        header.appendLE(size)
        header.appendLE(UInt16(nameData.count))
        header.appendLE(UInt16(0))
        header.append(nameData)
        return header
    }

    private static func centralDirectoryHeader(entry: Entry) -> Data {
        let nameData = Data(entry.name.utf8)
        var header = Data()
        header.appendLE(UInt32(0x02014b50))
        header.appendLE(UInt16(20))
        header.appendLE(UInt16(20))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(entry.crc32)
        header.appendLE(entry.size)
        header.appendLE(entry.size)
        header.appendLE(UInt16(nameData.count))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt32(0))
        header.appendLE(entry.offset)
        header.append(nameData)
        return header
    }

    private static func endOfCentralDirectory(entryCount: Int, centralDirSize: UInt32, centralDirStart: UInt32) -> Data {
        var footer = Data()
        footer.appendLE(UInt32(0x06054b50))
        footer.appendLE(UInt16(0))
        footer.appendLE(UInt16(0))
        footer.appendLE(UInt16(entryCount))
        footer.appendLE(UInt16(entryCount))
        footer.appendLE(centralDirSize)
        footer.appendLE(centralDirStart)
        footer.appendLE(UInt16(0))
        return footer
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
