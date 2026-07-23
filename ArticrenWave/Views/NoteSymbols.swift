// NoteSymbols.swift — Professional vector music notation symbols
// Hand-crafted SwiftUI Canvas paths for all note/rest types
import SwiftUI

// MARK: - Note Head Shape
struct NoteHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        // Slightly tilted oval — standard engraving style
        p.addEllipse(in: CGRect(x: cx - w*0.48, y: cy - h*0.38, width: w*0.96, height: h*0.76))
        return p
    }
}

// MARK: - Whole Note (open oval, no stem)
struct WholeNoteSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            let cx = sz.width/2, cy = sz.height/2
            let rx = sz.width*0.42, ry = sz.height*0.28
            // Outer oval
            var outer = Path()
            outer.addEllipse(in: CGRect(x: cx-rx, y: cy-ry, width: rx*2, height: ry*2))
            ctx.stroke(outer, with: .color(color), lineWidth: sz.width*0.1)
            // Inner cutout (white hole to give hollow look)
            var inner = Path()
            inner.addEllipse(in: CGRect(x: cx-rx*0.4, y: cy-ry*0.5, width: rx*0.8, height: ry))
            ctx.fill(inner, with: .color(color))
        }
        .frame(width: size, height: size * 0.6)
    }
}

// MARK: - Half Note (open oval + stem)
struct HalfNoteSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            let cx = sz.width*0.35
            let headY = sz.height*0.72
            let rx = sz.width*0.32, ry = sz.height*0.18
            // Open head
            var head = Path()
            head.addEllipse(in: CGRect(x: cx-rx, y: headY-ry, width: rx*2, height: ry*2))
            ctx.stroke(head, with: .color(color), lineWidth: sz.width*0.09)
            // Stem up
            var stem = Path()
            stem.move(to: CGPoint(x: cx+rx-sz.width*0.04, y: headY))
            stem.addLine(to: CGPoint(x: cx+rx-sz.width*0.04, y: sz.height*0.08))
            ctx.stroke(stem, with: .color(color), lineWidth: sz.width*0.07)
        }
        .frame(width: size, height: size * 1.5)
    }
}

// MARK: - Quarter Note (filled oval + stem)
struct QuarterNoteSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            let cx = sz.width*0.35
            let headY = sz.height*0.76
            let rx = sz.width*0.32, ry = sz.height*0.17
            // Filled head
            var head = Path()
            head.addEllipse(in: CGRect(x: cx-rx, y: headY-ry, width: rx*2, height: ry*2))
            // Rotate slightly
            ctx.fill(head, with: .color(color))
            // Stem
            var stem = Path()
            stem.move(to: CGPoint(x: cx+rx-sz.width*0.04, y: headY-ry*0.3))
            stem.addLine(to: CGPoint(x: cx+rx-sz.width*0.04, y: sz.height*0.06))
            ctx.stroke(stem, with: .color(color), lineWidth: sz.width*0.08)
        }
        .frame(width: size, height: size * 1.5)
    }
}

// MARK: - Eighth Note (filled + stem + flag)
struct EighthNoteSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            let cx = sz.width*0.32
            let headY = sz.height*0.78
            let rx = sz.width*0.30, ry = sz.height*0.16
            // Head
            var head = Path()
            head.addEllipse(in: CGRect(x: cx-rx, y: headY-ry, width: rx*2, height: ry*2))
            ctx.fill(head, with: .color(color))
            // Stem
            let stemX = cx+rx-sz.width*0.04
            var stem = Path()
            stem.move(to: CGPoint(x: stemX, y: headY-ry*0.3))
            stem.addLine(to: CGPoint(x: stemX, y: sz.height*0.06))
            ctx.stroke(stem, with: .color(color), lineWidth: sz.width*0.08)
            // Flag (single curve)
            var flag = Path()
            flag.move(to: CGPoint(x: stemX, y: sz.height*0.06))
            flag.addCurve(
                to: CGPoint(x: stemX + sz.width*0.40, y: sz.height*0.30),
                control1: CGPoint(x: stemX + sz.width*0.35, y: sz.height*0.08),
                control2: CGPoint(x: stemX + sz.width*0.42, y: sz.height*0.20)
            )
            ctx.stroke(flag, with: .color(color), lineWidth: sz.width*0.08)
        }
        .frame(width: size, height: size * 1.6)
    }
}

// MARK: - Sixteenth Note (filled + stem + 2 flags)
struct SixteenthNoteSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            let cx = sz.width*0.30
            let headY = sz.height*0.80
            let rx = sz.width*0.28, ry = sz.height*0.15
            var head = Path()
            head.addEllipse(in: CGRect(x: cx-rx, y: headY-ry, width: rx*2, height: ry*2))
            ctx.fill(head, with: .color(color))
            let stemX = cx+rx-sz.width*0.04
            var stem = Path()
            stem.move(to: CGPoint(x: stemX, y: headY-ry*0.3))
            stem.addLine(to: CGPoint(x: stemX, y: sz.height*0.04))
            ctx.stroke(stem, with: .color(color), lineWidth: sz.width*0.08)
            // Two flags
            for i in 0..<2 {
                var flag = Path()
                let startY = sz.height*(0.04 + Double(i)*0.15)
                flag.move(to: CGPoint(x: stemX, y: startY))
                flag.addCurve(
                    to: CGPoint(x: stemX + sz.width*0.38, y: startY + sz.height*0.20),
                    control1: CGPoint(x: stemX + sz.width*0.32, y: startY + sz.height*0.04),
                    control2: CGPoint(x: stemX + sz.width*0.40, y: startY + sz.height*0.12)
                )
                ctx.stroke(flag, with: .color(color), lineWidth: sz.width*0.07)
            }
        }
        .frame(width: size, height: size * 1.7)
    }
}

