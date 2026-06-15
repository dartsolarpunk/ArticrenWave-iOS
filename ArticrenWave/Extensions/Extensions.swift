// Extensions.swift — Utility extensions for ArticrenWave
import SwiftUI

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:  (a,r,g,b) = (255,(int>>8)*17,(int>>4 & 0xF)*17,(int & 0xF)*17)
        case 6:  (a,r,g,b) = (255,int>>16,int>>8 & 0xFF,int & 0xFF)
        case 8:  (a,r,g,b) = (int>>24,int>>16 & 0xFF,int>>8 & 0xFF,int & 0xFF)
        default: (a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// Safe MIDI note clamp 0–127
func midiNote(_ value: Int) -> UInt8 {
    UInt8(Swift.max(0, Swift.min(127, value)))
}

extension InstrumentFamily {
    var clef: Clef {
        switch self {
        case .cello, .doubleBass, .bassoon, .tuba, .trombone: return .bass
        default: return .treble
        }
    }
}
