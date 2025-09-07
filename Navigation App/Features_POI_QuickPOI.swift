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
        case .gas: return "fuelpump.fill"
        case .ev:  return "bolt.fill"        // 確実に存在するSF Symbol
        case .toilet: return "figure.wave"   // 出ない環境は別アイコンに差し替え可
        case .conv: return "bag.fill"
        }
    }
    var query: String {
        switch self {
        case .gas: return "ガソリンスタンド"
        case .ev:  return "充電スタンド"
        case .toilet: return "トイレ"
        case .conv: return "コンビニ"
        }
    }
}

struct SimplePOI: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let kind: QuickPOIKind

    // Equatable / Hashable は id のみで判断（座標型の差異で失敗しないように）
    static func == (lhs: SimplePOI, rhs: SimplePOI) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class QuickPOISearch: ObservableObject {
    @Published var active: QuickPOIKind? = nil
    @Published var results: [SimplePOI] = []

    // モック検索：中心近くに5件ランダム
    func run(_ kind: QuickPOIKind, around center: CLLocationCoordinate2D) {
        active = kind
        results = (0..<5).map { i in
            let dx = Double.random(in: -0.004...0.004)
            let dy = Double.random(in: -0.004...0.004)
            let c = CLLocationCoordinate2D(latitude: center.latitude + dy, longitude: center.longitude + dx)
            return SimplePOI(name: "\(kind.rawValue) \(i+1)", coordinate: c, kind: kind)
        }
    }

    func clear() { active = nil; results = [] }
}