// MARK: - Rest Symbols
struct WholeRestSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            // Whole rest = filled rectangle hanging from line
            var rect = Path()
            rect.addRect(CGRect(x: sz.width*0.15, y: sz.height*0.35, width: sz.width*0.70, height: sz.height*0.28))
            ctx.fill(rect, with: .color(color))
        }
        .frame(width: size, height: size * 0.7)
    }
}

struct HalfRestSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            // Half rest = filled rectangle sitting on line
            var rect = Path()
            rect.addRect(CGRect(x: sz.width*0.15, y: sz.height*0.38, width: sz.width*0.70, height: sz.height*0.28))
            ctx.fill(rect, with: .color(color))
            // Bottom line
            var line = Path()
            line.move(to: CGPoint(x: sz.width*0.10, y: sz.height*0.68))
            line.addLine(to: CGPoint(x: sz.width*0.90, y: sz.height*0.68))
            ctx.stroke(line, with: .color(color), lineWidth: sz.width*0.07)
        }
        .frame(width: size, height: size * 0.7)
    }
}

struct QuarterRestSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            // Quarter rest — classic zigzag shape
            var p = Path()
            p.move(to:    CGPoint(x: sz.width*0.55, y: sz.height*0.05))
            p.addCurve(to: CGPoint(x: sz.width*0.30, y: sz.height*0.30),
                control1:   CGPoint(x: sz.width*0.70, y: sz.height*0.12),
                control2:   CGPoint(x: sz.width*0.25, y: sz.height*0.20))
            p.addCurve(to: CGPoint(x: sz.width*0.65, y: sz.height*0.55),
                control1:   CGPoint(x: sz.width*0.42, y: sz.height*0.40),
                control2:   CGPoint(x: sz.width*0.72, y: sz.height*0.45))
            p.addCurve(to: CGPoint(x: sz.width*0.28, y: sz.height*0.72),
                control1:   CGPoint(x: sz.width*0.55, y: sz.height*0.66),
                control2:   CGPoint(x: sz.width*0.22, y: sz.height*0.65))
            p.addLine(to: CGPoint(x: sz.width*0.38, y: sz.height*0.88))
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: sz.width*0.09, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size * 1.4)
    }
}

struct EighthRestSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            // Eighth rest — diagonal line with filled dot
            var line = Path()
            line.move(to: CGPoint(x: sz.width*0.65, y: sz.height*0.10))
            line.addLine(to: CGPoint(x: sz.width*0.30, y: sz.height*0.88))
            ctx.stroke(line, with: .color(color), lineWidth: sz.width*0.09)
            var dot = Path()
            dot.addEllipse(in: CGRect(x: sz.width*0.50, y: sz.height*0.08, width: sz.width*0.28, height: sz.height*0.20))
            ctx.fill(dot, with: .color(color))
        }
        .frame(width: size, height: size * 1.3)
    }
}

struct SixteenthRestSymbol: View {
    var color: Color = .white
    var size: CGFloat = 20
    var body: some View {
        Canvas { ctx, sz in
            var line = Path()
            line.move(to: CGPoint(x: sz.width*0.65, y: sz.height*0.08))
            line.addLine(to: CGPoint(x: sz.width*0.28, y: sz.height*0.90))
            ctx.stroke(line, with: .color(color), lineWidth: sz.width*0.09)
            for (x, y, s) in [(0.45, 0.06, 0.24), (0.62, 0.36, 0.24)] as [(Double,Double,Double)] {
                var dot = Path()
                dot.addEllipse(in: CGRect(x: sz.width*x, y: sz.height*y,
                                          width: sz.width*s, height: sz.height*(s*0.8)))
                ctx.fill(dot, with: .color(color))
            }
        }
        .frame(width: size, height: size * 1.4)
    }
}

// MARK: - Sharp / Flat / Natural
struct SharpSymbol: View {
    var color: Color = .white
    var size: CGFloat = 16
    var body: some View {
        Canvas { ctx, sz in
            // Two vertical lines
            for xFrac in [0.35, 0.65] as [Double] {
                var v = Path()
                v.move(to: CGPoint(x: sz.width*xFrac, y: sz.height*0.05))
                v.addLine(to: CGPoint(x: sz.width*xFrac, y: sz.height*0.95))
                ctx.stroke(v, with: .color(color), lineWidth: sz.width*0.12)
            }
            // Two horizontal lines (slightly angled)
            for yFrac in [0.32, 0.62] as [Double] {
                var h = Path()
                h.move(to: CGPoint(x: sz.width*0.10, y: sz.height*(yFrac+0.04)))
                h.addLine(to: CGPoint(x: sz.width*0.90, y: sz.height*(yFrac-0.04)))
                ctx.stroke(h, with: .color(color), lineWidth: sz.width*0.11)
            }
        }
        .frame(width: size, height: size * 1.3)
    }
}

