//
//  UI_RouteOptionSheet.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import SwiftUI

struct RouteOptionSheet: View {
    @Binding var useHighway: Bool
    var body: some View {
        NavigationStack {
            Form {
                Toggle("高速道路を使う", isOn: $useHighway)
            }
            .navigationTitle("ルートオプション")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
