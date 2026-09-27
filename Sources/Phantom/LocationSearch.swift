import MapKit

/// Place search via MKLocalSearchCompleter, plus "lat, lon" parsing for pasted coordinates.
@MainActor
final class LocationSearch: NSObject, ObservableObject {
    @Published var query = "" {
        didSet { queryChanged() }
    }
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var typedCoordinate: CLLocationCoordinate2D?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func clear() {
        query = ""
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> (coordinate: CLLocationCoordinate2D, name: String)? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first
        else { return nil }
        return (item.location.coordinate, item.name ?? item.address?.shortAddress ?? completion.title)
    }

    private func queryChanged() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        typedCoordinate = Self.parseCoordinate(text)
        if text.isEmpty {
            completer.cancel()
            completions = []
        } else {
            completer.queryFragment = text
        }
    }

    /// Accepts decimal degrees such as "48.8584, 2.2945" or "48.8584 2.2945".
    nonisolated static func parseCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let tokens = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
        guard tokens.count == 2,
              let latitude = Double(tokens[0]), let longitude = Double(tokens[1]),
              (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude)
        else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension LocationSearch: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            self.completions = Array(completer.results.prefix(8))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            self.completions = []
        }
    }
}
