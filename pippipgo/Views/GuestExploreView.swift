import CoreLocation
import MapKit
import SwiftUI
import Translation

// Signed-out exploring (App Review guideline 5.1.1(v)): the map, nearby essentials, directions
// and Apple's own translation work without an account. Everything here runs on the phone with
// Apple services; nothing is sent to PipPipGo or an AI provider. Ask Pip still needs an account.

enum GuestCategory: String, CaseIterable, Identifiable {
    case restrooms, transit, groceries, food, hotels, pharmacy, cash, parking
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .restrooms: "Restrooms"
        case .transit: "Transit"
        case .groceries: "Groceries"
        case .food: "Food"
        case .hotels: "Hotels"
        case .pharmacy: "Pharmacy"
        case .cash: "Cash"
        case .parking: "Parking"
        }
    }

    var symbol: String {
        switch self {
        case .restrooms: "toilet.fill"
        case .transit: "tram.fill"
        case .groceries: "cart.fill"
        case .food: "fork.knife"
        case .hotels: "bed.double.fill"
        case .pharmacy: "pills.fill"
        case .cash: "banknote.fill"
        case .parking: "parkingsign"
        }
    }

    var tint: Color {
        switch self {
        case .restrooms: .blue
        case .transit: .indigo
        case .groceries: .orange
        case .food: Color(red: 0.85, green: 0.33, blue: 0.16)
        case .hotels: .purple
        case .pharmacy: .green
        case .cash: .teal
        case .parking: Color(red: 0.0, green: 0.42, blue: 0.85)
        }
    }

    /// Plain-text fallback when Apple has no categorised places nearby.
    var query: String {
        switch self {
        case .restrooms: "public restroom"
        case .transit: "public transport station"
        case .groceries: "grocery store"
        case .food: "restaurant"
        case .hotels: "hotel"
        case .pharmacy: "pharmacy"
        case .cash: "ATM"
        case .parking: "parking"
        }
    }

    var pointsOfInterest: [MKPointOfInterestCategory] {
        switch self {
        case .restrooms: [.restroom]
        case .transit: [.publicTransport]
        case .groceries: [.foodMarket]
        case .food: [.restaurant, .cafe, .bakery]
        case .hotels: [.hotel]
        case .pharmacy: [.pharmacy]
        case .cash: [.atm, .bank]
        case .parking: [.parking]
        }
    }
}

struct NearbyPlace: Identifiable {
    let id = UUID()
    let item: MKMapItem
    let distance: CLLocationDistance
    var name: String { item.name ?? "" }
    var coordinate: CLLocationCoordinate2D { item.placemark.coordinate }
}

@MainActor @Observable
final class NearbyPlacesModel: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus
    private(set) var category: GuestCategory?
    private(set) var places: [NearbyPlace] = []
    private(set) var searching = false
    private(set) var failed = false
    /// How far the traveler is willing to go, in local units (miles where people use them).
    static let radii: [CLLocationDistance] = Locale.current.measurementSystem == .metric
        ? [1_000, 5_000, 25_000] : [804.672, 4_828.032, 24_140.16]
    private(set) var radius = NearbyPlacesModel.radii[0]
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var searchID = UUID()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var locationDenied: Bool { authorization == .denied || authorization == .restricted }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if [.authorizedAlways, .authorizedWhenInUse].contains(authorization) { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        let first = location == nil
        location = latest
        // A category tapped before the first fix searches as soon as the location arrives.
        if first, searching, let category { search(category) }
    }

    func clear() {
        searchID = UUID()
        category = nil; places = []; searching = false; failed = false
    }

    func setRadius(_ radius: CLLocationDistance) {
        self.radius = radius
        if let category { search(category, widen: false) }
    }

    /// Apple Maps places within the chosen distance, nearest first. When nothing is that close it
    /// widens to the next distance (shown as selected), then tries a filtered plain-text search.
    func search(_ category: GuestCategory, widen: Bool = true) {
        let ticket = UUID(); searchID = ticket
        self.category = category; places = []; failed = false
        searching = true
        guard let location else {
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
            manager.startUpdatingLocation()
            return
        }
        Task {
            var found: [MKMapItem] = []
            var errors = 0, attempts = 0
            let options = Self.radii.filter { $0 >= radius }
            var used = radius
            for candidate in (widen ? options : [radius]) where found.isEmpty {
                used = candidate
                let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: candidate)
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: category.pointsOfInterest)
                attempts += 1
                do { found = try await MKLocalSearch(request: request).start().mapItems } catch { errors += 1 }
                guard searchID == ticket else { return }
            }
            if found.isEmpty {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = category.query
                request.resultTypes = .pointOfInterest
                request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: used * 2, longitudinalMeters: used * 2)
                attempts += 1
                do {
                    // Text search can match unrelated businesses; drop ones Apple files under another kind.
                    found = try await MKLocalSearch(request: request).start().mapItems.filter { item in
                        item.pointOfInterestCategory.map(category.pointsOfInterest.contains) ?? true
                    }
                } catch { errors += 1 }
                guard searchID == ticket else { return }
            }
            radius = used
            places = found
                .map { item in
                    let point = item.placemark.coordinate
                    let distance = location.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                    return NearbyPlace(item: item, distance: distance)
                }
                .filter { $0.distance <= used * 1.1 }
                .sorted { $0.distance < $1.distance }
                .prefix(15).map { $0 }
            failed = places.isEmpty && errors == attempts
            searching = false
        }
    }
}

