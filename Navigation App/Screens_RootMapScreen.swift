//
//  Screens_RootMapScreen.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import SwiftUI
import MapKit
import UIKit

struct RootMapScreen: View {
    @StateObject private var nav = NavigationState()
    @StateObject private var poi = QuickPOISearch()
    @StateObject private var store = RouteStore()
    @StateObject private var place = PlaceSearch()
    @StateObject private var location = LocationManager()

    // Mapカメラ / 表示リージョン
    @State private var camera: MapCameraPosition
    @State private var searchRegion: MKCoordinateRegion

    // 編集関連
    @State private var editMode: EditModeKind = .none
    @State private var editPoints: [CGPoint] = []

    // 保存/ロード
    @State private var showingSave = false
    @State private var saveName = ""
    @State private var showLoadListSheet = false

    // 検索ボックス
    @State private var searchText = ""
    @State private var showingRouteOption = false

    // 現在地追従
    @State private var followUser = true

    init() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.0116, longitude: 135.7681),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        _camera = State(initialValue: .region(region))
        _searchRegion = State(initialValue: region)
    }

    var body: some View {
        ZStack {
            // === Map
            Map(position: $camera) {
                // ルート簡易プレビュー（点で表示）
                if let r = store.selected {
                    ForEach(Array(r.points.enumerated()), id: \.offset) { _, c in
                        Annotation("", coordinate: c) {
                            Circle().frame(width: 4, height: 4).foregroundStyle(.blue)
                        }
                    }
                }
                // 目的地検索の結果
                ForEach(place.results) { item in
                    Marker(item.name, coordinate: item.coordinate)
                }
                // POIピン
                ForEach(poi.results) { item in
                    Marker(item.name, coordinate: item.coordinate)
                }
            }
            .onMapCameraChange(frequency: .continuous) { ctx in
                searchRegion = ctx.region
            }
            .mapControls { MapUserLocationButton(); MapCompass() }
            .ignoresSafeArea()

            // === 上部：新規/編集 + クイック検索
            VStack(spacing: 8) {
                HStack {
                    Button("ルート新規作成") { startCreateRoute() }
                        .buttonStyle(.borderedProminent)
                    Button("ルート編集") { startEditRoute() }
                        .buttonStyle(.bordered)
                    Spacer()
                    if store.selected != nil {
                        Button("保存") { showingSave = true }
                        Button("ロード") { showLoadList() }
                    } else {
                        Button("ロード") { showLoadList() }
                    }
                }
                .padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach([QuickPOIKind.gas, .ev, .toilet, .conv]) { k in
                            Button {
                                if poi.active == k { poi.clear() }
                                else {
                                    poi.run(k, around: searchRegion.center,
                                            span: searchRegion.span)
                                }
                            } label: {
                                Label(k.rawValue, systemImage: k.icon)
                                    .padding(.vertical, 6).padding(.horizontal, 10)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }

                Spacer()
            }
            .padding(.top, 8)

            // === 左側：ナビ中の縦クイック
            if nav.isNavigating {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        ForEach([QuickPOIKind.gas, .ev, .toilet, .conv]) { k in
                            Button {
                                poi.run(k, around: searchRegion.center, span: searchRegion.span)
                                if let nearest = poi.results.first {
                                    nav.nextSymbol = "mappin.and.ellipse"
                                    nav.nextDistanceM = MKMapPoint(nearest.coordinate)
                                        .distance(to: MKMapPoint(searchRegion.center))
                                }
                            } label: {
                                Image(systemName: k.icon).font(.title3)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 120)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // === 下部：検索ボックス
            VStack {
                Spacer()
                SearchBar(
                    text: $searchText,
                    onSearch: { text in
                        place.search(query: text, in: searchRegion)
                        // 見つかったらマップを寄せる
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if let first = place.results.first {
                                camera = .camera(
                                    MapCamera(centerCoordinate: first.coordinate,
                                              distance: 1500, heading: 0, pitch: 0)
                                )
                            }
                        }
                    },
                    onRoute: { text in
                        place.search(query: text, in: searchRegion)
                        nav.isNavigating = true
                    },
                    onOption: { showingRouteOption = true }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // === 車線減少バナー
            VStack {
                if let msg = nav.laneDropMessage {
                    LaneDropBanner(message: msg).padding(.top, 8)
                }
                Spacer()
            }
            .animation(.easeInOut, value: nav.laneDropMessage)

            // === DriveHUD
            VStack { Spacer()
                DriveHUD().environmentObject(nav)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .ignoresSafeArea(edges: .bottom)

            // === 編集オーバーレイ
            if editMode != .none {
                EditOverlay(
                    mode: editMode,
                    points: $editPoints,
                    onFinish: { finishEdit() },
                    onCancel: { cancelEdit() }
                )
            }

            // === POIリスト（下部）
            if let active = poi.active, !poi.results.isEmpty {
                BottomPOIList(
                    kind: active,
                    items: poi.results,
                    distanceFrom: searchRegion.center,
                    onSelect: { _ in /* TODO: 寄り道 */ },
                    onClose: { poi.clear() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        // 位置権限＆更新開始
        .onAppear { location.start() }
        // 現在地追従（任意でOFFにもできるようにhookだけ用意）
        .onReceive(location.$lastCoordinate) { coord in
            guard followUser, let c = coord else { return }
            camera = .camera(
                MapCamera(centerCoordinate: c,
                          distance: 1200, heading: 0, pitch: 0)
            )
        }
        .sheet(isPresented: $showingSave) {
            SaveSheet(title: "ルートを保存", name: $saveName) {
                let coords = pointsFromEdit(points: editPoints,
                                            in: UIScreen.main.bounds.size,
                                            center: searchRegion.center)
                store.save(name: saveName.isEmpty ? "未命名ルート" : saveName, points: coords)
                saveName = ""
                editMode = .none
            }
        }
        .sheet(isPresented: $showLoadListSheet) {
            LoadListSheet(
                routes: store.routes,
                onLoad: { r in store.selected = r; nav.isNavigating = false },
                onShare: { _ in /* TODO: 共有 */ }
            )
        }
        .sheet(isPresented: $showingRouteOption) {
            RouteOptionSheet(useHighway: $nav.useHighway)
        }
        .onAppear {
            // デモ：ナビ中レーン減少通知（擬似）
            DispatchQueue.main.asyncAfter(deadline: .now()+3) {
                if nav.isNavigating { nav.laneDropMessage = "1 km先で 3 → 2 車線" }
            }
            DispatchQueue.main.asyncAfter(deadline: .now()+10) { nav.laneDropMessage = nil }
        }
    }

    // MARK: - 編集モード遷移
    private func startCreateRoute() {
        editMode = .createNew
        editPoints = []
    }
    private func startEditRoute() {
        editMode = .editExisting
        editPoints = []
    }
    private func finishEdit() {
        let coords = pointsFromEdit(points: editPoints,
                                    in: UIScreen.main.bounds.size,
                                    center: searchRegion.center)
        store.selected = NavRouteModel(name: "編集中ルート", points: coords)
        editMode = .none
    }
    private func cancelEdit() { editMode = .none }

    // 画面座標→ざっくり地図座標（モック）
    private func pointsFromEdit(points: [CGPoint], in size: CGSize, center: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        guard !points.isEmpty else { return [] }
        return points.map { p in
            let dx = (Double(p.x/size.width) - 0.5) * 0.02
            let dy = (Double(p.y/size.height) - 0.5) * -0.02
            return CLLocationCoordinate2D(latitude: center.latitude + dy,
                                          longitude: center.longitude + dx)
        }
    }

    private func showLoadList() { showLoadListSheet = true }
}
