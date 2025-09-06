//
//  ContentView.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/04.
//

import SwiftUI
import MapKit

// =======================================================
// ContentView（ここから起動）
// =======================================================
struct ContentView: View {
    var body: some View {
        DriveMapScreen()
    }
}

// =======================================================
// ナビ表示用の状態（ダミー値入り）
// =======================================================
final class NavigationState: ObservableObject {
    // 次の案内
    @Published var nextSymbol: String = "arrow.turn.up.right"
    @Published var nextDistanceM: CLLocationDistance = 350

    // 残り情報
    @Published var eta: Date = Date().addingTimeInterval(42 * 60)
    @Published var remainingTimeSec: TimeInterval = 42 * 60
    @Published var remainingDistanceM: CLLocationDistance = 12_800
    @Published var progress: Double = 0.35

    // フラグ
    @Published var isMuted: Bool = false
    @Published var isOffRoute: Bool = false

    // 車線減少（表示時のみセット）
    @Published var laneDropMessage: String? = "800 m先で 3 → 2 車線"
}

// =======================================================
// クイックPOI（モック）
// =======================================================
enum QuickPOI: String, CaseIterable, Identifiable {
    case toilet = "トイレ"
    case gas    = "ガソリン"
    case conv   = "コンビニ"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .toilet: return "figure.wave"     // 出ない環境なら person.fill 等に変更
        case .gas:    return "fuelpump.fill"
        case .conv:   return "bag.fill"
        }
    }

    var query: String {
        switch self {
        case .toilet: return "トイレ"
        case .gas:    return "ガソリンスタンド"
        case .conv:   return "コンビニ"
        }
    }
}

struct SimplePOI: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let kind: QuickPOI

    init(name: String, coordinate: CLLocationCoordinate2D, kind: QuickPOI) {
        self.id = UUID()
        self.name = name
        self.coordinate = coordinate
        self.kind = kind
    }

    static func == (lhs: SimplePOI, rhs: SimplePOI) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

final class QuickPOISearch: ObservableObject {
    @Published var active: QuickPOI? = nil
    @Published var results: [SimplePOI] = []

    // ダミー：中心の周囲にPOIを生成
    func run(_ kind: QuickPOI, around center: CLLocationCoordinate2D) {
        active = kind
        results = (0..<6).map { i in
            let dx = Double.random(in: -0.004...0.004)
            let dy = Double.random(in: -0.004...0.004)
            let c = CLLocationCoordinate2D(latitude: center.latitude + dy,
                                           longitude: center.longitude + dx)
            return SimplePOI(name: "\(kind.rawValue) \(i + 1)", coordinate: c, kind: kind)
        }
    }

    func clear() {
        active = nil
        results = []
    }
}

// =======================================================
// 共通フォーマッタ
// =======================================================
private func fmtDistance(_ m: CLLocationDistance) -> String {
    if m < 1000 { return String(format: "%.0f m", m) }
    return String(format: "%.1f km", m / 1000.0)
}
private func fmtDuration(_ s: TimeInterval) -> String {
    let h = Int(s) / 3600
    let m = (Int(s) % 3600) / 60
    return h > 0 ? "\(h)時間\(m)分" : "\(m)分"
}

// =======================================================
// 画面本体
// =======================================================
struct DriveMapScreen: View {
    @StateObject private var nav = NavigationState()
    @StateObject private var poi = QuickPOISearch()