struct GuestExploreView: View {
    let signIn: () -> Void
    var errorMessage: String?
    var signingIn = false
    @State private var model = NearbyPlacesModel()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selected: NearbyPlace?
    @State private var askingToSignIn = false
    @State private var translating = false
    @Namespace private var mapScope
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Map(position: $position, scope: mapScope) {
            UserAnnotation()
            ForEach(model.places) { place in
                Marker(place.name, systemImage: model.category?.symbol ?? "mappin", coordinate: place.coordinate)
                    .tint(model.category?.tint ?? .red)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .all))
        .mapControlVisibility(.hidden)
        // The panel insets the map, so Apple's attribution and legal link stay visible above it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            panel.frame(maxWidth: 520)
        }
        .overlay(alignment: .topTrailing) { floatingControls.padding(.trailing, 12).padding(.top, 8) }
        .overlay(alignment: .topLeading) {
            Button(action: signIn) {
                HStack(spacing: 6) {
                    if signingIn { ProgressView() } else { Image(systemName: "person.crop.circle.fill").font(.title3) }
                    Text("Sign in").font(.headline)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(.regularMaterial, in: Capsule())
            }
            .disabled(signingIn)
            .accessibilityIdentifier("guest.signIn")
            .padding(.leading, 12).padding(.top, 8)
        }
        .mapScope(mapScope)
        // Show the traveler and every result, including ones found farther away.
        .onChange(of: model.places.map(\.id)) { _, _ in
            if let region = NearbyFinder.region(for: model) { withAnimation { position = .region(region) } }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.start() } else { model.stop() }
        }
        .onDisappear { model.stop() }
        #if DEBUG
        // Simulator review: `-PipGuestCategory restrooms` searches once a location arrives.
        .onChange(of: model.location == nil) { _, missing in
            let arguments = ProcessInfo.processInfo.arguments
            if !missing, model.category == nil, let index = arguments.firstIndex(of: "-PipGuestCategory"),
               index + 1 < arguments.count, let category = GuestCategory(rawValue: arguments[index + 1]) {
                model.search(category)
            }
        }
        #endif
        .confirmationDialog("Sign in to ask Pip", isPresented: $askingToSignIn, titleVisibility: .visible) {
            Button("Sign in or create account", action: signIn)
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Pip answers your questions using your profile and AI. Sign in to continue.")
        }
        .sheet(isPresented: $translating) { GuestTranslateSheet() }
    }

    /// Apple Maps-style stack: translate, language and the system location button.
    private var floatingControls: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                if #available(iOS 17.4, *) {
                    Button { translating = true } label: {
                        Image(systemName: "character.bubble").font(.title3).frame(width: 48, height: 48)
                    }
                    .accessibilityLabel(Text("Translate"))
                    .accessibilityIdentifier("guest.translate")
                    Divider().frame(width: 48)
                }
                AppLanguageMenu().frame(width: 48, height: 48)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            MapUserLocationButton(scope: mapScope)
                .buttonBorderShape(.roundedRectangle(radius: 12))
            MapCompass(scope: mapScope)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            if let errorMessage {
                Text(LocalizedStringKey(errorMessage)).font(.callout).foregroundStyle(.red)
            }
            Button { askingToSignIn = true } label: {
                Label("Ask Pip", systemImage: "hand.raised.fill")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.blue)
            .accessibilityIdentifier("guest.askPip")

            NearbyFinder(model: model, selected: $selected) { place in
                withAnimation { position = .item(place.item) }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .background {
            // Continues behind the home indicator, like an Apple Maps sheet.
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(.regularMaterial).ignoresSafeArea(edges: .bottom)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
    }
}

