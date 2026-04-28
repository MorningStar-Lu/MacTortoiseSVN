import SwiftUI

struct WorkbenchLayout {
    static let sidebarWidth: CGFloat = 220
    static let minimumWindowSize = CGSize(width: 780, height: 560)

    let size: CGSize

    var usesCompactStack: Bool {
        size.width < 1320
    }

    var usesMinimalCommitMode: Bool {
        size.width < 1120 || size.height < 760
    }

    var pathBarWraps: Bool {
        size.width < 1560
    }

    var outerPadding: CGFloat {
        size.width < 1100 ? 12 : 16
    }
}

enum RatioSplitAxis {
    case horizontal
    case vertical
}

struct RatioSplit<First: View, Second: View>: View {
    let axis: RatioSplitAxis
    @Binding var ratio: Double
    let firstMin: CGFloat
    let secondMin: CGFloat
    let dividerThickness: CGFloat
    let first: First
    let second: Second

    @State private var dragStartFirstSpan: CGFloat?

    init(
        axis: RatioSplitAxis,
        ratio: Binding<Double>,
        firstMin: CGFloat,
        secondMin: CGFloat,
        dividerThickness: CGFloat = CommitPalette.panelGutter,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.axis = axis
        self._ratio = ratio
        self.firstMin = firstMin
        self.secondMin = secondMin
        self.dividerThickness = dividerThickness
        self.first = first()
        self.second = second()
    }

    var body: some View {
        GeometryReader { proxy in
            let totalSpan = axis == .horizontal ? proxy.size.width : proxy.size.height
            let contentSpan = max(0, totalSpan - dividerThickness)
            let minimumTotal = max(1, firstMin + secondMin)
            let compressionScale = min(1, contentSpan / minimumTotal)
            let effectiveFirstMin = firstMin * compressionScale
            let effectiveSecondMin = secondMin * compressionScale
            let lowerBound = contentSpan > 0 ? Double(effectiveFirstMin / contentSpan) : 0
            let upperBound = contentSpan > 0 ? Double(1 - (effectiveSecondMin / contentSpan)) : 1
            let clampedUpperBound = max(lowerBound, upperBound)
            let clampedRatio = min(max(ratio, lowerBound), clampedUpperBound)
            let firstSpan = max(
                effectiveFirstMin,
                min(contentSpan * clampedRatio, max(effectiveFirstMin, contentSpan - effectiveSecondMin))
            )
            let secondSpan = max(0, contentSpan - firstSpan)

            Group {
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        first
                            .frame(width: firstSpan, height: proxy.size.height)

                        SplitDivider(axis: axis)
                            .frame(width: dividerThickness, height: proxy.size.height)
                            .gesture(
                                dragGesture(
                                    currentFirstSpan: firstSpan,
                                    totalContentSpan: contentSpan,
                                    lowerBound: lowerBound,
                                    upperBound: clampedUpperBound
                                )
                            )

                        second
                            .frame(width: secondSpan, height: proxy.size.height)
                    }
                } else {
                    VStack(spacing: 0) {
                        first
                            .frame(width: proxy.size.width, height: firstSpan)

                        SplitDivider(axis: axis)
                            .frame(width: proxy.size.width, height: dividerThickness)
                            .gesture(
                                dragGesture(
                                    currentFirstSpan: firstSpan,
                                    totalContentSpan: contentSpan,
                                    lowerBound: lowerBound,
                                    upperBound: clampedUpperBound
                                )
                            )

                        second
                            .frame(width: proxy.size.width, height: secondSpan)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                guard abs(clampedRatio - ratio) > 0.0001 else {
                    return
                }
                DispatchQueue.main.async {
                    ratio = clampedRatio
                }
            }
        }
    }

    private func dragGesture(
        currentFirstSpan: CGFloat,
        totalContentSpan: CGFloat,
        lowerBound: Double,
        upperBound: Double
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard totalContentSpan > 0 else {
                    return
                }

                if dragStartFirstSpan == nil {
                    dragStartFirstSpan = currentFirstSpan
                }

                let baseSpan = dragStartFirstSpan ?? currentFirstSpan
                let translation = axis == .horizontal ? value.translation.width : value.translation.height
                let updatedSpan = min(
                    max(baseSpan + translation, CGFloat(lowerBound) * totalContentSpan),
                    CGFloat(upperBound) * totalContentSpan
                )

                ratio = min(max(Double(updatedSpan / totalContentSpan), lowerBound), upperBound)
            }
            .onEnded { _ in
                dragStartFirstSpan = nil
            }
    }
}

struct SplitDivider: View {
    let axis: RatioSplitAxis
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if axis == .horizontal {
                Rectangle()
                    .fill(CommitPalette.border.opacity(isHovering ? 0.95 : 0.7))
                    .frame(width: 2)

                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(CommitPalette.toolbarFill.opacity(isHovering ? 1 : 0.85))
                    .frame(width: isHovering ? 8 : 6, height: 52)
            } else {
                Rectangle()
                    .fill(CommitPalette.border.opacity(isHovering ? 0.95 : 0.7))
                    .frame(height: 2)

                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(CommitPalette.toolbarFill.opacity(isHovering ? 1 : 0.85))
                    .frame(width: 52, height: isHovering ? 8 : 6)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}
