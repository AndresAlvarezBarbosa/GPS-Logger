import SwiftUI
import MapKit
import UniformTypeIdentifiers

// MARK: - Root

struct ContentView: View {
    @StateObject private var viewModel = GeoTagViewModel()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(viewModel: viewModel)
                .frame(width: 300)
            Divider()
            MapContentView(viewModel: viewModel)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var viewModel: GeoTagViewModel
    @State private var gpxTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            headerRow

            Divider()

            // GPX drop zone + Image import side by side
            HStack(spacing: 10) {
                GPXDropZone(viewModel: viewModel, isTargeted: $gpxTargeted)
                ImageImportCard(viewModel: viewModel)
            }
            .frame(height: 90)

            // Time-offset row (corrects camera-clock vs GPX UTC mismatch)
            timeOffsetRow

            // Primary action
            Button {
                Task { viewModel.tagImages() }
            } label: {
                Group {
                    if viewModel.isTagging {
                        Label("Tagging…", systemImage: "ellipsis")
                    } else {
                        Label("Geotag Images", systemImage: "tag.fill")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.images.isEmpty || viewModel.trackPoints.isEmpty || viewModel.isTagging)

            // Image list
            ImageListView(images: viewModel.images)

            // Status
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Export
            Button(action: exportImages) {
                Label("Export Tagged Images", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.taggedImages.isEmpty)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    private var headerRow: some View {
        HStack {
            Label("GPS Logger", systemImage: "mappin.and.ellipse")
                .font(.headline)
            Spacer()
            if !viewModel.trackPoints.isEmpty || !viewModel.images.isEmpty {
                Button { viewModel.clearAll() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear all data")
            }
        }
    }

    // Camera clocks often store local time; GPX stores UTC. Adjust here.
    private var timeOffsetRow: some View {
        HStack {
            Image(systemName: "clock.arrow.2.circlepath")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Time offset")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(value: $viewModel.timeOffsetHours, in: -24...24) {
                Text(viewModel.timeOffsetHours >= 0
                     ? "+\(viewModel.timeOffsetHours)h"
                     : "\(viewModel.timeOffsetHours)h")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(minWidth: 32, alignment: .trailing)
            }
            .onChange(of: viewModel.timeOffsetHours) {
                viewModel.matchImages()
            }
        }
    }

    private func exportImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder to save the geotagged images"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.exportImages(to: url)
        }
    }
}

// MARK: - GPX Drop Zone

struct GPXDropZone: View {
    @ObservedObject var viewModel: GeoTagViewModel
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: viewModel.trackPoints.isEmpty
                  ? "arrow.down.doc.fill"
                  : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(viewModel.trackPoints.isEmpty
                    ? (isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    : AnyShapeStyle(Color.green))

            Text(viewModel.trackPoints.isEmpty
                 ? (isTargeted ? "Drop GPX" : ".gpx file")
                 : "\(viewModel.trackPoints.count) pts")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !viewModel.gpxFilename.isEmpty {
                Text(viewModel.gpxFilename)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : .clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                    guard let url = item as? URL,
                          url.pathExtension.lowercased() == "gpx" else { return }
                    Task { @MainActor in viewModel.loadGPX(from: url) }
                }
            }
            return true
        }
    }
}

// MARK: - Image Import Card

struct ImageImportCard: View {
    @ObservedObject var viewModel: GeoTagViewModel

    var body: some View {
        Button(action: importImages) {
            VStack(spacing: 5) {
                Image(systemName: viewModel.images.isEmpty
                      ? "photo.badge.plus.fill"
                      : "photo.stack.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.images.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))

                Text(viewModel.images.isEmpty
                     ? "Add Images"
                     : "\(viewModel.images.count) images")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .glassEffect(in: .rect(cornerRadius: 12))
    }

    private func importImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .tiff, .rawImage]
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        panel.message = "Select images to geotag"
        if panel.runModal() == .OK {
            viewModel.importImages(urls: panel.urls)
        }
    }
}

// MARK: - Image List

struct ImageListView: View {
    let images: [ImageItem]

    var body: some View {
        Group {
            if images.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No images yet")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Text("Drop a .gpx file, then add images")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(images) { image in
                            ImageRowView(image: image)
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 2)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct ImageRowView: View {
    let image: ImageItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: image.status.icon)
                .foregroundStyle(image.status.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(image.filename)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let coord = image.matchedCoordinate {
                    Text(String(format: "%.5f°, %.5f°", coord.latitude, coord.longitude))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let date = image.captureDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No EXIF date")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(image.status.label)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(image.status.color.opacity(0.12), in: Capsule())
                .foregroundStyle(image.status.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Map

struct MapContentView: View {
    @ObservedObject var viewModel: GeoTagViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $cameraPosition) {
            if !viewModel.trackCoordinates.isEmpty {
                MapPolyline(coordinates: viewModel.trackCoordinates)
                    .stroke(.orange, lineWidth: 3)
            }

            ForEach(viewModel.geoImages) { geo in
                Marker(geo.filename, systemImage: "camera.fill", coordinate: geo.coordinate)
                    .tint(geo.isTagged ? .blue : .green)
            }
        }
        .mapStyle(.standard)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapZoomStepper()
        }
        .onChange(of: viewModel.mapFocusCounter) {
            guard let region = viewModel.mapFocusRegion else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .region(region)
            }
        }
    }
}

#Preview {
    ContentView()
}
