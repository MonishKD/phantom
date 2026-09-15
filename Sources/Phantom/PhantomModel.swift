import MapKit
import SwiftUI

/// Map selection, camera, and the click → teleport flow.
@MainActor
final class PhantomModel: ObservableObject {
    @Published var pin: SavedPlace?
    @Published var camera: MapCameraPosition = .automatic
    @Published private(set) var isTeleporting = false
    @Published var showActivity = false

    private let bridge: DeviceBridge
    private let recents: RecentPlaces
    private let geocoder = CLGeocoder()
    private var teleportsInFlight = 0

    init(bridge: DeviceBridge, recents: RecentPlaces) {
        self.bridge = bridge
        self.recents = recents
    }

    /// Drops the pin at `coordinate` and, if asked, moves the device there right away.
    func choose(_ coordinate: CLLocationCoordinate2D, name: String? = nil, teleport: Bool, flyTo: Bool) {
        let place = SavedPlace(name: name ?? coordinate.formatted, latitude: coordinate.latitude, longitude: coordinate.longitude)
        pin = place
        if flyTo { fly(to: coordinate) }
        if name == nil { resolveName(for: place) }
        if teleport {
            Task { await self.teleport(to: place) }
        }
    }

    func teleportToPin() {
        guard let pin else { return }
        Task { await teleport(to: pin) }
    }

    func fly(to coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))
        }
    }

    private func teleport(to place: SavedPlace) async {
        teleportsInFlight += 1
        isTeleporting = true
        defer {
            teleportsInFlight -= 1
            isTeleporting = teleportsInFlight > 0
        }
        guard await bridge.teleport(to: place.coordinate) else { return }
        // The pin may have picked up a street name while the device call was in flight.
        if let pin, pin.id == place.id {
            recents.record(pin)
        } else {
            recents.record(place)
        }
    }

    private func resolveName(for place: SavedPlace) {
        geocoder.cancelGeocode()
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let placemark = placemarks?.first, let name = Self.describe(placemark) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.pin?.id == place.id { self.pin?.name = name }
                    self.recents.rename(place.id, to: name)
                }
            }
        }
    }

    nonisolated private static func describe(_ placemark: CLPlacemark) -> String? {
        var parts: [String] = []
        for part in [placemark.name, placemark.locality, placemark.country] {
            if let part, !part.isEmpty, !parts.contains(part) { parts.append(part) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