struct FlatSymbol: View {
    var color: Color = .white
    var size: CGFloat = 16
    var body: some View {
        Canvas { ctx, sz in
            var p = Path()
            p.move(to: CGPoint(x: sz.width*0.25, y: sz.height*0.02))
            p.addLine(to: CGPoint(x: sz.width*0.25, y: sz.height*0.95))
            p.addCurve(
                to: CGPoint(x: sz.width*0.25, y: sz.height*0.62),
                control1: CGPoint(x: sz.width*0.88, y: sz.height*0.62),
                control2: CGPoint(x: sz.width*0.88, y: sz.height*0.38)
            )
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: sz.width*0.12, lineCap: .round))
        }
        .frame(width: size, height: size * 1.4)
    }
}

struct NaturalSymbol: View {
    var color: Color = .white
    var size: CGFloat = 16
    var body: some View {
        Canvas { ctx, sz in
            var p = Path()
            // Left vertical (partial)
            p.move(to: CGPoint(x: sz.width*0.22, y: sz.height*0.10))
            p.addLine(to: CGPoint(x: sz.width*0.22, y: sz.height*0.72))
            // Top horizontal
            p.addLine(to: CGPoint(x: sz.width*0.78, y: sz.height*0.58))
            // Right vertical (partial)
            p.move(to: CGPoint(x: sz.width*0.78, y: sz.height*0.28))
            p.addLine(to: CGPoint(x: sz.width*0.78, y: sz.height*0.92))
            // Bottom horizontal
            p.addLine(to: CGPoint(x: sz.width*0.22, y: sz.height*0.78))
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: sz.width*0.12, lineCap: .square))
        }
        .frame(width: size, height: size * 1.4)
    }
}

// MARK: - Tie / Slur curve
struct TieCurveSymbol: View {
    var color: Color = .white
    var size: CGFloat = 24
    var isSlur: Bool = false // false = Carry (arcs ABOVE), true = Slur (dips BELOW)
    var body: some View {
        Canvas { ctx, sz in
            var p = Path()
            // Canvas Y increases downward: a SMALLER midY pulls the curve UP (Carry),
            // a LARGER midY pushes the curve DOWN (Slur).
            let midY = sz.height * (isSlur ? 0.75 : 0.25)
            p.move(to: CGPoint(x: sz.width*0.05, y: sz.height*0.5))
            p.addCurve(
                to: CGPoint(x: sz.width*0.95, y: sz.height*0.5),
                control1: CGPoint(x: sz.width*0.3, y: midY),
                control2: CGPoint(x: sz.width*0.7, y: midY)
            )
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: sz.width*0.055, lineCap: .round))
        }
        .frame(width: size * 1.4, height: size * 0.6)
    }
}

// MARK: - Accent mark
struct AccentSymbol: View {
    var color: Color = .white
    var size: CGFloat = 16
    var body: some View {
        Canvas { ctx, sz in
            var p = Path()
            p.move(to: CGPoint(x: sz.width*0.08, y: sz.height*0.22))
            p.addLine(to: CGPoint(x: sz.width*0.92, y: sz.height*0.50))
            p.addLine(to: CGPoint(x: sz.width*0.08, y: sz.height*0.78))
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: sz.width*0.12, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size * 0.8)
    }
}

// MARK: - Note symbol view factory
struct NoteSymbolView: View {
    let duration: NoteDuration
    var color: Color = .white
    var size: CGFloat = 22
    var isRest: Bool = false

    var body: some View {
        if isRest {
            restView
        } else {
            noteView
        }
    }

    @ViewBuilder var noteView: some View {
        switch duration {
        case .whole:      WholeNoteSymbol(color: color, size: size)
        case .half:       HalfNoteSymbol(color: color, size: size)
        case .quarter:    QuarterNoteSymbol(color: color, size: size)
        case .eighth:     EighthNoteSymbol(color: color, size: size)
        case .sixteenth:  SixteenthNoteSymbol(color: color, size: size)
        }
    }

    @ViewBuilder var restView: some View {
        switch duration {
        case .whole:      WholeRestSymbol(color: color, size: size)
        case .half:       HalfRestSymbol(color: color, size: size)
        case .quarter:    QuarterRestSymbol(color: color, size: size)
        case .eighth:     EighthRestSymbol(color: color, size: size)
        case .sixteenth:  SixteenthRestSymbol(color: color, size: size)
        }
    }
}

// MARK: - Rest Duration helper
enum RestDurationHelper {
    static func noteFor(_ rest: RestDuration) -> NoteDuration {
        switch rest {
        case .whole:      return .whole
        case .half:       return .half
        case .quarter:    return .quarter
        case .eighth:     return .eighth
        case .sixteenth:  return .sixteenth
        }
    }
}
