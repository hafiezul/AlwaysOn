import AppKit
import CoreLocation
import CoreWLAN

/// What macOS lets AlwaysOn do with Location, which it needs only to read
/// the Wi-Fi network name (macOS 14 and later hide SSIDs without it)
enum LocationAccessState: Equatable {
    case notDetermined
    case granted
    /// Denied for AlwaysOn, or Location Services are off for the whole Mac
    case denied
    /// Blocked by device policy; the user can't change it
    case restricted
}

/// Follows the Wi-Fi network name through CoreWLAN change events instead of
/// polling, and owns the Location permission that reading it requires.
/// AlwaysOn never asks for the Mac's position; Location only unlocks the SSID.
final class WiFiNetworkMonitor: NSObject, ObservableObject {
    @Published private(set) var currentNetwork: String?
    @Published private(set) var locationAccess: LocationAccessState

    /// Called on the main queue when the network name changes
    var onNetworkChange: ((String?) -> Void)?

    private let client = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    private(set) var isMonitoring = false

    override init() {
        locationAccess = .notDetermined
        super.init()
        locationManager.delegate = self
        locationAccess = Self.accessState(locationManager)
    }

    deinit {
        if isMonitoring { try? client.stopMonitoringAllEvents() }
    }

    // MARK: - Monitoring

    func setMonitoring(_ enabled: Bool) {
        guard enabled != isMonitoring else { return }
        isMonitoring = enabled
        if enabled {
            client.delegate = self
            try? client.startMonitoringEvent(with: .ssidDidChange)
            try? client.startMonitoringEvent(with: .linkDidChange)
            refreshNetwork()
        } else {
            try? client.stopMonitoringAllEvents()
            client.delegate = nil
        }
    }

    /// Reads the network name now; nil when not on Wi-Fi or Location isn't allowed
    func refreshNetwork() {
        let name = client.interface()?.ssid()
        guard name != currentNetwork else { return }
        currentNetwork = name
        onNetworkChange?(name)
    }

    // MARK: - Location permission

    /// Shows the system Location prompt when it hasn't been answered yet,
    /// or opens System Settings when it was denied
    func requestLocationAccess() {
        switch Self.accessState(locationManager) {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Some macOS versions show the prompt only once updates start;
            // updates stop as soon as the answer arrives
            locationManager.startUpdatingLocation()
        case .denied:
            Self.openLocationSettings()
        case .granted, .restricted:
            break
        }
    }

    static func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func accessState(_ manager: CLLocationManager) -> LocationAccessState {
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        // Every authorized variant (always, when in use, legacy authorized)
        default: return .granted
        }
    }
}

extension WiFiNetworkMonitor: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let state = Self.accessState(manager)
        if state != .notDetermined { manager.stopUpdatingLocation() }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.locationAccess = state
            // A new grant reveals the network name
            if self.isMonitoring { self.refreshNetwork() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Updates only ever run to trigger the prompt; the position is never used
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
    }
}

extension WiFiNetworkMonitor: CWEventDelegate {
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in self?.refreshNetwork() }
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in self?.refreshNetwork() }
    }
}
