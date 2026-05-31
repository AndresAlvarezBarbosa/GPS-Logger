import Foundation
import CoreLocation

enum GPXParser {
    static func parse(url: URL) -> [GPXTrackPoint] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return [] }
        let delegate = GPXXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.points.sorted { $0.timestamp < $1.timestamp }
    }
}

private class GPXXMLDelegate: NSObject, XMLParserDelegate {
    var points: [GPXTrackPoint] = []
    private var pendingLat: Double?
    private var pendingLon: Double?
    private var currentElement = ""
    private var currentText = ""
    private let iso8601 = ISO8601DateFormatter()

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        currentElement = element
        currentText = ""
        if element == "trkpt" || element == "wpt" || element == "rtept" {
            pendingLat = attributes["lat"].flatMap(Double.init)
            pendingLon = attributes["lon"].flatMap(Double.init)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        if currentElement == "time", let lat = pendingLat, let lon = pendingLon {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = iso8601.date(from: text) {
                points.append(GPXTrackPoint(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    timestamp: date
                ))
            }
        }
        if element == "trkpt" || element == "wpt" || element == "rtept" {
            pendingLat = nil
            pendingLon = nil
        }
        currentElement = ""
    }
}
