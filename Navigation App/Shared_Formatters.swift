//
//  Shared_Formatters.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import Foundation
import MapKit

func fmtDistance(_ m: CLLocationDistance) -> String {
    if m < 1000 { return String(format: "%.0f m", m) }
    return String(format: "%.1f km", m / 1000.0)
}
func fmtDuration(_ s: TimeInterval) -> String {
    let h = Int(s) / 3600
    let m = (Int(s) % 3600) / 60
    return h > 0 ? "\(h)時間\(m)分" : "\(m)分"
}
