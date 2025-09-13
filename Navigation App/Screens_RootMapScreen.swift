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
    // 状態
    @StateObject private var nav = NavigationState()
    @StateObject private var poi = QuickPOISearch()
    @StateObject private var store = RouteStore()
    @StateObject private var place = PlaceSearch()
    @StateObject private var location = LocationManager()

    // ルーティング
    @StateObject private var engine = RouteEngine()
    @StateObject private var editor = RouteEditor()

    // 検索補完
    @StateObject private var sugg = SearchCompleter()

    // Map
    @State private var camera: MapCameraPosition
    @State private var searchRegion: MKCoordinateRegion

    // 編集
    enum EditModeKind { case none, createNew, editExisting }
    @State private var editMode: EditModeKind = .none
    @State private var draggingIndex: Int? = nil
    @State private var pendingDraggedCoord: CLLocationCoordinate2D? = nil

    // 保存/ロード/検索シート
    @State private var showingSave = false
    @State private var saveName = ""
    @State private var showLoadListSheet = false
    @State private var showSearchSheet = false

    // 検索
    @State private var searchText = ""
    @State private var showingRouteOption = false

    // 現在地追従
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
                    // === Map =====================================================
                    Map(position: $camera) {
                        mapLayers(proxy: proxy)
                    }
                    // 編集中でもパン/ズーム/回転OK。移動量が小さいときだけ「タップ扱い」。
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard editMode != .none, draggingIndex == nil else { return }
                                let move = hypot(value.translation.width, value.translation.height)
                                guard move < 5 else { return } // パン判定
                                // 1) 既存ルート線上タップなら挿入
                                if tryInsertPointOnRoute(from: value.location, proxy: proxy) {
                                    return
                                }
                                // 2) それ以外は通常追加
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

                    // === 通常ツールバー行（編集中は非表示） =======================
                    if editMode == .none {
                        VStack {
                            HStack {
                                Button("ルート新規作成") {
                                    editMode = .createNew
                                    followUser = false                    // 追従停止
                                    editor.reset()
                                    activeNavRoute = nil
                                    nav.isNavigating = false
                                    store.selected = nil
                                }
                                .buttonStyle(.borderedProminent)

                                Button("編集") {
                                    editMode = .editExisting
                                    followUser = false                    // 追従停止
                                    if let r = activeNavRoute,
                                       editor.points.isEmpty,
                                       let start = location.lastCoordinate {
                                        let end = coords(from: r.polyline).last ?? start
                                        editor.points = [start, end]
                                        editor.segments = [r.polyline]
                                    }
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                if activeNavRoute != nil && !nav.isNavigating {
                                    Button("開始") {
                                        nav.isNavigating = true
                                        followUser = true                  // ナビでは追従ON
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                if nav.isNavigating {
                                    Button("終了") {
                                        nav.isNavigating = false
                                    }
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
                            Button {
                                showSearchSheet = true
                            } label: {
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
            // ==== ナビゲーションバー（編集中だけ黒＋キャンセル） ===================
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if editMode != .none {
                    ToolbarItem(placement: .principal) {
                        Text(editMode == .createNew ? "ルート作成中" : "ルート編集中")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
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
            if let route = activeNavRoute, nav.isNavigating {
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
        // 現在地
        UserAnnotation()

        // 編集中セグメント（青/5pt）
        ForEach(editor.segments.indices, id: \.self) { i in
            MapPolyline(coordinates: coords(from: editor.segments[i]))
                .stroke(.blue, lineWidth: 5)
        }

        // ナビ経路（緑/10pt）
        if let navRoute = activeNavRoute {
            MapPolyline(coordinates: coords(from: navRoute.polyline))
                .stroke(.green, lineWidth: 10)
        }

        // 検索結果
        ForEach(place.results) { item in
            Marker(item.name, coordinate: item.coordinate)
        }
        // POI
        ForEach(poi.results) { item in
            Marker(item.name, coordinate: item.coordinate)
        }

        // 編集点（番号入り, ドラッグ可）— 編集中のみ
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

    // MARK: - 検索→ルート表示（ナビは開始しない）
    private func searchPlaceAndShowRoute(name: String, region: MKCoordinateRegion) {
        place.search(query: name, in: region)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let dest = place.results.first?.coordinate else { return }
            if let cur = location.lastCoordinate {
                Task {
                    do {
                        let route = try await engine.route(from: cur, to: dest, allowHighways: nav.useHighway)
                        activeNavRoute = route
                        nav.isNavigating = false
                        editor.reset() // 編集は「編集」ボタンで
                        camera = .camera(MapCamera(centerCoordinate: dest, distance: 1500, heading: 0, pitch: 0))
                    } catch { }
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

    // === 線上タップで挿入：前後のセグメントを「置換＋挿入」で必ず繋ぐ ==========
    private func tryInsertPointOnRoute(from tapLocal: CGPoint, proxy: MapProxy) -> Bool {
        guard editMode != .none else { return false }
        guard !editor.segments.isEmpty else { return false }

        let threshold: CGFloat = 24 // px
        var best: (segIndex: Int, coord: CLLocationCoordinate2D, screenDist: CGFloat)? = nil

        for (i, pl) in editor.segments.enumerated() {
            if let hit = nearestOnPolyline(pl, toLocalPoint: tapLocal, proxy: proxy) {
                if best == nil || hit.screenDist < best!.screenDist {
                    best = (i, hit.coord, hit.screenDist)
                }
            }
        }

        guard let b = best, b.screenDist <= threshold else { return false }

        let insertIndex = min(b.segIndex + 1, editor.points.count)
        editor.points.insert(b.coord, at: insertIndex)
        // ここが肝：前後2区間を再計算し、segments を置換＋挿入で更新
        Task { await rebuildSegmentsAroundInsertion(insertedAt: insertIndex) }
        return true
    }

    private func rebuildSegmentsAroundInsertion(insertedAt i: Int) async {
        // i は points[i-1]—points[i] の間に挿入された新しい点のインデックス
        // 1) 前区間： [i-1] → [i] を計算し、segments[i-1] を置換
        if i - 1 >= 0 && i < editor.points.count {
            let a = editor.points[i - 1], b = editor.points[i]
            if let r = try? await engine.route(from: a, to: b, allowHighways: nav.useHighway) {
                if i - 1 < editor.segments.count { editor.segments[i - 1] = r.polyline }
                else { editor.segments.append(r.polyline) }
            }
        }
        // 2) 後区間： [i] → [i+1] を計算し、segments[i] に「挿入」
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
        let cs = coords(from: poly)
        guard cs.count >= 2 else { return nil }
        let pts = cs.map { MKMapPoint($0) }

        var bestDist = CGFloat.greatestFiniteMagnitude
        var bestCoord = cs[0]
        var bestSeg = 0

        for j in 0..<(pts.count - 1) {
            let (proj, _) = projectPointToSegment(P, pts[j], pts[j+1])
            let projCoord = proj.coordinate
            let screenPt = proxy.convert(projCoord, to: .local) ?? .zero
            let d = hypot(screenPt.x - tapLocal.x, screenPt.y - tapLocal.y)
            if d < bestDist {
                bestDist = d
                bestCoord = projCoord
                bestSeg = j
            }
        }
        return (bestCoord, bestDist, bestSeg)
    }

    // 画面座標→近い編集点（グローバル座標版）
    private func hitTestPointGlobal(_ global: CGPoint, proxy: MapProxy) -> Int? {
        let threshold: CGFloat = 28
        var bestIdx: Int? = nil
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, c) in editor.points.enumerated() {
            let p = proxy.convert(c, to: .global) ?? .zero
            let d = hypot(p.x - global.x, p.y - global.y)
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

    private func cancelEditing() {
        editor.reset()
        editMode = .none
        followUser = true // 編集終了後は追従を戻す（必要に応じて変更）
    }
    private func showLoadList() { showLoadListSheet = true }
}

// ====== 下部・検索ボトムシート（安全版） ======================================
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

// ====== ドラッグ用の点（番号入り・グローバル座標で通知） =====================
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
