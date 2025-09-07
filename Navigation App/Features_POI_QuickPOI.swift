//
//  Features_POI_QuickPOI.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import Foundation
import MapKit

enum QuickPOIKind: String, CaseIterable, Identifiable {
    case gas = "ガソリン", ev = "充電", toilet = "トイレ", conv = "コンビニ"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .gas:    return "fuelpump.fill"
        case .ev:     return "bolt.fill"        // 環境依存の無いシンボル
        case .toilet: return "figure.wave"
        case .conv:   return "bag.fill"
        }
    }
    var query: String {
        switch self {
        case .gas:    return "ガソリンスタンド"
        case .ev:     return "充電スタンド"
        case .toilet: return "トイレ"
        case .conv:   return "コンビニ"
        }
    }
}

struct SimplePOI: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let kind: QuickPOIKind

    static func == (lhs: SimplePOI, rhs: SimplePOI) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class QuickPOISearch: ObservableObject {
    @Published var active: QuickPOIKind? = nil
    @Published var results: [SimplePOI] = []

    /// 指定種別のPOIを、リージョン内で最大5件検索
    func run(_ kind: QuickPOIKind, around center: CLLocationCoordinate2D, span: MKCoordinateSpan = .init(latitudeDelta: 0.02, longitudeDelta: 0.02)) {
        active = kind
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = kind.query
        req.region = MKCoordinateRegion(center: center, span: span)

        MKLocalSearch(request: req).start { [weak self] resp, _ in
            guard let self else { return }
            let items = resp?.mapItems ?? []
            Task { @MainActor in
                self.results = items.prefix(5).compactMap { item in
                    guard let c = item.placemark.location?.coordinate else { return nil }
                    return SimplePOI(name: item.name ?? kind.rawValue, coordinate: c, kind: kind)
                }
            }
        }
    }

    func clear() { active = nil; results = [] }
}
