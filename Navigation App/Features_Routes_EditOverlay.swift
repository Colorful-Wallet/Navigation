//
//  Features_Routes_EditOverlay.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import SwiftUI

enum EditModeKind { case none, editExisting, createNew }

struct EditOverlay: View {
    let mode: EditModeKind
    @Binding var points: [CGPoint]
    var onFinish: () -> Void
    var onCancel: () -> Void

    @State private var draggingIndex: Int? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack {
                HStack {
                    Text("ルート編集").foregroundStyle(.white).bold()
                    Spacer()
                    Button("完了") { onFinish() }.buttonStyle(.borderedProminent)
                    Button("キャンセル") { onCancel() }.buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                ZStack {
                    // 線
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for p in points.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(Color.green, lineWidth: 3)

                    // 編集点
                    ForEach(Array(points.enumerated()), id: \.offset) { idx, p in
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 20, height: 20)
                            .position(p)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        draggingIndex = idx
                                        if let di = draggingIndex { points[di] = value.location }
                                    }
                                    .onEnded { _ in draggingIndex = nil }
                            )
                            .onTapGesture {
                                points.removeAll { $0 == p } // 簡易削除
                            }
                    }
                }
                .overlay(
                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                TapGesture().onEnded {
                                    // 簡易に中央へ1点追加（モック）
                                    let pt = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                                    points.append(pt)
                                }
                            )
                    }
                )

                Spacer(minLength: 8)
            }
        }
        .ignoresSafeArea()
    }
}
