//
//  Features_Navigation_DriveHUD.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/07.
//

import SwiftUI
import MapKit

@MainActor
struct DriveHUD: View {
    @EnvironmentObject var nav: NavigationState

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: min(max(nav.progress, 0), 1))
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal, 12)

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: nav.nextSymbol)
                        .font(.system(size: 22, weight: .semibold))
                    Text(fmtDistance(nav.nextDistanceM))
                        .font(.title3).bold().monospacedDigit()
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(nav.eta, style: .time)
                        .font(.subheadline).monospacedDigit()
                    Text("\(fmtDuration(nav.remainingTimeSec))・\(fmtDistance(nav.remainingDistanceM))")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Button { nav.isMuted.toggle() } label: {
                    Image(systemName: nav.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)

                if nav.isOffRoute {
                    Button { /* TODO: ルート復帰 */ } label: {
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
