import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit

struct GeoPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let detail: String
    let origin: TrafficOrigin
    let sample: RequestSample
    var count: Int
}

enum GeoPlace {
    static func isUsable(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude, let longitude else { return false }
        if latitude == 0 && longitude == 0 { return false }
        return (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    static func coordinate(for request: RequestSample) -> CLLocationCoordinate2D? {
        if request.origin == .ourService { return nil }
        if isUsable(latitude: request.latitude, longitude: request.longitude) {
            return CLLocationCoordinate2D(latitude: request.latitude ?? 0, longitude: request.longitude ?? 0)
        }
        return centroid(code: request.countryCode, country: request.country)
    }

    static func pins(from requests: [RequestSample]) -> [GeoPin] {
        var grouped: [String: GeoPin] = [:]
        for request in requests {
            guard let coordinate = coordinate(for: request) else { continue }
            let key = "\(coordinate.latitude.rounded(to: 2)):\(coordinate.longitude.rounded(to: 2))"
            if var current = grouped[key] {
                current.count += 1
                grouped[key] = current
                continue
            }
            let place = [request.city, request.region, request.country].compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty || trimmed == "Unknown" || trimmed == "Private" ? nil : trimmed
            }.joined(separator: ", ")
            grouped[key] = GeoPin(
                id: key,
                coordinate: coordinate,
                title: place.isEmpty ? request.clientIp : place,
                detail: request.origin.sourceLabel(for: request),
                origin: request.origin,
                sample: request,
                count: 1
            )
        }
        return grouped.values.sorted { $0.count > $1.count }
    }

    static func region(for pins: [GeoPin]) -> MKCoordinateRegion? {
        guard let first = pins.first else { return nil }
        var minLat = first.coordinate.latitude
        var maxLat = first.coordinate.latitude
        var minLon = first.coordinate.longitude
        var maxLon = first.coordinate.longitude
        for pin in pins {
            minLat = min(minLat, pin.coordinate.latitude)
            maxLat = max(maxLat, pin.coordinate.latitude)
            minLon = min(minLon, pin.coordinate.longitude)
            maxLon = max(maxLon, pin.coordinate.longitude)
        }
        let span = MKCoordinateSpan(
            latitudeDelta: max(8, (maxLat - minLat) * 1.8 + 2),
            longitudeDelta: max(8, (maxLon - minLon) * 1.8 + 2)
        )
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: span
        )
    }

    static func centroid(code: String, country: String) -> CLLocationCoordinate2D? {
        let key = normalizedCode(code, country: country)
        guard let pair = centroids[key] else { return nil }
        return CLLocationCoordinate2D(latitude: pair.0, longitude: pair.1)
    }

    private static func normalizedCode(_ code: String, country: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.count == 2, trimmed != "ZZ" { return trimmed }
        switch country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "israel": return "IL"
        case "united states", "usa", "us": return "US"
        case "germany": return "DE"
        case "united kingdom", "uk", "great britain": return "GB"
        case "france": return "FR"
        case "singapore": return "SG"
        case "netherlands": return "NL"
        case "canada": return "CA"
        case "china": return "CN"
        case "brazil": return "BR"
        default: return ""
        }
    }

    private static let centroids: [String: (Double, Double)] = [
        "AE": (24.45, 54.38), "AR": (-34.60, -58.38), "AT": (48.21, 16.37), "AU": (-35.28, 149.13),
        "BE": (50.85, 4.35), "BG": (42.70, 23.32), "BR": (-15.79, -47.88), "CA": (45.42, -75.70),
        "CH": (46.95, 7.44), "CL": (-33.45, -70.67), "CN": (39.90, 116.41), "CZ": (50.08, 14.44),
        "DE": (52.52, 13.40), "DK": (55.68, 12.57), "EG": (30.04, 31.24), "ES": (40.42, -3.70),
        "FI": (60.17, 24.94), "FR": (48.86, 2.35), "GB": (51.51, -0.13), "GR": (37.98, 23.73),
        "HK": (22.32, 114.17), "HU": (47.50, 19.04), "ID": (-6.21, 106.85), "IE": (53.35, -6.26),
        "IL": (31.79, 35.20), "IN": (28.61, 77.21), "IT": (41.90, 12.50), "JP": (35.68, 139.69),
        "KR": (37.57, 126.98), "MX": (19.43, -99.13), "MY": (3.14, 101.69), "NL": (52.37, 4.90),
        "NO": (59.91, 10.75), "NZ": (-41.29, 174.78), "PH": (14.60, 120.98), "PK": (33.68, 73.05),
        "PL": (52.23, 21.01), "PT": (38.72, -9.14), "RO": (44.43, 26.10), "RU": (55.76, 37.62),
        "SA": (24.71, 46.68), "SE": (59.33, 18.07), "SG": (1.35, 103.82), "TH": (13.76, 100.50),
        "TR": (39.93, 32.86), "TW": (25.03, 121.57), "UA": (50.45, 30.52), "US": (38.91, -77.04),
        "VN": (21.03, 105.85), "ZA": (-25.75, 28.19)
    ]
}

private final class GeoAnnotation: NSObject, MKAnnotation {
    let pin: GeoPin
    var coordinate: CLLocationCoordinate2D { pin.coordinate }
    var title: String? { pin.title }
    var subtitle: String? { pin.count > 1 ? "\(pin.count) requests" : pin.detail }

    init(pin: GeoPin) { self.pin = pin }
}

struct RequestMapCanvas: UIViewRepresentable {
    let pins: [GeoPin]
    var onSelect: (RequestSample) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        if #available(iOS 16.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = config
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        let existing = Set(map.annotations.compactMap { $0 as? GeoAnnotation }.map(\.pin.id))
        let next = Set(pins.map(\.id))
        if existing != next {
            map.removeAnnotations(map.annotations)
            map.addAnnotations(pins.map(GeoAnnotation.init))
        }
        if let region = GeoPlace.region(for: pins) {
            map.setRegion(region, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (RequestSample) -> Void
        init(onSelect: @escaping (RequestSample) -> Void) { self.onSelect = onSelect }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let item = annotation as? GeoAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "geo") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "geo")
            view.annotation = annotation
            view.markerTintColor = item.pin.origin == .ourService
                ? UIColor(red: 1, green: 0.68, blue: 0.31, alpha: 1)
                : UIColor(red: 0.25, green: 0.90, blue: 0.82, alpha: 1)
            view.glyphText = item.pin.count > 1 ? "\(item.pin.count)" : nil
            view.canShowCallout = true
            view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let item = view.annotation as? GeoAnnotation {
                onSelect(item.pin.sample)
            }
        }
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
