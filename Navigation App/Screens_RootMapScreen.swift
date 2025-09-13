//
//  Screens_RootMapScreen.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - ルート編集/表示/ナビの統合画面
struct RootMapScreen: View {

    // ==== 既存状態 ====
    @StateObject private var nav = NavigationState()
    @StateObject private var poi = QuickPOISearch()
    @StateObject private var store = RouteStore()
    @StateObject private var place = PlaceSearch()
    @StateObject private var location = LocationManager()

    // ルーティング / 編集
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

    // ナビ関連
    @State private var activeNavRoute: MKRoute? = nil           // Appleの単一路線ナビ
    @State private var activeCustomNav: [MKPolyline]? = nil      // 自作ルートでのナビ
    @State private var showStepList = false
    @State private var showNavOptions = false
    @State private var currentInstruction: String = "出発"

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

                    // === Map本体（編集オーバーレイ含む） =========================
                    Map(position: $camera) {
                        mapLayers(proxy: proxy)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                // 編集時のみ：タップで点追加/線上に挿入
                                guard editMode != .none, draggingIndex == nil else { return }
                                let move = hypot(value.translation.width, value.translation.height)
                                guard move < 5 else { return }
                                if tryInsertPointOnRoute(from: value.location, proxy: proxy) { return }
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

                    // === 非編集時の上部コマンド（ピル型） =========================
                    if editMode == .none && !nav.isNavigating {
                        topCommandRowNonEditing()
                    }

                    // === ナビ中：右側の縦ボタン（ルート俯瞰 / ミュート） ============
                    if nav.isNavigating {
                        VStack {
                            Spacer()
                            VStack(spacing: 10) {
                                Button {
                                    zoomToFitCurrentRoute()
                                } label: {
                                    Image(systemName: "point.topleft.down.curvedto.point.filled.bottomright.up")
                                        .font(.title3)
                                        .padding(10)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                Button {
                                    nav.isMuted.toggle()
                                } label: {
                                    Image(systemName: nav.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .font(.title3)
                                        .padding(10)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                            }
                            .padding(.trailing, 10)
                            .padding(.bottom, 120)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    // === 左側：ナビ中クイックPOI（必要なら残す） ===================
                    if nav.isNavigating {
                        VStack {
                            Spacer()
                            VStack(spacing: 10) {
                                ForEach([QuickPOIKind.gas, .ev, .toilet, .conv]) { k in
                                    Button {
                                        poi.run(k, around: searchRegion.center, span: searchRegion.span)
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

                    // === POIリスト（下部） ========================================
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

                    // === 検索ボタン（非編集時のみ） ================================
                    if editMode == .none && !nav.isNavigating {
                        VStack {
                            Spacer()
                            HStack { Spacer()
                                Button {
                                    showSearchSheet = true
                                } label: {
                                    Label("検索", systemImage: "magnifyingglass")
                                        .font(.headline)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                                .padding(.trailing, 12).padding(.bottom, 12)
                            }
                        }
                    }
                }
            }
            // === ナビ時の上部インセット（大案内バナー） / 編集時の操作列 ============
            .safeAreaInset(edge: .top) {
                if nav.isNavigating {
                    NavInstructionBanner(icon: nav.nextSymbol, instruction: currentInstruction)
                } else if editMode != .none {
                    EditorActionBar(
                        onConfirm: { zoomToFitCurrentRoute() },
                        onSave: { showingSave = true },
                        onStart: { Task { await startNavigationForEditorRoute() } }
                    )
                }
            }
            // === ナビ時の下部メトリクスカード ===================================
            .safeAreaInset(edge: .bottom) {
                if nav.isNavigating {
                    NavMetricsBar(
                        eta: nav.eta,
                        remainTimeSec: nav.remainingTimeSec,
                        remainDistanceM: nav.remainingDistanceM,
                        onShowSteps: { showStepList = true },
                        onShowOptions: { showNavOptions = true }
                    )
                }
            }
            // === ナビゲーションバー（編集中は黒＋キャンセル） ======================
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
        // === 位置権限＆追従・HUD更新 =============================================
        .onAppear { location.start() }
        .onReceive(location.$lastCoordinate) { coord in
            guard let c = coord else { return }
            if followUser {
                camera = .camera(MapCamera(centerCoordinate: c, distance: 1200, heading: 0, pitch: 0))
            }
            if nav.isNavigating {
                if let r = activeNavRoute {
                    updateHUD(appleRoute: r, user: c)     // ← currentInstruction も更新
                } else if let pls = activeCustomNav {
                    updateHUD(custom: pls, user: c)
                }
            }
        }
        // === 保存（保存後はトップに戻る） ========================================
        .sheet(isPresented: $showingSave) {
            SaveSheet(title: "ルートを保存", name: $saveName) {
                store.save(name: saveName.isEmpty ? "未命名ルート" : saveName, points: editor.points)
                saveName = ""
                cancelEditing()
            }
        }
        // === ロード ==============================================================
        .sheet(isPresented: $showLoadListSheet) {
            LoadListSheet(routes: store.routes,
                          onLoad: { r in store.selected = r; nav.isNavigating = false },
                          onShare: { _ in })
        }
        // === ルートオプション ====================================================
        .sheet(isPresented: $showingRouteOption) { RouteOptionSheet(useHighway: $nav.useHighway) }
        // === 検索（純正風ボトム） ===============================================
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
        // === ナビ：ステップ一覧 ==================================================
        .sheet(isPresented: $showStepList) {
            StepListSheet(
                title: currentInstruction,
                steps: activeNavRoute?.steps ?? [],
                onClose: { showStepList = false }
            )
            .presentationDetents([.medium, .large])
        }
        // === ナビ：オプション（経由地・終了など） ================================
        .sheet(isPresented: $showNavOptions) {
            NavOptionSheet(
                destinationTitle: activeNavRoute?.name ?? "目的地",
                eta: nav.eta,
                onAddStop: { /* TODO: 経由地 */ },
                onShareETA: { /* TODO: 共有 */ },
                onReportTraffic: { /* TODO */ },
                onVolume: { /* TODO */ },
                onEndRoute: {
                    // 経路を終了 → ルート表示画面に戻る
                    nav.isNavigating = false
                    activeNavRoute = nil
                    activeCustomNav = nil
                    showNavOptions = false
                }
            )
        }
    }

    // MARK: - 上部コマンド（非編集時）
    @ViewBuilder
    private func topCommandRowNonEditing() -> some View {
        VStack {
            HStack(spacing: 10) {
                Button("ルート新規作成") {
                    editMode = .createNew
                    followUser = false
                    editor.reset()
                    activeCustomNav = nil
                    activeNavRoute = nil
                    nav.isNavigating = false
                    store.selected = nil
                }
                .buttonStyle(PillButtonStyle(kind: .filled, tint: .accentColor))

                if activeNavRoute != nil {
                    Button("編集") {
                        guard let r = activeNavRoute else { return }
                        editMode = .editExisting
                        followUser = false
                        editor.reset()
                        let end = coords(from: r.polyline).last ?? searchRegion.center
                        if let cur = location.lastCoordinate {
                            editor.points = [cur, end]
                        } else {
                            editor.points = [searchRegion.center, end]
                        }
                        editor.segments = [r.polyline]
                    }
                    .buttonStyle(PillButtonStyle(kind: .tinted, tint: .accentColor))
                }

                Spacer()

                if activeNavRoute != nil && !nav.isNavigating {
                    Button("開始") {
                        nav.isNavigating = true
                        followUser = true
                        if let r = activeNavRoute {
                            nav.remainingDistanceM = r.distance
                            nav.remainingTimeSec = r.expectedTravelTime
                            nav.nextDistanceM = r.steps.first?.distance ?? r.distance
                            nav.progress = 0
                            currentInstruction = r.steps.first?.instructions.isEmpty == false
                                ? r.steps.first!.instructions : "出発"
                            nav.nextSymbol = pickSymbol(from: currentInstruction)
                        }
                        activeCustomNav = nil
                    }
                    .buttonStyle(PillButtonStyle(kind: .filled, tint: .accentColor))
                }

                Button("ロード") { showLoadList() }
                    .buttonStyle(PillButtonStyle(kind: .tinted, tint: .accentColor))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Map Layers
    @MapContentBuilder
    private func mapLayers(proxy: MapProxy) -> some MapContent {
        UserAnnotation()

        // 編集線（青）
        ForEach(editor.segments.indices, id: \.self) { i in
            MapPolyline(coordinates: coords(from: editor.segments[i]))
                .stroke(.blue, lineWidth: 5)
        }

        // Apple検索ルート（緑）— 編集/ナビ以外で表示
        if editMode == .none, !nav.isNavigating, let navRoute = activeNavRoute {
            MapPolyline(coordinates: coords(from: navRoute.polyline))
                .stroke(.green, lineWidth: 10)
        }

        // カスタムナビ（緑）— 編集/ナビ以外で表示（必要なら）
        if editMode == .none, !nav.isNavigating, let custom = activeCustomNav {
            ForEach(Array(custom.enumerated()), id: \.offset) { _, pl in
                MapPolyline(coordinates: coords(from: pl))
                    .stroke(.green, lineWidth: 10)
            }
        }

        // 検索ピン / POI
        ForEach(place.results) { item in Marker(item.name, coordinate: item.coordinate) }
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

    // MARK: - 検索→ルート表示
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

    // MARK: - 編集：点追加/再計算/線上挿入
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
        if index - 1 >= 0 {
            let a = editor.points[index - 1]
            if let r = try? await engine.route(from: a, to: newCoord, allowHighways: nav.useHighway),
               index - 1 < editor.segments.count {
                editor.segments[index - 1] = r.polyline
            }
        }
        if index + 1 < editor.points.count {
            let b = editor.points[index + 1]
            if let r = try? await engine.route(from: newCoord, to: b, allowHighways: nav.useHighway) {
                if index < editor.segments.count { editor.segments[index] = r.polyline }
                else { editor.segments.append(r.polyline) }
            }
        }
    }

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
        if i - 1 >= 0 && i < editor.points.count {
            let a = editor.points[i - 1], b = editor.points[i]
            if let r = try? await engine.route(from: a, to: b, allowHighways: nav.useHighway) {
                if i - 1 < editor.segments.count { editor.segments[i - 1] = r.polyline }
                else { editor.segments.append(r.polyline) }
            }
        }
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

        if let cur = location.lastCoordinate, let first = editor.points.first {
            if let r0 = try? await engine.route(from: cur, to: first, allowHighways: nav.useHighway) {
                polylines.append(r0.polyline)
            }
        }
        if editor.segments.count >= max(0, editor.points.count - 1) {
            polylines.append(contentsOf: editor.segments)
        } else {
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

        let total = polylines.reduce(0) { $0 + polylineLength($1) }
        nav.remainingDistanceM = total
        nav.remainingTimeSec = total / 12.5
        nav.nextDistanceM = total
        nav.progress = 0
        currentInstruction = "出発"
        nav.nextSymbol = "arrow.up"
        zoomToFitCurrentRoute()
    }

    // MARK: - HUD更新（Appleルート / カスタム）
    private func updateHUD(appleRoute route: MKRoute, user: CLLocationCoordinate2D) {
        var nearestStepIndex = 0
        var nearestDistance = CLLocationDistance.greatestFiniteMagnitude
        for (i, step) in route.steps.enumerated() {
            let d = distanceToPolyline(from: user, polyline: step.polyline)
            if d < nearestDistance { nearestDistance = d; nearestStepIndex = i }
        }
        let remainInStep = remainingDistanceOnPolyline(from: user, polyline: route.steps[nearestStepIndex].polyline)
        currentInstruction = route.steps[nearestStepIndex].instructions.isEmpty ? "直進" : route.steps[nearestStepIndex].instructions
        nav.nextSymbol = pickSymbol(from: currentInstruction)
        nav.nextDistanceM = max(0, remainInStep)

        let passed = routeDistanceUptoStep(route, index: nearestStepIndex)
                 + (route.steps[nearestStepIndex].distance - remainInStep)
        nav.remainingDistanceM = max(0, route.distance - passed)
        nav.progress = max(0, min(1, passed / max(route.distance, 1)))
        nav.remainingTimeSec = max(0, route.expectedTravelTime * (nav.remainingDistanceM / max(route.distance, 1)))
    }

    private func updateHUD(custom polylines: [MKPolyline], user: CLLocationCoordinate2D) {
        guard !polylines.isEmpty else { return }
        var nearestIndex = 0
        var nearest = CLLocationDistance.greatestFiniteMagnitude
        for (i, pl) in polylines.enumerated() {
            let d = distanceToPolyline(from: user, polyline: pl)
            if d < nearest { nearest = d; nearestIndex = i }
        }
        let remainInThis = remainingDistanceOnPolyline(from: user, polyline: polylines[nearestIndex])
        nav.nextDistanceM = max(0, remainInThis)
        currentInstruction = "直進"
        nav.nextSymbol = "arrow.up"

        let passedBefore = polylines.prefix(nearestIndex).reduce(0) { $0 + polylineLength($1) }
        let thisTotal = polylineLength(polylines[nearestIndex])
        let passed = passedBefore + (thisTotal - remainInThis)
        let total = polylines.reduce(0) { $0 + polylineLength($1) }

        nav.remainingDistanceM = max(0, total - passed)
        nav.progress = max(0, min(1, passed / max(total, 1)))
        nav.remainingTimeSec = nav.remainingDistanceM / 12.5
    }

    // MARK: - 共通ユーティリティ
    private func coords(from pl: MKPolyline) -> [CLLocationCoordinate2D] {
        var arr = Array(repeating: kCLLocationCoordinate2DInvalid, count: pl.pointCount)
        pl.getCoordinates(&arr, range: NSRange(location: 0, length: pl.pointCount))
        return arr
    }
    private func polylineLength(_ pl: MKPolyline) -> CLLocationDistance {
        let cs = coords(from: pl); guard cs.count >= 2 else { return 0 }
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
        let cs = coords(from: polyline); guard cs.count >= 2 else { return 0 }
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

    private func pickSymbol(from text: String) -> String {
        if text.contains("左") { return "arrow.turn.left" }
        if text.contains("右") { return "arrow.turn.right" }
        return "arrow.up"
    }

    private func cancelEditing() {
        editor.reset()
        editMode = .none
        followUser = true
    }
    private func showLoadList() { showLoadListSheet = true }
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
        } else { return }

        let pad = 1.15
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat)/2,
                                            longitude: (minLon + maxLon)/2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * pad, 0.005),
                                    longitudeDelta: max((maxLon - minLon) * pad, 0.005))
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - 上部案内バナー（ナビ用）
private struct NavInstructionBanner: View {
    let icon: String
    let instruction: String
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                Text(instruction)
                    .font(.title.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            Capsule().fill(Color.secondary.opacity(0.35))
                .frame(width: 44, height: 5)
                .padding(.bottom, 4)
        }
        .background(.thinMaterial)
    }
}

// MARK: - 下部メトリクスカード（到着・時間・距離）
private struct NavMetricsBar: View {
    let eta: Date
    let remainTimeSec: TimeInterval
    let remainDistanceM: CLLocationDistance
    let onShowSteps: () -> Void
    let onShowOptions: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                MetricCell(title: "到着", value: Text(eta, style: .time))
                MetricCell(title: "時間", value: Text(fmtDuration(remainTimeSec)))
                MetricCell(title: "km", value: Text(String(format: "%.0f", remainDistanceM / 1000)))
                Spacer()
                Button(action: onShowOptions) {
                    Image(systemName: "chevron.up.circle.fill").font(.title2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 8)

            Button(action: onShowSteps) {
                Text("到着予定を共有").font(.callout)
            }
            .padding(.bottom, 4)
        }
    }
    private struct MetricCell<Content: View>: View {
        let title: String
        let value: Content
        init(title: String, value: Content) { self.title = title; self.value = value }
        var body: some View {
            VStack(alignment: .leading) {
                value.font(.title2).bold().monospacedDigit()
                Text(title).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 編集時の上部操作列
private struct EditorActionBar: View {
    let onConfirm: () -> Void
    let onSave: () -> Void
    let onStart: () -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button("確定", action: onConfirm)
                    .buttonStyle(PillButtonStyle(kind: .filled, tint: .accentColor))
                Button("保存", action: onSave)
                    .buttonStyle(PillButtonStyle(kind: .tinted, tint: .accentColor))
                Button("ルート案内開始", action: onStart)
                    .buttonStyle(PillButtonStyle(kind: .filled, tint: .green))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.thinMaterial)
    }
}

// MARK: - ナビオプションシート
private struct NavOptionSheet: View {
    let destinationTitle: String
    let eta: Date
    let onAddStop: () -> Void
    let onShareETA: () -> Void
    let onReportTraffic: () -> Void
    let onVolume: () -> Void
    let onEndRoute: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill").font(.title2)
                            .foregroundStyle(.red)
                        VStack(alignment: .leading) {
                            Text(destinationTitle).bold()
                            Text("到着時刻: \(eta.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("経路オプション")
                }

                Button(action: onAddStop) {
                    Label("経由地を追加", systemImage: "plus.circle.fill")
                }
                Button(action: onShareETA) {
                    Label("到着予定を共有", systemImage: "person.2.circle.fill")
                }
                Button(action: onReportTraffic) {
                    Label("交通情報を報告", systemImage: "exclamationmark.bubble.fill")
                }
                Button(action: onVolume) {
                    Label("声の音量", systemImage: "speaker.wave.2.fill")
                }

                Section {
                    Button(role: .destructive, action: onEndRoute) {
                        Text("経路を終了").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("オプション")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - ステップ一覧シート
private struct StepListSheet: View {
    let title: String
    let steps: [MKRoute.Step]
    let onClose: () -> Void
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: s.instructions))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(distance(s.distance)).bold()
                            Text(s.instructions.isEmpty ? "直進" : s.instructions)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("閉じる", action: onClose)
                }
            }
        }
    }
    private func icon(for text: String) -> String {
        if text.contains("左") { return "arrow.turn.left" }
        if text.contains("右") { return "arrow.turn.right" }
        return "arrow.up"
    }
    private func distance(_ m: CLLocationDistance) -> String {
        m < 1000 ? String(format: "%.0f m", m) : String(format: "%.1f km", m/1000)
    }
}

// MARK: - ピルボタン
private struct PillButtonStyle: ButtonStyle {
    enum Kind { case filled, tinted, outline }
    var kind: Kind = .filled
    var tint: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(background(configuration))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
    @ViewBuilder private func background(_ configuration: Configuration) -> some View {
        switch kind {
        case .filled:
            Capsule()
                .fill(tint.opacity(configuration.isPressed ? 0.85 : 1))
                .overlay(Capsule().stroke(.clear, lineWidth: 0))
                .foregroundStyle(.white)
        case .tinted:
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(tint, lineWidth: 1.2))
        case .outline:
            Capsule().stroke(tint, lineWidth: 1.4)
        }
    }
}

// MARK: - 検索ボトム
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

// MARK: - ドラッグ編集点（番号付）
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

// MARK: - 共通フォーマッタ（Shared_Formatters を使用）
//
// この画面ファイル内では fmtDuration / fmtDistance を定義しません。
// プロジェクト共通の Shared_Formatters.swift にある実装を利用します。
