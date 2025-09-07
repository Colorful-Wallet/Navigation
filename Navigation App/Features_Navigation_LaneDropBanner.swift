//
//  Features_Navigation_LaneDropBanner.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import SwiftUI

struct LaneDropBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "triangle.fill").foregroundStyle(.yellow)
            Text(message).font(.subheadline).bold().foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: Capsule())
        .padding(.horizontal, 12)
    }
}
