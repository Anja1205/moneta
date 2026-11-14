import SwiftUI

/// Minimal price line with a soft fill, coloured by the move over the series.
struct Sparkline: View {
    let points: [Double]
    var color: Color? = nil
    var lineWidth: CGFloat = 1.8

    private var resolvedColor: Color {
        if let color { return color }
        guard let first = points.first, let last = points.last else { return Palette.muted }
        return Palette.change(first == 0 ? 0 : last / first - 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let path = linePath(in: proxy.size)
            ZStack {
                fillPath(path, in: proxy.size)
                    .fill(LinearGradient(colors: [resolvedColor.opacity(0.25), resolvedColor.opacity(0)], startPoint: .top, endPoint: .bottom))
                path.stroke(resolvedColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func linePath(in size: CGSize) -> Path {
        var path = Path()
        guard points.count > 1, let low = points.min(), let high = points.max() else { return path }
        let span = max(high - low, high * 0.0005)
        for (index, value) in points.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
            let y = size.height * (1 - CGFloat((value - low) / span)) * 0.9 + size.height * 0.05
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }

    private func fillPath(_ line: Path, in size: CGSize) -> Path {
        var path = line
        guard !line.isEmpty else { return path }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

extension Array where Element == PricePoint {
    /// Every n-th price so sparklines stay light.
    func sparkValues(maxPoints: Int = 60) -> [Double] {
        guard count > maxPoints else { return map(\.price) }
        let step = Double(count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { self[Int((Double($0) * step).rounded())].price }
    }
}

#Preview {
    Sparkline(points: [1, 1.2, 1.1, 1.4, 1.35, 1.6])
        .frame(width: 140, height: 44)
        .padding()
        .background(Palette.background)
}
