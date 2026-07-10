import SwiftUI

/// Dark focus vignette around the screen edges.
struct VignetteView: View {
    private let depth: CGFloat = 180
    private let strength = 0.55

    var body: some View {
        ZStack {
            edge(.top)
            edge(.bottom)
            edge(.leading)
            edge(.trailing)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func edge(_ side: Edge) -> some View {
        let gradient = LinearGradient(
            colors: [Color.black.opacity(strength), .clear],
            startPoint: side.startPoint,
            endPoint: side.endPoint
        )
        switch side {
        case .top:
            VStack { Rectangle().fill(gradient).frame(height: depth); Spacer() }
        case .bottom:
            VStack { Spacer(); Rectangle().fill(gradient).frame(height: depth) }
        case .leading:
            HStack { Rectangle().fill(gradient).frame(width: depth); Spacer() }
        case .trailing:
            HStack { Spacer(); Rectangle().fill(gradient).frame(width: depth) }
        }
    }
}

private extension Edge {
    var startPoint: UnitPoint {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    var endPoint: UnitPoint {
        switch self {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }
}
