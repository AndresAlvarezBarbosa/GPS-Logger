import Foundation
import ImageIO
import CoreLocation

enum ImageGeoTagger {
    enum ImageGeoTaggerError: Error, LocalizedError {
        case securityScopedAccessFailed(URL)
        case cannotCreateImageSource(URL)
        case cannotReadImageProperties(URL)
        case unsupportedImageType(URL)
        case missingCaptureDate(URL)
        case invalidDateFormat(String, URL)
        case cannotCreateImageDestination(URL)
        case imageWriteFailed(URL)
        case fileReplaceFailed(URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .securityScopedAccessFailed(let url):
                return "Unable to access file: \(url.path)"
            case .cannotCreateImageSource(let url):
                return "Unable to create an image source for file: \(url.path)"
            case .cannotReadImageProperties(let url):
                return "Unable to read image metadata from: \(url.path)"
            case .unsupportedImageType(let url):
                return "Unsupported image type for file: \(url.path)"
            case .missingCaptureDate(let url):
                return "No capture date metadata found in: \(url.path)"
            case .invalidDateFormat(let raw, let url):
                return "Invalid capture date format '\(raw)' in: \(url.path)"
            case .cannotCreateImageDestination(let url):
                return "Unable to create a temporary image destination for: \(url.path)"
            case .imageWriteFailed(let url):
                return "Unable to write GPS metadata to temporary file for: \(url.path)"
            case .fileReplaceFailed(let url, let underlying):
                return "Unable to replace original file at \(url.path): \(underlying.localizedDescription)"
            }
        }
    }

    /// Reads the original capture date from image EXIF/TIFF metadata.
    static func captureDate(from url: URL) throws -> Date {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageGeoTaggerError.cannotCreateImageSource(url)
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ImageGeoTaggerError.cannotReadImageProperties(url)
        }

        let possibleDates: [String?] = [
            (properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String,
            (properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeDigitized] as? String,
            (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFDateTime] as? String,
        ]

        guard let rawDate = possibleDates.compactMap({ $0 }).first else {
            throw ImageGeoTaggerError.missingCaptureDate(url)
        }

        guard let parsedDate = parseDate(from: rawDate) else {
            throw ImageGeoTaggerError.invalidDateFormat(rawDate, url)
        }

        return parsedDate
    }

    /// Writes GPS coordinates into an image while preserving existing metadata.
    static func writeGPS(to url: URL, coordinate: CLLocationCoordinate2D) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageGeoTaggerError.cannotCreateImageSource(url)
        }

        guard let uti = CGImageSourceGetType(source) else {
            throw ImageGeoTaggerError.unsupportedImageType(url)
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ImageGeoTaggerError.cannotReadImageProperties(url)
        }

        var metadata = properties
        var gpsMetadata = (properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]) ?? [:]
        gpsMetadata[kCGImagePropertyGPSLatitude] = abs(coordinate.latitude)
        gpsMetadata[kCGImagePropertyGPSLatitudeRef] = coordinate.latitude >= 0 ? "N" : "S"
        gpsMetadata[kCGImagePropertyGPSLongitude] = abs(coordinate.longitude)
        gpsMetadata[kCGImagePropertyGPSLongitudeRef] = coordinate.longitude >= 0 ? "E" : "W"
        metadata[kCGImagePropertyGPSDictionary] = gpsMetadata

        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(".geotagtmp_\(url.lastPathComponent)")

        guard let destination = CGImageDestinationCreateWithURL(tmpURL as CFURL, uti, 1, nil) else {
            throw ImageGeoTaggerError.cannotCreateImageDestination(url)
        }

        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw ImageGeoTaggerError.imageWriteFailed(url)
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw ImageGeoTaggerError.fileReplaceFailed(url, underlying: error)
        }
    }

    // MARK: - Helpers

    private static func parseDate(from rawString: String) -> Date? {
        let dateFormats = [
            "yyyy:MM:dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss"
        ]

        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: rawString) {
                return date
            }
        }

        return nil
    }
}
