//
//  Features_Navigation_NavigationState.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import Foundation
import MapKit

@MainActor
final class NavigationState: ObservableObject {
    @Published var isNavigating = false
    @Published var useHighway = true
    @Published var nextSymbol: String = "arrow.turn.up.right"
    @Published var nextDistanceM: CLLocationDistance = 350
    @Published var eta: Date = Date().addingTimeInterval(42 * 60)
    @Published var remainingTimeSec: TimeInterval = 42 * 60
    @Published var remainingDistanceM: CLLocationDistance = 12_800
    @Published var progress: Double = 0.35
    @Published var isMuted: Bool = false
    @Published var isOffRoute: Bool = false
    @Published var laneDropMessage: String? = nil
}