    // 初期リージョン
    private let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.0116, longitude: 135.7681),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    // iOS17+ SwiftUI Mapカメラ
    @State private var camera: MapCameraPosition
    // 検索/距離計算用の現在表示リージョン
    @State private var searchRegion: MKCoordinateRegion

    init() {
        _camera = State(initialValue: .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.0116, longitude: 135.7681),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        ))
        _searchRegion = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.0116, longitude: 135.7681),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }

    var body: some View {
        ZStack {
            // --- 地図
            Map(position: $camera) {
                ForEach(poi.results) { item in
                    Marker(item.name, coordinate: item.coordinate)
                }
            }
            .onMapCameraChange(frequency: .continuous) { ctx in
                searchRegion = ctx.region
            }

            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .ignoresSafeArea()

            // --- 上部：車線減少バナー
            VStack(spacing: 0) {
                if let msg = nav.laneDropMessage {
                    LaneDropBanner(message: msg)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
                Spacer()
            }
            .animation(.easeInOut, value: nav.laneDropMessage)

            // --- 右下：クイックPOI 3ボタン
            VStack { Spacer()
                HStack {
                    Spacer()
                    QuickPOIButtons(
                        active: poi.active,
                        onTap: { kind in
                            if poi.active == kind { poi.clear() }
                            else { poi.run(kind, around: searchRegion.center) }
                        }
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
            }
            .ignoresSafeArea()

            // --- 下部：DriveHUD
            VStack { Spacer()
                DriveHUD()
                    .environmentObject(nav)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .ignoresSafeArea(edges: .bottom)

            // --- 下部：POIボトムシート（アクティブ時のみ）
            if let active = poi.active, !poi.results.isEmpty {
                BottomPOIList(
                    kind: active,
                    items: poi.results,
                    distanceFrom: searchRegion.center,
                    onSelect: { _ in /* TODO: 寄り道/目的地設定 */ },
                    onClose: { poi.clear() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        // デモ：3秒後に「ルート復帰」、6秒後に解除
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { nav.isOffRoute = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { nav.isOffRoute = false }
        }
    }
}

// =======================================================
// 上部バナー
// =======================================================
struct LaneDropBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "triangle.fill").foregroundStyle(.yellow)
            Text(message).font(.subheadline).bold()
            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: Capsule())
        .padding(.horizontal, 12)
    }
}

// =======================================================
// 下部HUD
// =======================================================
struct DriveHUD: View {
    @EnvironmentObject var nav: NavigationState

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: min(max(nav.progress, 0), 1))
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal, 12)

            HStack(spacing: 12) {
                // 次の案内
                HStack(spacing: 8) {
                    Image(systemName: nav.nextSymbol)
                        .font(.system(size: 22, weight: .semibold))
                    Text(fmtDistance(nav.nextDistanceM))
                        .font(.title3).bold().monospacedDigit()
                }

                Spacer(minLength: 8)

                // 残り情報
                VStack(alignment: .trailing, spacing: 2) {
                    Text(nav.eta, style: .time)
                        .font(.subheadline).monospacedDigit()
                    Text("\(fmtDuration(nav.remainingTimeSec))・\(fmtDistance(nav.remainingDistanceM))")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                // ミュート
                Button { nav.isMuted.toggle() } label: {
                    Image(systemName: nav.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)

                // 逸脱時のみ
                if nav.isOffRoute {
                    Button {
                        // TODO: 「ルート復帰」を呼ぶ
                    } label: {
                        Label("ルート復帰", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// =======================================================
// 右下：クイックPOI 3ボタン
// =======================================================
struct QuickPOIButtons: View {
    let active: QuickPOI?
    let onTap: (QuickPOI) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(QuickPOI.allCases) { kind in
                Button { onTap(kind) } label: {
                    Image(systemName: kind.icon)
                        .font(.title3)
                        .padding(12)
                        .background(
                            Circle().fill(.ultraThinMaterial)
                                .overlay(
                                    Circle().stroke(active == kind ? Color.accentColor : .clear, lineWidth: 2)
                                )
                        )
                }
                .accessibilityLabel(kind.rawValue)
            }
        }
    }
}

// =======================================================
// 下部：POIボトムリスト（モック）
// =======================================================
struct BottomPOIList: View {
    let kind: QuickPOI
    let items: [SimplePOI]
    let distanceFrom: CLLocationCoordinate2D
    let onSelect: (SimplePOI) -> Void
    let onClose: () -> Void

    private func distance(_ c: CLLocationCoordinate2D) -> CLLocationDistance {
        let a = MKMapPoint(c)
        let b = MKMapPoint(distanceFrom)
        return a.distance(to: b) // iOS17+ のインスタンスメソッド
    }

    var body: some View {
        VStack(spacing: 0) {
            // グリッパー
            Capsule().fill(Color.secondary.opacity(0.4))
                .frame(width: 44, height: 5)
                .padding(.top, 8)

            HStack {
                Label(kind.rawValue, systemImage: kind.icon)
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.headline)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            List(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.body)
                    Text(fmtDistance(distance(item.coordinate)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect(item) }
            }
            .listStyle(.plain)
            .frame(maxHeight: 280)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .shadow(radius: 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityAddTraits(.isModal)
    }
}
