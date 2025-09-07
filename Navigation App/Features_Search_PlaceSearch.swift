//
//  Features_Search_PlaceSearch.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import Foundation
import MapKit

struct PlaceItem: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: PlaceItem, rhs: PlaceItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class PlaceSearch: ObservableObject {
    @Published var results: [PlaceItem] = []

    func search(query: String, in region: MKCoordinateRegion) {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = region

        MKLocalSearch(request: req).start { [weak self] resp, _ in
            guard let self else { return }
            let items = resp?.mapItems ?? []
            Task { @MainActor in
                self.results = items.prefix(10).compactMap { item in
                    guard let c = item.placemark.location?.coordinate else { return nil }
                    return PlaceItem(name: item.name ?? query,
                                     subtitle: item.placemark.title,
                                     coordinate: c)
                }
            }
        }
    }

    func clear() { results = [] }
}
