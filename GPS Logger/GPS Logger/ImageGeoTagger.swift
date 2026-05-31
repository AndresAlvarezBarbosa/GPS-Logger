import Foundation
import ImageIO
import CoreLocation

enum ImageGeoTagger {

    /// Reads the DateTimeOriginal EXIF field from a JPEG/TIFF/RAW file.
    static func captureDate(from url: URL) -> Date? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw  = (exif?[kCGImagePropertyExifDateTimeOriginal]
                 ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String

        guard let raw else { return nil }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        fmt.timeZone = .current
        return fmt.date(from: raw)
    }

    /// Writes GPS coordinates into the image metadata without re-compressing the image.
    @discardableResult
    static func writeGPS(to url: URL, coordinate: CLLocationCoordinate2D) -> Bool {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let uti = CGImageSourceGetType(source)
        else { return false }

        let gpsData: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude:    abs(coordinate.latitude),
                kCGImagePropertyGPSLatitudeRef: coordinate.latitude  >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude:   abs(coordinate.longitude),
                kCGImagePropertyGPSLongitudeRef: coordinate.longitude >= 0 ? "E" : "W",
            ] as [CFString: Any]
        ]

        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(".geotagtmp_\(url.lastPathComponent)")

        guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, uti, 1, nil) else {
            return false
        }
        // Copies compressed image data + merges GPS metadata — no quality loss.
        CGImageDestinationAddImageFromSource(dest, source, 0, gpsData as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }
    }
}
