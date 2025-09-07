//
//  Features_Routes_Routes.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import Foundation
import MapKit

struct NavRouteModel: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var points: [CLLocationCoordinate2D]

    // Equatable は id のみで判定（座標配列の等価判定に依存しない）
    static func == (lhs: NavRouteModel, rhs: NavRouteModel) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class RouteStore: ObservableObject {
    @Published var routes: [NavRouteModel] = []
    @Published var selected: NavRouteModel? = nil

    func save(name: String, points: [CLLocationCoordinate2D]) {
        routes.append(.init(name: name, points: points))
    }
}
