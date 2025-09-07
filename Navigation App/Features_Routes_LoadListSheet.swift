//
//  Features_Routes_LoadListSheet.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import SwiftUI

struct LoadListSheet: View {
    let routes: [NavRouteModel]
    var onLoad: (NavRouteModel) -> Void
    var onShare: (NavRouteModel) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(routes) { r in
                HStack {
                    Text(r.name)
                    Spacer()
                    Button("読み込み") { onLoad(r); dismiss() }
                        .buttonStyle(.borderedProminent)
                    Button("共有") { onShare(r) }
                        .buttonStyle(.bordered)
                }
            }
            .navigationTitle("保存済みルート")
        }
    }
}