/// Find nearby: Apple Maps categories, nearest results and walking directions. Shared by the
/// signed-out screen and the signed-in map.
struct NearbyFinder: View {
    let model: NearbyPlacesModel
    @Binding var selected: NearbyPlace?
    let focus: (NearbyPlace) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let selected {
            placeCard(selected)
        } else if let category = model.category {
            results(category)
        } else {
            categories
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find nearby").font(.title3.weight(.bold))
            if model.locationDenied {
                Text("Allow location access to find places near you.").font(.callout).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 12) {
                ForEach(GuestCategory.allCases) { category in
                    Button { model.search(category); selected = nil } label: {
                        VStack(spacing: 6) {
                            Image(systemName: category.symbol).font(.title3).foregroundStyle(.white)
                                .frame(width: 52, height: 52).background(category.tint, in: Circle())
                            Text(category.title).font(.caption).foregroundStyle(.primary)
                                .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guest.category.\(category.rawValue)")
                }
            }
        }
    }

    private func results(_ category: GuestCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(category.title, systemImage: category.symbol).font(.title3.weight(.bold))
                Spacer()
                Button { model.clear() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("Close"))
            }
            distanceChoice
            if model.locationDenied {
                Text("Allow location access to find places near you.").font(.callout).foregroundStyle(.secondary)
                Button("Open location settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
            } else if model.searching {
                HStack(spacing: 10) {
                    ProgressView()
                    if model.location == nil {
                        Text("Finding your location…").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else if model.places.isEmpty {
                Text(model.failed ? "Places nearby are unavailable right now." : "Nothing found nearby.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Try again") { model.search(category) }
                    .buttonStyle(.bordered)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.places) { place in
                            Button {
                                selected = place
                                focus(place)
                            } label: {
                                HStack {
                                    Text(verbatim: place.name).font(.body).foregroundStyle(.primary).lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text(NearbyFinder.distance(place.distance)).font(.callout).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    /// Within ½ mi · 3 mi · 15 mi (1 · 5 · 25 km): how far the traveler is willing to go.
    private var distanceChoice: some View {
        HStack(spacing: 8) {
            ForEach(NearbyPlacesModel.radii, id: \.self) { radius in
                let selected = model.radius == radius
                Button { model.setRadius(radius) } label: {
                    Text(Self.radiusLabel(radius))
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(selected ? Color.blue : Color.secondary.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("nearby.radius.\(Int(radius))")
            }
        }
    }

    private func placeCard(_ place: NearbyPlace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: place.name).font(.title2.weight(.bold))
                    Text(NearbyFinder.distance(place.distance)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { selected = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("Close"))
            }
            Button {
                place.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("guest.directions")
        }
    }

    /// Frames the traveler and every result together.
    static func region(for model: NearbyPlacesModel) -> MKCoordinateRegion? {
        guard let location = model.location, !model.places.isEmpty else { return nil }
        let points = [location.coordinate] + model.places.map(\.coordinate)
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: max(0.006, (lats.max()! - lats.min()!) * 1.5),
                                                         longitudeDelta: max(0.006, (lons.max()! - lons.min()!) * 1.5)))
    }

    /// "0.5 mi" / "3 mi" / "15 mi" or "1 km" / "5 km" / "25 km", never converted to feet.
    static func radiusLabel(_ meters: CLLocationDistance) -> String {
        let style = Measurement<UnitLength>.FormatStyle(width: .abbreviated, usage: .asProvided,
                                                        numberFormatStyle: .number.precision(.fractionLength(0...1)))
        let metric = Locale.current.measurementSystem == .metric
        return Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: metric ? .kilometers : .miles).formatted(style)
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// Apple's own translation, on the phone. No account and no PipPipGo or AI provider involved.
struct GuestTranslateSheet: View {
    @State private var phrase = ""
    @State private var showing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Type a phrase to translate", text: $phrase, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("guest.translate.text")
                Button("Translate") { showing = true }
                    .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Translate a phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .modifier(SystemTranslation(text: phrase, isPresented: $showing))
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SystemTranslation: ViewModifier {
    let text: String
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.4, *) {
            content.translationPresentation(isPresented: $isPresented, text: text)
        } else {
            content
        }
    }
}
