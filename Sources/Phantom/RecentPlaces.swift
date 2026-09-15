import CoreLocation
import Foundation

struct SavedPlace: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// The most recent places the device was moved to, persisted in UserDefaults.
@MainActor
final class RecentPlaces: ObservableObject {
    @Published private(set) var places: [SavedPlace] = []

    private let storageKey = "recentPlaces"
    private let limit = 15

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            places = saved
        }
    }

    func record(_ place: SavedPlace) {
        places.removeAll { $0.id == place.id || $0.coordinate.distance(to: place.coordinate) < 30 }
        places.insert(place, at: 0)
        if places.count > limit { places.removeLast(places.count - limit) }
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        places[index].name = name
        save()
    }

    func remove(_ place: SavedPlace) {
        places.removeAll { $0.id == place.id }
        save()
    }

    func clear() {
        places.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
