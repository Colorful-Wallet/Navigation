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
    // 既存状態
    @StateObject private var nav = NavigationState()
    @StateObject private var poi = QuickPOISearch()
    @StateObject private var store = RouteStore()
    @StateObject private var place = PlaceSearch()
    @StateObject private var location = LocationManager()

    // 追加：編集/ルート
    @StateObject private var engine = RouteEngine()
    @StateObject private var editor = RouteEditor()

    // Apple純正風サジェスト
    @StateObject private var sugg = SearchCompleter()

    // Map
    @State private var camera: MapCameraPosition
    @State private var searchRegion: MKCoordinateRegion

    // 編集モード
    @State private var editMode: EditModeKind = .none
    @State private var draggingIndex: Int? = nil
    @State private var pendingDraggedCoord: CLLocationCoordinate2D? = nil

    // 保存/ロード
    @State private var showingSave = false
    @State private var saveName = ""
    @State private var showLoadListSheet = false

    // 検索
    @State private var searchText = ""
    @State private var showingRouteOption = false

    // 現在地
    @State private var followUser = true

    // ナビ用
    @State private var activeNavRoute: MKRoute? = nil

    init() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.0116, longitude: 135.7681),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        _camera = State(initialValue: .region(region))
        _searchRegion = State(initialValue: region)
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                ZStack {
                    // === Map（オーバーレイ含む）
                    Map(position: $camera) {
                        mapLayers(proxy: proxy) // ← MapContentBuilder で分割
                    }
                    .onMapCameraChange(frequency: .continuous) { ctx in
                        searchRegion = ctx.region
                    }
                    .mapControls { MapUserLocationButton(); MapCompass() }
                    .ignoresSafeArea()

                    // === 編集モード時：タップ追加（ドラッグでない時）
                    if editMode != .none {
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        if draggingIndex != nil { return } // ドラッグだったら無視
                                        if let coord = proxy.convert(value.location, from: .local) {
                                            Task { await handleTapAdd(at: coord) }
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
                                activeNavRoute = nil
                                nav.isNavigating = false
                                store.selected = nil
                            }
                            .buttonStyle(.borderedProminent)

                            Button("ルート編集") {
                                editMode = .editExisting
                                editor.reset()
                                activeNavRoute = nil
                                nav.isNavigating = false
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
                            onSelect: { _ in /* TODO: 寄り道 */ },
                            onClose: { poi.clear() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            // Apple純正風 検索UI
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("場所・住所を検索"))
            .onChange(of: searchText) { new in
                sugg.update(query: new, region: searchRegion)
            }
            .searchSuggestions {
                // MKLocalSearchCompletion は Hashable でないため enumerated で安定ID付与
                ForEach(Array(sugg.suggestions.enumerated()), id: \.offset) { _, s in
                    Button {
                        searchText = s.title
                        searchPlaceAndZoom(name: s.title + " " + s.subtitle, region: searchRegion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.body)
                            if !s.subtitle.isEmpty {
                                Text(s.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onSubmit(of: .search) {
                searchPlaceAndZoom(name: searchText, region: searchRegion)
            }
        }
        // 位置権限＆更新開始
        .onAppear { location.start() }
        // 現在地追従 + 交差点までの距離更新
        .onReceive(location.$lastCoordinate) { coord in
            guard let c = coord else { return }
            if followUser {
                camera = .camera(MapCamera(centerCoordinate: c, distance: 1200, heading: 0, pitch: 0))
            }
            if let route = activeNavRoute {
                updateHUD(route: route, user: c)
            }
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

    // MARK: - Map Layers（※ View ではなく MapContent を返す）
    @MapContentBuilder
    private func mapLayers(proxy: MapProxy) -> some MapContent {

        // 1) 編集中セグメント（道路スナップ済み）
        ForEach(editor.segments.indices, id: \.self) { i in
            MapPolyline(coordinates: coords(from: editor.segments[i]))
                .stroke(.blue, lineWidth: 5)
        }

        // 2) ナビ経路（優先表示）
        if let navRoute = activeNavRoute {
            MapPolyline(coordinates: coords(from: navRoute.polyline))
                .stroke(.green, lineWidth: 6)
        }

        // 3) 目的地検索の結果
        ForEach(place.results) { item in
            Marker(item.name, coordinate: item.coordinate)
        }

        // 4) POI ピン
        ForEach(poi.results) { item in
            Marker(item.name, coordinate: item.coordinate)
        }

        // 5) 編集点（ドラッグ可）
        ForEach(editor.points.indices, id: \.self) { idx in
            Annotation("", coordinate: editor.points[idx]) {  // MapAnnotation は iOS17で非推奨
                DraggableEditDot(
                    onDragChanged: { loc in
                        if draggingIndex == nil, let hit = hitTestPoint(loc, proxy: proxy) {
                            draggingIndex = hit
                        }
                        if let i = draggingIndex,
                           let c = proxy.convert(loc, from: .local) {
                            pendingDraggedCoord = c
                            editor.points[i] = c
                        }
                    },
                    onDragEnded: {
                        if let i = draggingIndex, let new = pendingDraggedCoord {
                            Task { await recalcAround(index: i, newCoord: new) }
                        }
                        draggingIndex = nil
                        pendingDraggedCoord = nil
                    }
                )
            }
        }
    }

    // MARK: - 目的地検索→ズーム＆ナビ開始
    private func searchPlaceAndZoom(name: String, region: MKCoordinateRegion) {
        place.search(query: name, in: region)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let first = place.results.first {
                camera = .camera(MapCamera(centerCoordinate: first.coordinate, distance: 1500, heading: 0, pitch: 0))
                if let cur = location.lastCoordinate {
                    Task { await startNavigation(from: cur, to: first.coordinate) }
                }
            }
        }
    }

    private func startNavigation(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async {
        do {
            let route = try await engine.route(from: from, to: to, allowHighways: nav.useHighway)
            activeNavRoute = route
            nav.isNavigating = true
            nav.remainingDistanceM = route.distance
            nav.remainingTimeSec = route.expectedTravelTime
            nav.nextDistanceM = route.steps.first?.distance ?? route.distance
            nav.progress = 0
        } catch {
            // 無視（UI変更なし）
        }
    }

    // MARK: - 編集：タップ追加とドラッグ再計算
    private func handleTapAdd(at coord: CLLocationCoordinate2D) async {
        switch editMode {
        case .none: return
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
            } catch {
                editor.points.append(coord) // 失敗時は点のみ
            }
        }
    }

    private func recalcAround(index: Int, newCoord: CLLocationCoordinate2D) async {
        guard index < editor.points.count else { return }
        editor.points[index] = newCoord

        // 前区間
        if index - 1 >= 0 {
            let a = editor.points[index - 1]
            do {
                let r = try await engine.route(from: a, to: newCoord, allowHighways: nav.useHighway)
                if index - 1 < editor.segments.count { editor.segments[index - 1] = r.polyline }
            } catch { }
        }
        // 後区間
        if index + 1 < editor.points.count {
            let b = editor.points[index + 1]
            do {
                let r = try await engine.route(from: newCoord, to: b, allowHighways: nav.useHighway)
                if index < editor.segments.count { editor.segments[index] = r.polyline }
            } catch { }
        }
    }

    // 画面座標から「近い編集点」をヒットテスト
    private func hitTestPoint(_ loc: CGPoint, proxy: MapProxy) -> Int? {
        let threshold: CGFloat = 28
        var bestIdx: Int? = nil
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, c) in editor.points.enumerated() {
            let p = proxy.convert(c, to: .local) ?? .zero
            let d = hypot(p.x - loc.x, p.y - loc.y)
            if d < threshold && d < bestDist {
                bestDist = d; bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - HUD更新（次の交差点まで）
    private func updateHUD(route: MKRoute, user: CLLocationCoordinate2D) {
        var nearestStepIndex = 0
        var nearestDistance = CLLocationDistance.greatestFiniteMagnitude
        for (i, step) in route.steps.enumerated() {
            let d = distanceToPolyline(from: user, polyline: step.polyline)
            if d < nearestDistance { nearestDistance = d; nearestStepIndex = i }
        }

        let remainInStep = remainingDistanceOnPolyline(from: user, polyline: route.steps[nearestStepIndex].polyline)

        nav.nextDistanceM = max(0, remainInStep)
        let passed = routeDistanceUptoStep(route, index: nearestStepIndex)
                   + (route.steps[nearestStepIndex].distance - remainInStep)
        nav.remainingDistanceM = max(0, route.distance - passed)
        nav.progress = max(0, min(1, passed / max(route.distance, 1)))
        nav.remainingTimeSec = max(0, route.expectedTravelTime * (nav.remainingDistanceM / max(route.distance, 1)))
    }

    // --- Utility: MKPolyline <-> 距離
    private func coords(from pl: MKPolyline) -> [CLLocationCoordinate2D] {
        var arr = Array(repeating: kCLLocationCoordinate2DInvalid, count: pl.pointCount)
        pl.getCoordinates(&arr, range: NSRange(location: 0, length: pl.pointCount))
        return arr
    }

    private func distanceToPolyline(from point: CLLocationCoordinate2D, polyline: MKPolyline) -> CLLocationDistance {
        let pts = coords(from: polyline).map { MKMapPoint($0) }
        let p = MKMapPoint(point)
        var best = CLLocationDistance.greatestFiniteMagnitude
        for i in 0..<(pts.count - 1) {
            let seg = distancePointToSegment(p, pts[i], pts[i+1])
            if seg < best { best = seg }
        }
        return best
    }

    private func remainingDistanceOnPolyline(from point: CLLocationCoordinate2D, polyline: MKPolyline) -> CLLocationDistance {
        let cs = coords(from: polyline)
        guard cs.count >= 2 else { return 0 }
        let pts = cs.map { MKMapPoint($0) }
        let p = MKMapPoint(point)

        var closestIndex = 0
        var closestDist = CLLocationDistance.greatestFiniteMagnitude
        var closestProj = p

        for i in 0..<(pts.count - 1) {
            let (proj, dist) = projectPointToSegment(p, pts[i], pts[i+1])
            if dist < closestDist {
                closestDist = dist
                closestIndex = i
                closestProj = proj
            }
        }

        var remain: CLLocationDistance = closestProj.distance(to: pts[closestIndex+1])
        if closestIndex + 1 < pts.count - 1 {
            for j in (closestIndex + 1)..<(pts.count - 1) {
                remain += pts[j].distance(to: pts[j+1])
            }
        }
        return remain
    }

    private func routeDistanceUptoStep(_ route: MKRoute, index: Int) -> CLLocationDistance {
        guard index > 0 else { return 0 }
        return route.steps.prefix(index).reduce(0) { $0 + $1.distance }
    }

    // 幾何ユーティリティ
    private func distancePointToSegment(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> CLLocationDistance {
        return projectPointToSegment(p, a, b).1
    }
    private func projectPointToSegment(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint)
        -> (MKMapPoint, CLLocationDistance)
    {
        let apx = p.x - a.x, apy = p.y - a.y
        let abx = b.x - a.x, aby = b.y - a.y
        let ab2 = abx*abx + aby*aby
        let t = max(0, min(1, (apx*abx + apy*aby) / (ab2 == 0 ? 1 : ab2)))
        let proj = MKMapPoint(x: a.x + abx*t, y: a.y + aby*t)
        return (proj, proj.distance(to: p))
    }

    private func showLoadList() { showLoadListSheet = true }
}

// ドラッグ用の小さな点 View
private struct DraggableEditDot: View {
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onDragChanged($0.location) }
                    .onEnded { _ in onDragEnded() }
            )
    }
}
