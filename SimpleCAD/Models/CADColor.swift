import AppKit

struct CADColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let black  = CADColor(red: 0,   green: 0,   blue: 0,   alpha: 1)
    static let white  = CADColor(red: 1,   green: 1,   blue: 1,   alpha: 1)
    static let clear  = CADColor(red: 0,   green: 0,   blue: 0,   alpha: 0)
    static let blue   = CADColor(red: 0,   green: 0.47, blue: 1,  alpha: 1)
    static let gray   = CADColor(red: 0.5, green: 0.5,  blue: 0.5, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(_ nsColor: NSColor) {
        guard let c = nsColor.usingColorSpace(.sRGB) else { self = .black; return }
        red = Double(c.redComponent)
        green = Double(c.greenComponent)
        blue = Double(c.blueComponent)
        alpha = Double(c.alphaComponent)
    }

    init(hex: String, alpha: Double = 1.0) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        red   = Double((rgb >> 16) & 0xFF) / 255
        green = Double((rgb >> 8)  & 0xFF) / 255
        blue  = Double(rgb         & 0xFF) / 255
        self.alpha = alpha
    }

    var nsColor: NSColor {
        let comps: [CGFloat] = [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha)]
        return NSColor(colorSpace: .sRGB, components: comps, count: 4)
    }

    var hexString: String {
        String(format: "#%02X%02X%02X",
               Int((red   * 255).rounded()),
               Int((green * 255).rounded()),
               Int((blue  * 255).rounded()))
    }

    func withAlpha(_ a: Double) -> CADColor {
        CADColor(red: red, green: green, blue: blue, alpha: a)
    }
}
