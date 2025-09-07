//
//  Features_Routing_RouteEngine.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import Foundation
import MapKit

@MainActor
final class RouteEngine: ObservableObject {

    /// 2点間を自動車でルーティングして MKRoute を返す
    func route(from: CLLocationCoordinate2D,
               to: CLLocationCoordinate2D,
               allowHighways: Bool = true) async throws -> MKRoute {

        let src = MKMapItem(placemark: .init(coordinate: from))
        let dst = MKMapItem(placemark: .init(coordinate: to))

        let req = MKDirections.Request()
        req.source = src
        req.destination = dst
        req.transportType = .automobile
        req.requestsAlternateRoutes = false
        // MapKit には「高速回避」の公開プロパティが無いので allowHighways は将来拡張用

        let dir = MKDirections(request: req)
        let res = try await dir.calculate()
        guard let route = res.routes.first else {
            throw NSError(domain: "RouteEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "経路が見つかりません"])
        }
        return route
    }
}
