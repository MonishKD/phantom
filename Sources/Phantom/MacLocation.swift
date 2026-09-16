import CoreLocation

/// This Mac's own position. A device plugged into the Mac, or on its network, is right next to it,
/// so this is the best stand-in for where the device really is.
@MainActor
final class MacLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiters: [UUID: CheckedContinuation<CLLocation?, Never>] = [:]

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Asks for permission ahead of the first restore, so the prompt never holds one up.
    func prepare() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// A recent fix, or nil when Location Services are off, permission is denied, or nothing arrives in time.
    func current(timeout: Duration = .seconds(10)) async -> CLLocation? {
        if let cached = manager.location, -cached.timestamp.timeIntervalSinceNow < 300 {
            return cached
        }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()  // the delegate asks for a fix once allowed
        default:
            manager.requestLocation()
        }
        return await withCheckedContinuation { continuation in
            let id = UUID()
            waiters[id] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.waiters.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        MainActor.assumeIsolated { finish(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // "Location unknown" is transient and the timeout covers it; anything else won't resolve by waiting.
        guard (error as? CLError)?.code != .locationUnknown else { return }
        MainActor.assumeIsolated { finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard !waiters.isEmpty else { return }
            switch status {
            case .denied, .restricted: finish(nil)
            case .notDetermined: break
            default: self.manager.requestLocation()
            }
        }
    }
}
