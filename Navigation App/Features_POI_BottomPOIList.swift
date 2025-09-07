//
//  Features_POI_BottomPOIList.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import SwiftUI
import MapKit

struct BottomPOIList: View {
    let kind: QuickPOIKind
    let items: [SimplePOI]
    let distanceFrom: CLLocationCoordinate2D
    let onSelect: (SimplePOI) -> Void
    let onClose: () -> Void

    private func distance(_ c: CLLocationCoordinate2D) -> CLLocationDistance {
        MKMapPoint(c).distance(to: MKMapPoint(distanceFrom))
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.secondary.opacity(0.4))
                .frame(width: 44, height: 5).padding(.top, 8)

            HStack {
                Label(kind.rawValue, systemImage: kind.icon).font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.headline) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            List(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.body)
                    Text(fmtDistance(distance(item.coordinate)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect(item) }
            }
            .listStyle(.plain)
            .frame(maxHeight: 280)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .shadow(radius: 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityAddTraits(.isModal)
    }
}
