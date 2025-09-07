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

    // ルーティング関連
    @StateObject private var engine = RouteEngine()
    @StateObject private var editor = RouteEditor()

    // Mapカメラ / 表示リージョン
    @State private var camera: MapCameraPosition
    @State private var searchRegion: MKCoordinateRegion

    // 編集関連
    @State private var editMode: EditModeKind = .none

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
        MapReader { proxy in
            ZStack {
                // === Map（オーバーレイ含む）
                Map(position: $camera) {
                    // 1) 編集済みセグメントを描画（道路スナップ済み）
                    ForEach(Array(editor.segments.enumerated()), id: \.offset) { _, seg in
                        let coords = coords(from: seg)
                        MapPolyline(coordinates: coords).stroke(.blue, lineWidth: 5)
                    }

                    // 2) 保存済みルートを点でプレビュー（任意）
                    if let r = store.selected, !r.points.isEmpty {
                        ForEach(Array(r.points.enumerated()), id: \.offset) { _, c in
                            Annotation("", coordinate: c) {
                                Circle().frame(width: 4, height: 4).foregroundStyle(.blue)
                            }
                        }
                    }

                    // 3) 目的地検索の結果
                    ForEach(place.results) { item in
                        Marker(item.name, coordinate: item.coordinate)
                    }

                    // 4) POIピン
                    ForEach(poi.results) { item in
                        Marker(item.name, coordinate: item.coordinate)
                    }
                }
                .onMapCameraChange(frequency: .continuous) { ctx in
                    searchRegion = ctx.region
                }
                .mapControls { MapUserLocationButton(); MapCompass() }
                .ignoresSafeArea()

                // === 編集モード時のみ：タップ位置→座標のジェスチャ
                if editMode != .none {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let pt = value.location
                                    if let coord = proxy.convert(pt, from: .local) {
                                        Task { await handleMapTap(at: coord) }
                                    }
                                }
                        )
                }

                // === 上部：新規/編集 + クイック検索
                VStack(spacing: 8) {
                    HStack {
                        Button("ルート新規作成") {
                            editMode = .createNew
                            editor.reset()
                            store.selected = nil
                        }
                        .buttonStyle(.borderedProminent)

                        Button("ルート編集") {
                            editMode = .editExisting
                            editor.reset()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        if !editor.segments.isEmpty {
                            Button("保存") { showingSave = true }
                        }
                        Button("ロード") { showLoadList() }
                    }
                    .padding(.horizontal, 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach([QuickPOIKind.gas, .ev, .toilet, .conv]) { k in
                                Button {
                                    if poi.active == k { poi.clear() }
                                    else { poi.run(k, around: searchRegion.center, span: searchRegion.span) }
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

                // === 下部：検索ボックス（次ステップで .searchable に置換予定）
                VStack {
                    Spacer()
                    SearchBar(
                        text: $searchText,
                        onSearch: { text in
                            place.search(query: text, in: searchRegion)
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

                // === DriveHUD（ナビ中のみ表示）
                if nav.isNavigating {
                    VStack { Spacer()
                        DriveHUD().environmentObject(nav)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }

                // === POIリスト（下部）
                if let active = poi.active, !poi.results.isEmpty {
                    BottomPOIList(
                        kind: active,
                        items: poi.results,
                        distanceFrom: searchRegion.center,
                        onSelect: { _ in /* TODO */ },
                        onClose: { poi.clear() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        // 位置権限＆更新開始
        .onAppear { location.start() }
        // 現在地追従
        .onReceive(location.$lastCoordinate) { coord in
            guard followUser, let c = coord else { return }
            camera = .camera(MapCamera(centerCoordinate: c, distance: 1200, heading: 0, pitch: 0))
        }
        // 保存
        .sheet(isPresented: $showingSave) {
            SaveSheet(title: "ルートを保存", name: $saveName) {
                store.save(name: saveName.isEmpty ? "未命名ルート" : saveName, points: editor.points)
                saveName = ""
                editMode = .none
            }
        }
        // ロード
        .sheet(isPresented: $showLoadListSheet) {
            LoadListSheet(routes: store.routes,
                          onLoad: { r in store.selected = r; nav.isNavigating = false },
                          onShare: { _ in })
        }
        // ルートオプション
        .sheet(isPresented: $showingRouteOption) {
            RouteOptionSheet(useHighway: $nav.useHighway)
        }
        // デモ通知
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()+3) {
                if nav.isNavigating { nav.laneDropMessage = "1 km先で 3 → 2 車線" }
            }
            DispatchQueue.main.asyncAfter(deadline: .now()+10) { nav.laneDropMessage = nil }
        }
    }

    // MARK: - 編集タップ処理（道路スナップ）
    private func handleMapTap(at coord: CLLocationCoordinate2D) async {
        switch editMode {
        case .none:
            return

        case .createNew, .editExisting:
            if editor.points.isEmpty {
                editor.points.append(coord)
                return
            }
            guard let last = editor.points.last else { return }
            do {
                let route = try await engine.route(from: last, to: coord, allowHighways: nav.useHighway)
                editor.points.append(coord)
                editor.segments.append(route.polyline)

                // HUD（モック）
                nav.nextSymbol = "arrow.turn.up.right"
                nav.nextDistanceM = route.steps.first?.distance ?? route.distance
                nav.remainingDistanceM = route.distance
                nav.remainingTimeSec = route.expectedTravelTime

            } catch {
                editor.points.append(coord) // 失敗時は点だけ保持
            }
        }
    }

    // MKPolyline -> [CLLocationCoordinate2D]
    private func coords(from pl: MKPolyline) -> [CLLocationCoordinate2D] {
        var arr = Array(repeating: kCLLocationCoordinate2DInvalid, count: pl.pointCount)
        pl.getCoordinates(&arr, range: NSRange(location: 0, length: pl.pointCount))
        return arr
    }

    private func showLoadList() { showLoadListSheet = true }
}
