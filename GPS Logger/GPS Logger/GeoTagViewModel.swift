import Foundation
import Combine
import MapKit
import SwiftUI

// MARK: - Support types

struct GPXTrackPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
}

enum TagStatus {
    case pending, matched, tagged, noMatch

    var label: String {
        switch self {
        case .pending: "Pending"
        case .matched: "Matched"
        case .tagged: "Tagged"
        case .noMatch: "No Match"
        }
    }

    var color: Color {
        switch self {
        case .pending: .secondary
        case .matched: .green
        case .tagged: .blue
        case .noMatch: .orange
        }
    }

    var icon: String {
        switch self {
        case .pending: "clock"
        case .matched: "location.fill"
        case .tagged: "checkmark.circle.fill"
        case .noMatch: "exclamationmark.triangle"
        }
    }
}

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
    let captureDate: Date?
    var matchedCoordinate: CLLocationCoordinate2D?
    var status: TagStatus = .pending
}

/// Flat struct for MapKit annotations — avoids optional coordinate in map content.
struct GeoImage: Identifiable {
    let id: UUID
    let filename: String
    let coordinate: CLLocationCoordinate2D
    let isTagged: Bool
}

// MARK: - ViewModel

@MainActor
class GeoTagViewModel: ObservableObject {
    @Published var trackPoints: [GPXTrackPoint] = []
    @Published var images: [ImageItem] = []
    @Published var isTagging = false
    @Published var statusMessage = ""
    @Published var gpxFilename = ""
    @Published var timeOffsetHours: Int = 0

    // Used to trigger animated camera fly-to without requiring MKCoordinateRegion: Equatable.
    @Published var mapFocusCounter: Int = 0
    private(set) var mapFocusRegion: MKCoordinateRegion? = nil

    var trackCoordinates: [CLLocationCoordinate2D] {
        trackPoints.map(\.coordinate)
    }

    var taggedImages: [ImageItem] {
        images.filter { $0.status == .tagged }
    }

    var geoImages: [GeoImage] {
        images.compactMap { item in
            guard let coord = item.matchedCoordinate else { return nil }
            return GeoImage(id: item.id, filename: item.filename,
                            coordinate: coord, isTagged: item.status == .tagged)
        }
    }

    func loadGPX(from url: URL) {
        let points = GPXParser.parse(url: url)
        trackPoints = points
        gpxFilename = url.lastPathComponent
        statusMessage = "Loaded \(points.count) track points"
        matchImages()
        fitMapToTrack()
    }

    func importImages(urls: [URL]) {
        let newItems = urls.compactMap { url -> ImageItem? in
            guard !images.contains(where: { $0.url == url }) else { return nil }
            return ImageItem(url: url, filename: url.lastPathComponent,
                             captureDate: ImageGeoTagger.captureDate(from: url))
        }
        images.append(contentsOf: newItems)
        statusMessage = "Imported \(newItems.count) images (\(images.count) total)"
        matchImages()
    }

    func matchImages() {
        guard !trackPoints.isEmpty else { return }
        let offsetSeconds = TimeInterval(timeOffsetHours * 3600)
        for i in images.indices {
            guard let date = images[i].captureDate else {
                images[i].status = .noMatch
                continue
            }
            let adjusted = date.addingTimeInterval(offsetSeconds)
            if let nearest = nearestPoint(to: adjusted) {
                images[i].matchedCoordinate = nearest.coordinate
                images[i].status = images[i].status == .tagged ? .tagged : .matched
            } else {
                images[i].matchedCoordinate = nil
                images[i].status = .noMatch
            }
        }
    }

    func tagImages() {
        isTagging = true
        var tagged = 0
        for i in images.indices {
            guard images[i].status == .matched,
                  let coord = images[i].matchedCoordinate else { continue }
            if ImageGeoTagger.writeGPS(to: images[i].url, coordinate: coord) {
                images[i].status = .tagged
                tagged += 1
            }
        }
        statusMessage = "Tagged \(tagged) of \(images.count) images"
        isTagging = false
    }

    func exportImages(to directory: URL) {
        var exported = 0
        for item in taggedImages {
            let dest = directory.appendingPathComponent(item.filename)
            try? FileManager.default.copyItem(at: item.url, to: dest)
            exported += 1
        }
        statusMessage = "Exported \(exported) images to \(directory.lastPathComponent)/"
    }

    func clearAll() {
        trackPoints = []
        images = []
        gpxFilename = ""
        statusMessage = ""
        mapFocusRegion = nil
        mapFocusCounter = 0
    }

    // MARK: - Private

    private func nearestPoint(to date: Date) -> GPXTrackPoint? {
        let maxDelta: TimeInterval = 7200
        guard let nearest = trackPoints.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }) else { return nil }
        return abs(nearest.timestamp.timeIntervalSince(date)) <= maxDelta ? nearest : nil
    }

    private func fitMapToTrack() {
        guard !trackPoints.isEmpty else { return }
        let lats = trackCoordinates.map(\.latitude)
        let lons = trackCoordinates.map(\.longitude)
        mapFocusRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (lats.min()! + lats.max()!) / 2,
                longitude: (lons.min()! + lons.max()!) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.02),
                longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.02)
            )
        )
        mapFocusCounter += 1
    }
}
