import CoreLocation
import MapKit
import Testing
@testable import pippipgo

struct NearbyRatingsTests {
    private func place(_ name: String, _ lat: Double, _ lon: Double) -> NearbyPlace {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        item.name = name
        return NearbyPlace(item: item, distance: 0)
    }

    private func google(_ name: String, _ lat: Double, _ lon: Double, _ rating: Double?) -> GooglePlaceRating {
        GooglePlaceRating(id: name, name: name, latitude: lat, longitude: lon, rating: rating,
                          user_rating_count: 10, google_maps_uri: nil)
    }

    @MainActor @Test func ratingsMatchByNameNearbyOrByVeryCloseLocation() {
        let hotel = place("DoubleTree by Hilton Hotel San Diego - Del Mar", 32.9380, -117.2360)
        let inn = place("Hampton Inn", 32.9400, -117.2300)
        let far = place("Far Hotel", 33.0000, -117.3000)
        let ratings = NearbyPlacesModel.match([hotel, inn, far], [
            google("DoubleTree by Hilton San Diego Del Mar", 32.9385, -117.2364, 4.3), // ~65 m, same name
            google("Totally Different", 32.94002, -117.23002, 3.9),                 // ~3 m, any name
            google("Far Hotel", 33.0100, -117.3000, 4.8),                           // ~1 km away
        ])
        #expect(ratings[hotel.id]?.rating == 4.3)
        #expect(ratings[inn.id]?.rating == 3.9)
        #expect(ratings[far.id] == nil)
    }

    @MainActor @Test func placesWithoutGoogleRatingsAreSkipped() {
        let hotel = place("Hotel", 32.9, -117.2)
        #expect(NearbyPlacesModel.match([hotel], [google("Hotel", 32.9, -117.2, nil)]).isEmpty)
    }

    @Test func distancesRoundToEasyValues() {
        let us = Locale.current.measurementSystem != .metric
        if us {
            #expect(NearbyFinder.distance(522).contains("0.3"))      // 1,715 ft
            #expect(NearbyFinder.distance(2_500).contains("1.5"))    // 1.55 mi
            #expect(NearbyFinder.distance(20_000).contains("12"))    // 12.4 mi
        } else {
            #expect(NearbyFinder.distance(522).contains("500"))
            #expect(NearbyFinder.distance(2_600).contains("2.5"))
        }
    }
}
