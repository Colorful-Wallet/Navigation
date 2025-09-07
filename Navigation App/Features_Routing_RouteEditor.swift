//
//  Features_Routing_RouteEditor.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import Foundation
import MapKit

@MainActor
final class RouteEditor: ObservableObject {
    @Published var points: [CLLocationCoordinate2D] = []   // ユーザーが打った編集点
    @Published var segments: [MKPolyline] = []             // 生成された道路スナップ済みセグメント

    func reset() {
        points.removeAll()
        segments.removeAll()
    }
}
