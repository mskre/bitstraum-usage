import Foundation

@main
struct DetachedPanelThemeTests {
    static func main() {
        let metrics = DetachedPanelChromeMetrics.smokedGlass
        guard metrics.cornerRadius <= 18 else {
            fatalError("Expected smoked-glass theme to keep the radius modest")
        }
        guard metrics.baseOpacity > 0.45 else {
            fatalError("Expected smoked-glass theme to use a darker base opacity")
        }
        guard !metrics.showsTopTab else {
            fatalError("Expected smoked-glass theme to remove the visible notch/tab treatment")
        }
    }
}
