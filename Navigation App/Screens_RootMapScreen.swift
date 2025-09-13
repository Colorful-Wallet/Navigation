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
    // === 既存の状態オブジェクト ===
    @StateObject private var nav = NavigationState()
    @StateObject private var poi = QuickPOISearch()
    @StateObject private var store = RouteStore()
    @StateObject private var place = PlaceSearch()
    @StateObject private var location = LocationManager()

    // ルーティング/編集
    @StateObject private var engine = RouteEngine()
    @StateObject private var editor = RouteEditor()

    // 検索補完
    @StateObject private var sugg = SearchCompleter()

    // Map
    @State private var camera: MapCameraPosition
    @State private var searchRegion: MKCoordinateRegion

    // 編集モード
    enum EditModeKind { case none, createNew, editExisting }
    @State private var editMode: EditModeKind = .none
    @State private var draggingIndex: Int? = nil
    @State private var pendingDraggedCoord: CLLocationCoordinate2D? = nil

    // 保存/ロード/検索
    @State private var showingSave = false
    @State private var saveName = ""
    @State private var showLoadListSheet = false
    @State private var showSearchSheet = false
    @State private var searchText = ""
    @State private var showingRouteOption = false

    // 現在地追従
    @State private var followUser = true

    // ナビ用（Appleの検索ルート or カスタム作成ルート）
    @State private var activeNavRoute: MKRoute? = nil             // Apple検索の単一ルート
    @State private var activeCustomNav: [MKPolyline]? = nil       // 編集で作った複合ルート

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
                    // === Map =====================================================
                    Map(position: $camera) {
                        mapLayers(proxy: proxy)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard editMode != .none, draggingIndex == nil else { return }
                                let move = hypot(value.translation.width, value.translation.height)
                                guard move < 5 else { return } // パンなら無視
                                // 1) 線上タップなら挿入
                                if tryInsertPointOnRoute(from: value.location, proxy: proxy) { return }
                                // 2) それ以外は末尾追加
                                if let coord = proxy.convert(value.location, from: .local) {
                                    Task { await handleTapAdd(at: coord) }
                                }
                            }
                    )
                    .onMapCameraChange(frequency: .continuous) { ctx in
                        searchRegion = ctx.region
                    }
                    .mapControls { MapUserLocationButton(); MapCompass() }
                    .ignoresSafeArea()

                    // === 通常ツールバー相当の行（編集中は非表示） ==================
                    if editMode == .none {
                        VStack {
                            HStack {
                                Button("ルート新規作成") {
                                    editMode = .createNew
                                    followUser = false
                                    editor.reset()
                                    activeCustomNav = nil
                                    activeNavRoute = nil
                                    nav.isNavigating = false
                                    store.selected = nil
                                }
                                .buttonStyle(.borderedProminent)

                                Button("編集") {
                                    // 検索で出来たルートを編集に取り込む用途
                                    guard let r = activeNavRoute else { return }
                                    editMode = .editExisting
                                    followUser = false
                                    editor.reset()
                                    // 現在地 → 目的地 の単一路線を「編集線」として仮置き
                                    let end = coords(from: r.polyline).last ?? searchRegion.center
                                    if let cur = location.lastCoordinate {
                                        editor.points = [cur, end]
                                    } else {
                                        editor.points = [searchRegion.center, end]
                                    }
                                    editor.segments = [r.polyline]
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                if activeNavRoute != nil && !nav.isNavigating {
                                    Button("開始") {
                                        nav.isNavigating = true
                                        followUser = true
                                        // Apple検索ルートで開始
                                        if let r = activeNavRoute {
                                            nav.remainingDistanceM = r.distance
                                            nav.remainingTimeSec = r.expectedTravelTime
                                            nav.nextDistanceM = r.steps.first?.distance ?? r.distance
                                            nav.progress = 0
                                        }
                                        activeCustomNav = nil
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                if nav.isNavigating {
                                    Button("終了") { nav.isNavigating = false }
                                        .buttonStyle(.bordered)
                                }

                                if !editor.segments.isEmpty {
                                    Button("保存") { showingSave = true }
                                }
                                Button("ロード") { showLoadList() }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                            Spacer()
                        }
                    }

                    // === 左サイド：ナビ中クイック ================================
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

                    // === 車線減少バナー ==========================================
                    VStack {
                        if let msg = nav.laneDropMessage {
                            LaneDropBanner(message: msg).padding(.top, 8)
                        }
                        Spacer()
                    }
                    .animation(.easeInOut, value: nav.laneDropMessage)

                    // === DriveHUD（ナビ中のみ） ==================================
                    if nav.isNavigating {
                        VStack { Spacer()
                            DriveHUD().environmentObject(nav)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                        .ignoresSafeArea(edges: .bottom)
                    }

                    // === 下部：検索ボタン & POIリスト =============================
                    VStack {
                        Spacer()

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

                        HStack {
                            Spacer()
                            Button { showSearchSheet = true } label: {
                                Label("検索", systemImage: "magnifyingglass")
                                    .font(.headline)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(.bottom, 12)
                            .padding(.trailing, 12)
                        }
                    }
                }
            }
            // ==== ナビゲーションバー（編集中用の黒バー + 操作） ====================
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if editMode != .none {
                    // タイトル（黒バー）
                    ToolbarItem(placement: .principal) {
                        Text(editMode == .createNew ? "ルート作成中" : "ルート編集中")
                            .font(.headline)
                    }
                    // 右側：確定/保存/案内開始/キャンセル
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button("確定") { zoomToFitCurrentRoute() }       // 俯瞰
                        Button("保存") { showingSave = true }            // 名前入力→保存
                        Button("ルート案内開始") {
                            Task { await startNavigationForEditorRoute() }
                        }
                        Button("キャンセル") { cancelEditing() }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(editMode != .none ? .black : Color(.systemBackground), for: .navigationBar)
            .toolbarColorScheme(editMode != .none ? .dark : .light, for: .navigationBar)
        }
        // 現在地追従 + HUD更新
        .onAppear { location.start() }
        .onReceive(location.$lastCoordinate) { coord in
            guard let c = coord else { return }
            if followUser {
                camera = .camera(MapCamera(centerCoordinate: c, distance: 1200, heading: 0, pitch: 0))
            }
            if nav.isNavigating {
                if let r = activeNavRoute {
                    updateHUD(appleRoute: r, user: c)
                } else if let pls = activeCustomNav {
                    updateHUD(custom: pls, user: c)
                }
            }
        }
        // 保存
        .sheet(isPresented: $showingSave) {
            SaveSheet(title: "ルートを保存", name: $saveName) {
                store.save(name: saveName.isEmpty ? "未命名ルート" : saveName, points: editor.points)
                saveName = ""
                // 確定/案内開始はそのまま使えるのでモードは維持
            }
        }
        // ロード
        .sheet(isPresented: $showLoadListSheet) {
            LoadListSheet(routes: store.routes,
                          onLoad: { r in store.selected = r; nav.isNavigating = false },
                          onShare: { _ in })
        }
        // ルートオプション
        .sheet(isPresented: $showingRouteOption) { RouteOptionSheet(useHighway: $nav.useHighway) }
        // 検索ボトムシート
        .sheet(isPresented: $showSearchSheet) {
            SearchBottomSheet(
                text: $searchText,
                suggestions: sugg.suggestions,
                onChange: { q in sugg.update(query: q, region: searchRegion) },
                onSelect: { title, subtitle in
                    searchText = title
                    showSearchSheet = false
                    searchPlaceAndShowRoute(name: title + " " + subtitle, region: searchRegion)
                },
                onSearch: { q in
                    showSearchSheet = false
                    searchPlaceAndShowRoute(name: q, region: searchRegion)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Map Layers（MapContentBuilder）
    @MapContentBuilder
    private func mapLayers(proxy: MapProxy) -> some MapContent {
        UserAnnotation()

        // 編集線（青）— 常に表示
        ForEach(editor.segments.indices, id: \.self) { i in
            MapPolyline(coordinates: coords(from: editor.segments[i]))
                .stroke(.blue, lineWidth: 5)
        }

        // Apple検索のナビ線（緑）— 編集中は隠す
        if editMode == .none, let navRoute = activeNavRoute {
            MapPolyline(coordinates: coords(from: navRoute.polyline))
                .stroke(.green, lineWidth: 10)
        }

        // カスタムナビ線（緑）— 編集中は隠す
        if editMode == .none, let custom = activeCustomNav {
            ForEach(Array(custom.enumerated()), id: \.offset) { _, pl in
                MapPolyline(coordinates: coords(from: pl))
                    .stroke(.green, lineWidth: 10)
            }
        }

        // 検索結果ピン
        ForEach(place.results) { item in Marker(item.name, coordinate: item.coordinate) }
        // POIピン
        ForEach(poi.results) { item in Marker(item.name, coordinate: item.coordinate) }

        // 編集点（番号付き・ドラッグ可）
        if editMode != .none {
            ForEach(editor.points.indices, id: \.self) { idx in
                Annotation("", coordinate: editor.points[idx]) {
                    DraggableEditDot(
                        text: String(idx + 1),
                        onDragChangedGlobal: { globalPt in
                            if draggingIndex == nil,
                               let hit = hitTestPointGlobal(globalPt, proxy: proxy) {
                                draggingIndex = hit
                            }
                            if let i = draggingIndex,
                               let c = proxy.convert(globalPt, from: .global) {
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
    }

    // MARK: - 「確定」＝ 俯瞰にズーム
    private func zoomToFitCurrentRoute() {
        var minLat =  90.0, maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0
        func eat(_ c: CLLocationCoordinate2D) {
            minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        if !editor.points.isEmpty {
            editor.points.forEach(eat)
        } else if let r = activeNavRoute {
            coords(from: r.polyline).forEach(eat)
        } else if let pls = activeCustomNav {
            pls.forEach { coords(from: $0).forEach(eat) }
        } else {
            return
        }
        // パディング係数
        let pad = 1.15
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat)/2,
                                            longitude: (minLon + maxLon)/2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * pad, 0.005),
                                    longitudeDelta: max((maxLon - minLon) * pad, 0.005))
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - 検索→ルート表示（Appleの単一路線）
    private func searchPlaceAndShowRoute(name: String, region: MKCoordinateRegion) {
        place.search(query: name, in: region)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let dest = place.results.first?.coordinate else { return }
            if let cur = location.lastCoordinate {
                Task {
                    if let route = try? await engine.route(from: cur, to: dest, allowHighways: nav.useHighway) {
                        activeNavRoute = route
                        activeCustomNav = nil
                        nav.isNavigating = false
                        editor.reset()
                        camera = .camera(MapCamera(centerCoordinate: dest, distance: 1500, heading: 0, pitch: 0))
                    }
                }
            } else {
                camera = .camera(MapCamera(centerCoordinate: dest, distance: 1500, heading: 0, pitch: 0))
            }
        }
    }

    // MARK: - 編集：タップ追加 & ドラッグ再計算
    private func handleTapAdd(at coord: CLLocationCoordinate2D) async {
        guard editMode != .none else { return }
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
            editor.points.append(coord)
        }
    }
    private func recalcAround(index: Int, newCoord: CLLocationCoordinate2D) async {
        guard index < editor.points.count else { return }
        editor.points[index] = newCoord
        // 前区間
        if index - 1 >= 0 {
            let a = editor.points[index - 1]
            if let r = try? await engine.route(from: a, to: newCoord, allowHighways: nav.useHighway),
               index - 1 < editor.segments.count {
                editor.segments[index - 1] = r.polyline
            }
        }
        // 後区間
        if index + 1 < editor.points.count {
            let b = editor.points[index + 1]
            if let r = try? await engine.route(from: newCoord, to: b, allowHighways: nav.useHighway) {
                if index < editor.segments.count { editor.segments[index] = r.polyline }
                else { editor.segments.append(r.polyline) }
            }
        }
    }

    // === 線上タップで挿入：前後区間を再計算して必ず繋ぐ ==========================
    private func tryInsertPointOnRoute(from tapLocal: CGPoint, proxy: MapProxy) -> Bool {
        guard editMode != .none, !editor.segments.isEmpty else { return false }
        let threshold: CGFloat = 24
        var best: (segIndex: Int, coord: CLLocationCoordinate2D, screenDist: CGFloat)? = nil
        for (i, pl) in editor.segments.enumerated() {
            if let hit = nearestOnPolyline(pl, toLocalPoint: tapLocal, proxy: proxy) {
                if best == nil || hit.screenDist < best!.screenDist { best = (i, hit.coord, hit.screenDist) }
            }
        }
        guard let b = best, b.screenDist <= threshold else { return false }
        let insertIndex = min(b.segIndex + 1, editor.points.count)
        editor.points.insert(b.coord, at: insertIndex)
        Task { await rebuildSegmentsAroundInsertion(insertedAt: insertIndex) }
        return true
    }
    private func rebuildSegmentsAroundInsertion(insertedAt i: Int) async {
        // 前区間 i-1 → 置換
        if i - 1 >= 0 && i < editor.points.count {
            let a = editor.points[i - 1], b = editor.points[i]
            if let r = try? await engine.route(from: a, to: b, allowHighways: nav.useHighway) {
                if i - 1 < editor.segments.count { editor.segments[i - 1] = r.polyline }
                else { editor.segments.append(r.polyline) }
            }
        }
        // 後区間 i → 挿入
        if i < editor.points.count - 1 {
            let a = editor.points[i], b = editor.points[i + 1]
            if let r = try? await engine.route(from: a, to: b, allowHighways: nav.useHighway) {
                if i < editor.segments.count { editor.segments.insert(r.polyline, at: i) }
                else { editor.segments.append(r.polyline) }
            }
        }
    }

    private func nearestOnPolyline(_ poly: MKPolyline,
                                   toLocalPoint tapLocal: CGPoint,
                                   proxy: MapProxy) -> (coord: CLLocationCoordinate2D, screenDist: CGFloat, segIndex: Int)?
    {
        guard let tapCoord = proxy.convert(tapLocal, from: .local) else { return nil }
        let P = MKMapPoint(tapCoord)
        let cs = coords(from: poly); guard cs.count >= 2 else { return nil }
        let pts = cs.map { MKMapPoint($0) }

        var bestDist = CGFloat.greatestFiniteMagnitude
        var bestCoord = cs[0]; var bestSeg = 0
        for j in 0..<(pts.count - 1) {
            let (proj, _) = projectPointToSegment(P, pts[j], pts[j+1])
            let projCoord = proj.coordinate
            let screenPt = proxy.convert(projCoord, to: .local) ?? .zero
            let d = hypot(screenPt.x - tapLocal.x, screenPt.y - tapLocal.y)
            if d < bestDist { bestDist = d; bestCoord = projCoord; bestSeg = j }
        }
        return (bestCoord, bestDist, bestSeg)
    }

    // 画面座標→近い編集点（グローバル座標）
    private func hitTestPointGlobal(_ global: CGPoint, proxy: MapProxy) -> Int? {
        let threshold: CGFloat = 28
        var bestIdx: Int? = nil
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, c) in editor.points.enumerated() {
            let p = proxy.convert(c, to: .global) ?? .zero
            let d = hypot(p.x - global.x, p.y - global.y)
            if d < threshold && d < bestDist { bestDist = d; bestIdx = i }
        }
        return bestIdx
    }

    // MARK: - ナビ開始（編集ルート）
    private func startNavigationForEditorRoute() async {
        guard !editor.points.isEmpty || !editor.segments.isEmpty else { return }
        var polylines: [MKPolyline] = []

        // 0) 現在地→①（自動）を先頭に
        if let cur = location.lastCoordinate, let first = editor.points.first {
            if let r0 = try? await engine.route(from: cur, to: first, allowHighways: nav.useHighway) {
                polylines.append(r0.polyline)
            }
        }
        // 1) 既存の編集セグメントを連結（不足があれば計算）
        if editor.segments.count >= max(0, editor.points.count - 1) {
            polylines.append(contentsOf: editor.segments)
        } else {
            // 念のため補完
            for i in 0..<(editor.points.count - 1) {
                let a = editor.points[i], b = editor.points[i+1]
                if let r = try? await engine.route(from: a, to: b, allowHighways: nav.useHighway) {
                    polylines.append(r.polyline)
                }
            }
        }

        activeCustomNav = polylines
        activeNavRoute  = nil
        nav.isNavigating = true
        followUser = true

        // 総距離/時間（簡易見積もり）
        let total = polylines.reduce(0) { $0 + polylineLength($1) }
        nav.remainingDistanceM = total
        // 想定速度 45km/h（=12.5m/s）で概算
        nav.remainingTimeSec = total / 12.5
        nav.nextDistanceM = total
        nav.progress = 0

        // 俯瞰に寄せる（任意）
        zoomToFitCurrentRoute()
    }

    // MARK: - HUD更新
    private func updateHUD(appleRoute route: MKRoute, user: CLLocationCoordinate2D) {
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

    private func updateHUD(custom polylines: [MKPolyline], user: CLLocationCoordinate2D) {
        guard !polylines.isEmpty else { return }
        // 1) 最も近いポリライン
        var nearestIndex = 0
        var nearest = CLLocationDistance.greatestFiniteMagnitude
        for (i, pl) in polylines.enumerated() {
            let d = distanceToPolyline(from: user, polyline: pl)
            if d < nearest { nearest = d; nearestIndex = i }
        }
        // 2) その線の残距離
        let remainInThis = remainingDistanceOnPolyline(from: user, polyline: polylines[nearestIndex])
        nav.nextDistanceM = max(0, remainInThis)
        // 3) 通過距離の概算
        let passedBefore = polylines.prefix(nearestIndex).reduce(0) { $0 + polylineLength($1) }
        let thisTotal = polylineLength(polylines[nearestIndex])
        let passed = passedBefore + (thisTotal - remainInThis)
        let total = polylines.reduce(0) { $0 + polylineLength($1) }

        nav.remainingDistanceM = max(0, total - passed)
        nav.progress = max(0, min(1, passed / max(total, 1)))
        nav.remainingTimeSec = nav.remainingDistanceM / 12.5 // 45km/hの簡易モデル
    }

    // --- Utility: MKPolyline <-> 距離 -----------------------------------------
    private func coords(from pl: MKPolyline) -> [CLLocationCoordinate2D] {
        var arr = Array(repeating: kCLLocationCoordinate2DInvalid, count: pl.pointCount)
        pl.getCoordinates(&arr, range: NSRange(location: 0, length: pl.pointCount))
        return arr
    }
    private func polylineLength(_ pl: MKPolyline) -> CLLocationDistance {
        let cs = coords(from: pl)
        guard cs.count >= 2 else { return 0 }
        var sum: CLLocationDistance = 0
        for i in 0..<(cs.count-1) { sum += MKMapPoint(cs[i]).distance(to: MKMapPoint(cs[i+1])) }
        return sum
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
            if dist < closestDist { closestDist = dist; closestIndex = i; closestProj = proj }
        }

        var remain: CLLocationDistance = closestProj.distance(to: pts[closestIndex+1])
        if closestIndex + 1 < pts.count - 1 {
            for j in (closestIndex + 1)..<(pts.count - 1) { remain += pts[j].distance(to: pts[j+1]) }
        }
        return remain
    }
    private func routeDistanceUptoStep(_ route: MKRoute, index: Int) -> CLLocationDistance {
        guard index > 0 else { return 0 }
        return route.steps.prefix(index).reduce(0) { $0 + $1.distance }
    }
    private func distancePointToSegment(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> CLLocationDistance {
        return projectPointToSegment(p, a, b).1
    }
    private func projectPointToSegment(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> (MKMapPoint, CLLocationDistance) {
        let apx = p.x - a.x, apy = p.y - a.y
        let abx = b.x - a.x, aby = b.y - a.y
        let ab2 = abx*abx + aby*aby
        let t = max(0, min(1, (apx*abx + apy*aby) / (ab2 == 0 ? 1 : ab2)))
        let proj = MKMapPoint(x: a.x + abx*t, y: a.y + aby*t)
        return (proj, proj.distance(to: p))
    }

    // === 汎用 ===
    private func cancelEditing() {
        editor.reset()
        editMode = .none
        followUser = true
    }
    private func showLoadList() { showLoadListSheet = true }
}

// ====== 検索ボトムシート（安全版） =============================================
private struct SearchBottomSheet: View {
    @Binding var text: String
    var suggestions: [MKLocalSearchCompletion]
    var onChange: (String) -> Void
    var onSelect: (String, String) -> Void
    var onSearch: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Capsule().fill(.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            HStack(spacing: 8) {
                TextField("場所・住所を検索", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text) { onChange($0) }
                Button(action: { onSearch(text) }) {
                    Image(systemName: "magnifyingglass.circle.fill").font(.title2)
                }
            }
            .padding(.horizontal, 12)

            List {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                    Button(action: { onSelect(s.title, s.subtitle) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title)
                            if !s.subtitle.isEmpty {
                                Text(s.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .presentationDragIndicator(.visible)
    }
}

// ====== ドラッグ用ドット（番号入り） ============================================
private struct DraggableEditDot: View {
    let text: String
    let onDragChangedGlobal: (CGPoint) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle().fill(Color.orange)
                Text(text).font(.caption2).bold().foregroundStyle(.white)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let origin = geo.frame(in: .global).origin
                        let g = CGPoint(x: origin.x + v.location.x, y: origin.y + v.location.y)
                        onDragChangedGlobal(g)
                    }
                    .onEnded { _ in onDragEnded() }
            )
        }
        .frame(width: 24, height: 24)
    }
}
