import MapKit
import SwiftUI

/// Map selection, camera, and the click → teleport flow.
@MainActor
final class PhantomModel: ObservableObject {
    @Published var pin: SavedPlace?
    @Published var camera: MapCameraPosition = .automatic
    @Published private(set) var isTeleporting = false
    @Published var showActivity = false
    /// Last settled map region, for the zoom buttons. Not published: it changes on every pan.
    var visibleRegion: MKCoordinateRegion?
    var hasCenteredOnDevice = false

    private let bridge: DeviceBridge
    private let recents: RecentPlaces
    private var nameLookup: Task<Void, Never>?
    private var teleportsInFlight = 0

    init(bridge: DeviceBridge, recents: RecentPlaces) {
        self.bridge = bridge
        self.recents = recents
        // Start from a fixed region, never `.automatic`: an automatic camera re-fits to the map's
        // content, so the first pin dropped would zoom all the way into a single building.
        let start = recents.places.first.map {
            MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        } ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30, longitude: -40),
            span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 200)
        )
        camera = .region(start)
        visibleRegion = start
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

    /// Zooms around the visible centre; a factor below 1 zooms in.
    func zoom(by factor: Double) {
        guard let region = visibleRegion else { return }
        let span = MKCoordinateSpan(
            latitudeDelta: min(max(region.span.latitudeDelta * factor, 0.0005), 150),
            longitudeDelta: min(max(region.span.longitudeDelta * factor, 0.0005), 300)
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            camera = .region(MKCoordinateRegion(center: region.center, span: span))
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
        nameLookup?.cancel()
        nameLookup = Task { [weak self] in
            let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
            guard let request = MKReverseGeocodingRequest(location: location),
                  let items = try? await request.mapItems,
                  let name = items.first.flatMap(Self.describe),
                  !Task.isCancelled,
                  let self
            else { return }
            if pin?.id == place.id { pin?.name = name }
            recents.rename(place.id, to: name)
        }
    }

    private static func describe(_ item: MKMapItem) -> String? {
        let name = item.name?.trimmingCharacters(in: .whitespaces)
        let address = item.address?.shortAddress ?? item.address?.fullAddress
        switch (name, address) {
        case let (name?, address?) where !name.isEmpty && !address.contains(name):
            return "\(name), \(address)"
        case let (name?, _) where !name.isEmpty:
            return name
        default:
            return address
        }
    }
}
