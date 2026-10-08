import CoreLocation
import Foundation
import SwiftUI

struct ConversationContext: Codable, Sendable {
    struct Location: Codable, Sendable {
        var latitude: Double
        var longitude: Double
        var horizontal_accuracy_meters: Double
        var captured_at: String
    }
    var captured_at: String
    var timezone: String
    var location: Location?
    var location_status: String = "unavailable"

    func hasFreshLocation(now: Date = Date()) -> Bool {
        guard let location, let captured = ISO8601DateFormatter().date(from: location.captured_at) else { return false }
        return abs(captured.timeIntervalSince(now)) <= 60
    }

    static func snapshot(location: CLLocation? = nil, status: String? = nil, now: Date = Date(), timezone: TimeZone = .current) -> Self {
        let formatter = ISO8601DateFormatter()
        let fresh = location.flatMap { fix -> Location? in
            guard CLLocationCoordinate2DIsValid(fix.coordinate), fix.horizontalAccuracy.isFinite, fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSince(now)) <= 60 else { return nil }
            return Location(latitude: fix.coordinate.latitude,
                            longitude: fix.coordinate.longitude,
                            horizontal_accuracy_meters: fix.horizontalAccuracy,
                            captured_at: formatter.string(from: fix.timestamp))
        }
        return Self(captured_at: formatter.string(from: now), timezone: timezone.identifier, location: fresh, location_status: fresh != nil ? (status ?? "available") : (location != nil ? "stale" : (status ?? "unavailable")))
    }

    @MainActor static func capture() async -> Self {
        let collector = ConversationLocationCollector()
        let location = await collector.capture()
        return snapshot(location: location, status: collector.status)
    }
}

@MainActor final class ConversationLocationCollector: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let captureTimeout: Duration
    private let permissionTimeout: Duration
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeout: Task<Void, Never>?
    private var updating = false
    private var best: CLLocation?
    private var sawStaleFix = false
    private(set) var status = "unavailable"

    init(manager: CLLocationManager = CLLocationManager(), captureTimeout: Duration = .seconds(15), permissionTimeout: Duration = .seconds(60)) {
        self.manager = manager
        self.captureTimeout = captureTimeout
        self.permissionTimeout = permissionTimeout
        super.init()
    }

    func capture() async -> CLLocation? {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(nil, status: "cancelled"); return }
                requestLocation()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(nil, status: "cancelled") }
        }
    }

    private func startTimeout(_ duration: Duration, awaitingPermission: Bool = false) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            let usable = self.best.flatMap { ConversationContext.snapshot(location: $0).location == nil ? nil : $0 }
            self.finish(usable, status: usable != nil ? self.availableStatus : awaitingPermission ? "permission_pending" : self.sawStaleFix ? "stale" : "timed_out")
        }
    }

    private var availableStatus: String {
        manager.accuracyAuthorization == .reducedAccuracy ? "approximate" : "available"
    }

    private func requestLocation() {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            if timeout == nil {
                startTimeout(permissionTimeout, awaitingPermission: true)
                manager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            guard !updating else { return }
            updating = true
            startTimeout(captureTimeout)
            manager.startUpdatingLocation()
        case .denied: finish(nil, status: "permission_denied")
        case .restricted: finish(nil, status: "permission_restricted")
        @unknown default: finish(nil, status: "unavailable")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { requestLocation() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard continuation != nil else { return }
        for fix in locations {
            guard ConversationContext.snapshot(location: fix).location != nil else { sawStaleFix = true; continue }
            if best == nil || fix.horizontalAccuracy < best!.horizontalAccuracy || abs(best!.timestamp.timeIntervalSinceNow) > 60 {
                best = fix
            }
        }
        if let best, best.horizontalAccuracy <= 25 || manager.accuracyAuthorization == .reducedAccuracy {
            finish(best, status: availableStatus)
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Core Location may temporarily have no fix while acquiring GPS; keep waiting.
        if (error as? CLError)?.code == .locationUnknown { return }
        finish(nil, status: (error as? CLError)?.code == .denied ? "permission_denied" : "unavailable")
    }
    private func finish(_ location: CLLocation?, status: String) {
        guard let pending = continuation else { return }
        continuation = nil
        self.status = status
        timeout?.cancel(); timeout = nil
        manager.stopUpdatingLocation(); manager.delegate = nil
        pending.resume(returning: location)
    }
}


struct ConversationLocationView: View {
    @Bindable var store: CurrentLocationStore
    @Environment(\.openURL) private var openURL

    private var explanation: String {
        switch store.context?.location_status {
        case "permission_denied": return "Location access is off. Allow While Using the App in Settings."
        case "permission_restricted": return "Location access is restricted on this iPhone."
        case "permission_pending": return "Allow location access when iOS asks."
        case "timed_out": return "Waiting for a fresh location. It will retry automatically."
        case "stale": return "Waiting for a newer location. It will retry automatically."
        case .none: return "Your nearby address will appear automatically."
        default: return store.context?.location == nil ? "Location is unavailable. Check Location Services." : "Location found. Nearby address is unavailable; lookup will retry automatically."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Nearby address", systemImage: "mappin.and.ellipse").font(.caption.bold())
                Spacer()
                if store.isUpdating { ProgressView().controlSize(.small) }
            }
            if let address = store.address {
                Text(verbatim: address).font(.subheadline).textSelection(.enabled)
                if let stamp = store.context?.captured_at, let captured = ISO8601DateFormatter().date(from: stamp) {
                    Text("Updated \(captured.formatted(date: .omitted, time: .shortened)) · automatic")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text(LocalizedStringKey(store.isUpdating ? "Finding your nearby address…" : explanation)).font(.caption2).foregroundStyle(.secondary)
            }
            if ["permission_denied", "approximate"].contains(store.context?.location_status ?? "") {
                Button("Open location settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}
