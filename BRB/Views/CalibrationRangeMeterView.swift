//
//  CalibrationRangeMeterView.swift
//  BRB
//
//  Shared visual dual-threshold range meter mapping signal strength to position.
//  - Left: -95 dBm (Far away / screen covered)
//  - Right: -40 dBm (Near Mac / desk area)
//  Visualizes Away Zone, Hysteresis Buffer Zone, and Desk Zone with interactive
//  boundary ticks and an animated live signal needle showing real-time location.
//

import SwiftUI

func estimatedDistanceString(for rssi: Double) -> String {
    if rssi >= -55 {
        return "< 0.5m (Immediate desk)"
    } else if rssi >= -65 {
        return "~0.5 – 1.5m (At desk)"
    } else if rssi >= -75 {
        return "~1.5 – 2.5m (Desk boundary)"
    } else if rssi >= -85 {
        return "~2.5 – 4.0m (Stepping away)"
    } else {
        return "> 4.0m (Far away)"
    }
}

/// Visual dual-threshold range meter mapping signal strength to position.
/// - Left: -95 dBm (Far away / screen covered)
/// - Right: -40 dBm (Near Mac / desk area)
/// Visualizes the Away Zone, Hysteresis Buffer Zone, and Desk Zone with interactive threshold tick marks
/// and an animated live signal needle showing where the user's earbuds are in real time.
struct CalibrationRangeMeterView: View {
    var reading: Double?
    var isStale: Bool
    var veilOn: Double
    var veilOff: Double

    private let minV: Double = -95.0
    private let maxV: Double = -40.0

    private func fraction(_ v: Double) -> CGFloat {
        CGFloat(min(1.0, max(0.0, (v - minV) / (maxV - minV))))
    }

    var body: some View {
        VStack(spacing: DS.spacingXS) {
            GeometryReader { geo in
                let w = geo.size.width
                let onX = fraction(veilOn) * w
                let offX = max(onX, fraction(veilOff) * w)

                ZStack(alignment: .topLeading) {
                    // Track Bar with 3 zones
                    ZStack(alignment: .leading) {
                        // Base / Away Zone (orange)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(0.85))
                            .frame(height: 12)

                        // Hysteresis Buffer Zone (blue)
                        Rectangle()
                            .fill(Color.blue.opacity(0.85))
                            .frame(width: max(0, offX - onX), height: 12)
                            .offset(x: onX)

                        // Near / Desk Zone (green)
                        Rectangle()
                            .fill(Color.green.opacity(0.85))
                            .frame(width: max(0, w - offX), height: 12)
                            .offset(x: offX)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .offset(y: 28)

                    // Veil-On Tick
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 18)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                        .offset(x: onX - 1, y: 25)

                    // Veil-Off Tick
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 18)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                        .offset(x: offX - 1, y: 25)

                    // Live Signal Needle
                    if let reading {
                        let rx = fraction(reading) * w
                        let clampedX = min(max(38, rx), max(38, w - 38))
                        let zoneColor: Color = {
                            if reading <= veilOn { return .orange }
                            if reading >= veilOff { return .green }
                            return .blue
                        }()

                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 11, weight: .bold))
                                Text("\(Int(round(reading))) dBm")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isStale ? Color.secondary.opacity(0.18) : zoneColor.opacity(0.18))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isStale ? Color.secondary : zoneColor, lineWidth: 1.5)
                            )
                            .foregroundColor(isStale ? .secondary : zoneColor)

                            Image(systemName: "triangle.fill")
                                .font(.system(size: 7))
                                .foregroundColor(isStale ? .secondary : zoneColor)
                                .rotationEffect(.degrees(180))
                                .offset(y: -1)
                        }
                        .position(x: clampedX, y: 13)
                        .animation(.easeInOut(duration: 0.35), value: reading)
                        .animation(.easeInOut(duration: 0.2), value: isStale)
                    }
                }
            }
            .frame(height: 48)

            // Range Scale Labels
            HStack {
                Text("Far (>3m / -95 dBm)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("~2m Boundary")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Near (<1m / -40 dBm)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
