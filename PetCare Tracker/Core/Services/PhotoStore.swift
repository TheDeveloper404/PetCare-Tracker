import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated final class PhotoStore: Sendable {
    let directory: URL
    static let maximumPixels = 100_000_000
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }
    func url(for name: String?) -> URL? {
        guard let name, name == URL(fileURLWithPath: name).lastPathComponent,
              UUID(uuidString: String(name.dropLast(4))) != nil, name.hasSuffix(".jpg") else { return nil }
        return directory.appendingPathComponent(name)
    }
    /// Downsamples before decoding so a full-resolution camera image is not retained in memory.
    func save(_ data: Data) throws -> String {
        // Declared dimensions are checked before decoding so a small file cannot expand into a huge bitmap.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= Self.maximumPixels / height,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw CareError.photo }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw CareError.photo }
        // Re-encoding also strips original location/EXIF metadata.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CareError.photo }
        let name = UUID().uuidString + ".jpg"
        do { try (output as Data).write(to: url(for: name)!, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { throw CareError.photo }
        return name
    }
    func remove(_ name: String) { if let url = url(for: name) { try? FileManager.default.removeItem(at: url) } }
    func data(for name: String?) throws -> Data? {
        guard let name else { return nil }
        guard let url = url(for: name) else { throw CareError.photo }
        return try Data(contentsOf: url)
    }
}
