//
//  UI_SearchBar.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var onSearch: (String) -> Void
    var onRoute: (String) -> Void
    var onOption: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("場所・住所を検索", text: $text)
                .textFieldStyle(.roundedBorder)
            Button("検索") { onSearch(text) }
                .buttonStyle(.bordered)
            Button("経路") { onRoute(text) }
                .buttonStyle(.borderedProminent)
            Button { onOption() } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
