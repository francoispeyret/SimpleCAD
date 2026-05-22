import Foundation

// MARK: - DocumentUnit

enum DocumentUnit: String, CaseIterable, Codable, Identifiable {
    var id: String { rawValue }

    case mm = "mm"
    case cm = "cm"
    case m  = "m"
    case km = "km"
    case `in` = "in"
    case ft   = "ft"
    case yd   = "yd"
    case mi   = "mi"

    // Pixels per unit at 96 DPI (1 in = 96 px, 1 in = 25.4 mm)
    var pixelsPerUnit: Double {
        switch self {
        case .mm: return 96.0 / 25.4
        case .cm: return 96.0 / 2.54
        case .m:  return 96.0 / 0.0254
        case .km: return 96.0 / 0.0000254
        case .in: return 96.0
        case .ft: return 96.0 * 12.0
        case .yd: return 96.0 * 36.0
        case .mi: return 96.0 * 63360.0
        }
    }

    var decimals: Int {
        switch self {
        case .mm: return 1
        case .cm: return 2
        case .m:  return 3
        case .km: return 6
        case .in: return 2
        case .ft: return 3
        case .yd: return 3
        case .mi: return 5
        }
    }

    func fromPixels(_ px: Double) -> Double { px / pixelsPerUnit }
    func toPixels(_ value: Double) -> Double { value * pixelsPerUnit }

    func format(_ px: Double) -> String {
        String(format: "%.\(decimals)f \(rawValue)", fromPixels(px))
    }

    func formatValue(_ px: Double) -> String {
        String(format: "%.\(decimals)f", fromPixels(px))
    }
}
