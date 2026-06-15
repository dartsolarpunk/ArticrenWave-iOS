// SharedComponents.swift — Shared UI components used across multiple views
// Articren Wave · © 2026 DART Meadow LLC & Radical Deepscale LLC
import SwiftUI

// MARK: - Articren Wave logo mark (vector, used in menu + splash)
struct ArticrenWaveLogoMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width

            // Magenta/pink vertical lightning bolt
            let bolt = Path { p in
                p.move(to:    CGPoint(x: s*0.22, y: s*0.05))
                p.addLine(to: CGPoint(x: s*0.12, y: s*0.50))
                p.addLine(to: CGPoint(x: s*0.20, y: s*0.50))
                p.addLine(to: CGPoint(x: s*0.08, y: s*0.95))
                p.addLine(to: CGPoint(x: s*0.35, y: s*0.45))
                p.addLine(to: CGPoint(x: s*0.24, y: s*0.45))
                p.close()
            }
            ctx.fill(bolt, with: .linearGradient(
                Gradient(colors: [Color(hex: "#FF00A0"), Color(hex: "#8B00FF")]),
                startPoint: CGPoint(x: s*0.1, y: 0), endPoint: CGPoint(x: s*0.1, y: s)
            ))

            // Purple diagonal slash
            let slash = Path { p in
                p.move(to:    CGPoint(x: s*0.30, y: s*0.08))
                p.addLine(to: CGPoint(x: s*0.90, y: s*0.10))
                p.addLine(to: CGPoint(x: s*0.85, y: s*0.20))
                p.addLine(to: CGPoint(x: s*0.25, y: s*0.18))
                p.close()
            }
            ctx.fill(slash, with: .linearGradient(
                Gradient(colors: [Color(hex: "#8B00FF"), Color(hex: "#C040FB")]),
                startPoint: CGPoint(x: s*0.3, y: s*0.1), endPoint: CGPoint(x: s*0.9, y: s*0.1)
            ))

            // Cyan arc
            var wave = Path()
            wave.move(to: CGPoint(x: s*0.18, y: s*0.45))
            wave.addCurve(
                to: CGPoint(x: s*0.45, y: s*0.30),
                control1: CGPoint(x: s*0.28, y: s*0.55),
                control2: CGPoint(x: s*0.38, y: s*0.22)
            )
            ctx.stroke(wave, with: .linearGradient(
                Gradient(colors: [Color(hex: "#00BFFF"), Color(hex: "#7B00FF")]),
                startPoint: CGPoint(x: s*0.18, y: s*0.45),
                endPoint:   CGPoint(x: s*0.45, y: s*0.3)
            ), style: StrokeStyle(lineWidth: s*0.05, lineCap: .round))
        }
    }
}
