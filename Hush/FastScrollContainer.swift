import SwiftUI
import UIKit

/// A library tab's scroll view, with a floating A–Z index (alphabetical lists) or a draggable
/// scroll bar (other orders), row-by-row scroll ticks, pull to refresh, scroll-to-top and room for
/// the mini player.
struct FastScrollContainer<ItemID: Hashable, Content: View>: View {
    let itemIDs: [ItemID]
    let isAlphabetical: Bool
    private let letterTargets: [AlphabeticalLetterTarget<ItemID>]
    let itemsPerRow: Int
    let estimatedRowHeight: CGFloat
    let estimatedPadding: CGFloat
    let onRefresh: () async -> Void
    let onScrollOffsetChange: ((CGFloat, CGFloat) -> Void)?
    /// Changes when you tap the tab you're already on: scrolls back to the top (like Apple's apps).
    let scrollToTopSignal: Int?
    let content: Content

    @Environment(\.miniPlayerTop) private var miniPlayerTop
    /// Bottom edge of this list on screen, to work out how much of it the mini player covers.
    @State private var viewportBottom: CGFloat = 0
    @State private var metrics = FastScrollMetrics()
    @State private var lastDragTarget: Int?
    @State private var dragProgressFallback: CGFloat?
    @State private var underlyingScrollView: UIScrollView?
    /// The A–Z index / scroll bar floats over the artwork only while the list is moving (or you're
    /// touching it), then fades away.
    @State private var isIndexShown = false
    @State private var isTouchingIndex = false
    @State private var indexHideGeneration = 0
    private let scrollCoordinateSpace = UUID()

    /// Scroll activity is only reported on iOS 18+; before that the index simply stays visible.
    private var showsIndex: Bool {
        if #available(iOS 18.0, *) { return isIndexShown || isTouchingIndex }
        return true
    }

    init(
        itemIDs: [ItemID],
        letterTargets: [AlphabeticalLetterTarget<ItemID>],
        isAlphabetical: Bool,
        itemsPerRow: Int,
        estimatedRowHeight: CGFloat,
        estimatedPadding: CGFloat,
        onRefresh: @escaping () async -> Void,
        onScrollOffsetChange: ((CGFloat, CGFloat) -> Void)? = nil,
        scrollToTopSignal: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.scrollToTopSignal = scrollToTopSignal
        self.itemIDs = itemIDs
        self.isAlphabetical = isAlphabetical
        self.letterTargets = isAlphabetical ? letterTargets : []
        self.itemsPerRow = max(itemsPerRow, 1)
        self.estimatedRowHeight = estimatedRowHeight
        self.estimatedPadding = estimatedPadding
        self.onRefresh = onRefresh
        self.onScrollOffsetChange = onScrollOffsetChange
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { viewport in
                let rowCount = (itemIDs.count + itemsPerRow - 1) / itemsPerRow
                let viewportHeight = viewport.size.height.isFinite ? max(viewport.size.height, 0) : 0
                let measuredContentHeight = metrics.contentHeight.isFinite ? max(metrics.contentHeight, 0) : 0
                let measuredContentMinY = metrics.contentMinY.isFinite ? metrics.contentMinY : 0
                let rowHeight = estimatedRowHeight.isFinite ? max(estimatedRowHeight, 0) : 0
                let paddingHeight = estimatedPadding.isFinite ? max(estimatedPadding, 0) : 0
                let estimatedContentHeight = CGFloat(rowCount) * rowHeight + paddingHeight
                let contentHeight = max(measuredContentHeight, estimatedContentHeight)
                let maxOffset = max(contentHeight - viewportHeight, 0)
                let measuredProgress = measuredContentHeight > viewportHeight && maxOffset > 0
                    ? min(max(-measuredContentMinY / max(measuredContentHeight - viewportHeight, 1), 0), 1)
                    : 0
                let progress = dragProgressFallback ?? measuredProgress
                let visibleFraction = contentHeight > 0
                    ? min(viewportHeight / contentHeight, 1)
                    : 1
                // The swipeable library tabs don't get room for the mini player from the system,
                // so the last rows used to hide behind it. Leave exactly the covered space.
                let bottomClearance = MiniPlayerClearance.margin(bottomEdge: viewportBottom, miniPlayerTop: miniPlayerTop)
                // The A–Z index / scroll bar stops well above the mini player: right next to it, the
                // glass picked it up as a grey line along its right side.
                let indexBottomInset = miniPlayerTop.isFinite && viewportBottom > 0
                    ? max(viewportBottom - miniPlayerTop + 28, 0)
                    : 0

                ScrollView(showsIndicators: false) {
                    content
                        .background {
                            GeometryReader { contentGeometry in
                                Color.clear.preference(
                                    key: FastScrollMetricsPreferenceKey.self,
                                    value: FastScrollMetrics(
                                        contentHeight: contentGeometry.size.height,
                                        contentMinY: contentGeometry.frame(in: .named(scrollCoordinateSpace)).minY
                                    )
                                )
                            }
                    }
                    .background {
                        ScrollViewAccess { resolvedScrollView in
                            if underlyingScrollView !== resolvedScrollView {
                                underlyingScrollView = resolvedScrollView
                            }
                        }
                        .frame(width: 0, height: 0)
                    }
                }
                .contentMargins(.bottom, bottomClearance, for: .scrollContent)
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await onRefresh() }
                .modifier(ScrollOffsetReporter(action: onScrollOffsetChange))
                .modifier(ScrollTickHaptics(
                    // One tick per grid row (Playlists, Albums); song rows are shorter, so every
                    // second row — giving all three tabs the same rhythm.
                    stepHeight: (measuredContentHeight > 0 && rowCount > 0
                        ? max((measuredContentHeight - paddingHeight) / CGFloat(rowCount), 1)
                        : rowHeight) * (itemsPerRow == 1 ? 2 : 1)
                ))
                .coordinateSpace(name: scrollCoordinateSpace)
                .modifier(ScrollActivityReporter { isMoving in
                    if isMoving { revealIndex() } else { hideIndexSoon() }
                })
                .overlay(alignment: .trailing) {
                    if itemIDs.count > itemsPerRow, contentHeight > viewportHeight + 1 {
                        // A narrow frosted strip floating over the artwork's right edge.
                        Group {
                            if isAlphabetical {
                                if letterTargets.count > 1 {
                                    AlphabeticalLetterIndex(targets: letterTargets) { targetID, isScrubbing in
                                        if isScrubbing {
                                            scrollProxy.scrollTo(targetID, anchor: .top)
                                        } else {
                                            jumpToLetter(targetID, using: scrollProxy)
                                        }
                                    }
                                    .frame(width: 17)
                                    .padding(.vertical, 6)
                                    .background(FastScrollBackdrop())
                                }
                            } else {
                                FastScrollRail(progress: progress, visibleFraction: visibleFraction) { newProgress in
                                    dragProgressFallback = newProgress
                                    let target = Int((newProgress * CGFloat(itemIDs.count - 1)).rounded())
                                    guard target != lastDragTarget else { return }
                                    lastDragTarget = target
                                    scrollProxy.scrollTo(itemIDs[target], anchor: .top)
                                } onDragEnded: {
                                    lastDragTarget = nil
                                }
                                .frame(width: 13)
                                .background(FastScrollBackdrop())
                            }
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 3)
                        .padding(.bottom, indexBottomInset)
                        .opacity(showsIndex ? 1 : 0)
                        .allowsHitTesting(showsIndex)
                        // Touching it keeps it up while you scrub, then it fades after you let go.
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    guard !isTouchingIndex else { return }
                                    isTouchingIndex = true
                                    revealIndex()
                                }
                                .onEnded { _ in
                                    isTouchingIndex = false
                                    hideIndexSoon()
                                }
                        )
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { edge in
                    if abs(edge - viewportBottom) > 0.5 { viewportBottom = edge }
                }
                .onChange(of: scrollToTopSignal) { _, signal in
                    guard signal != nil else { return }
                    scrollToTop(using: scrollProxy)
                }
                .onPreferenceChange(FastScrollMetricsPreferenceKey.self) { newMetrics in
                    let safeContentHeight = newMetrics.contentHeight.isFinite ? max(newMetrics.contentHeight, 0) : 0
                    let safeContentMinY = newMetrics.contentMinY.isFinite ? newMetrics.contentMinY : 0
                    if isAlphabetical {
                        guard metrics.contentHeight != safeContentHeight else { return }
                        metrics = FastScrollMetrics(contentHeight: safeContentHeight)
                    } else {
                        metrics = FastScrollMetrics(contentHeight: safeContentHeight, contentMinY: safeContentMinY)
                        dragProgressFallback = nil
                    }
                }
            }
        }
    }

    private func revealIndex() {
        indexHideGeneration += 1
        guard !isIndexShown else { return }
        withAnimation(.easeOut(duration: 0.18)) { isIndexShown = true }
    }

    /// Fades the index out shortly after the list stops (unless it's being touched by then).
    private func hideIndexSoon() {
        indexHideGeneration += 1
        let generation = indexHideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard generation == indexHideGeneration, !isTouchingIndex, isIndexShown else { return }
            withAnimation(.easeInOut(duration: 0.18)) { isIndexShown = false }
        }
    }

    private func scrollToTop(using scrollProxy: ScrollViewProxy) {
        if let scrollView = underlyingScrollView {
            // The true top, including the space above the first row.
            let top = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top)
            scrollView.setContentOffset(top, animated: true)
        } else if let first = itemIDs.first {
            withAnimation(.smooth(duration: 0.35)) {
                scrollProxy.scrollTo(first, anchor: .top)
            }
        }
    }

    private func jumpToLetter(_ targetID: ItemID, using scrollProxy: ScrollViewProxy) {
        stopScrollMotion()
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                scrollProxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

    private func stopScrollMotion() {
        guard let underlyingScrollView else { return }
        underlyingScrollView.setContentOffset(underlyingScrollView.contentOffset, animated: false)
        underlyingScrollView.panGestureRecognizer.isEnabled = false
        underlyingScrollView.panGestureRecognizer.isEnabled = true
    }

}

/// Reports whether the list is moving (dragged, gliding or animating) — iOS 18+.
private struct ScrollActivityReporter: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { oldPhase, newPhase in
                let wasMoving = oldPhase != .idle
                let isMoving = newPhase != .idle
                if wasMoving != isMoving { onChange(isMoving) }
            }
        } else {
            content
        }
    }
}

/// The narrow frosted strip behind the floating A–Z index / scroll bar, so it reads over artwork.
private struct FastScrollBackdrop: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(Capsule(style: .continuous).fill(HushStyle.paper.opacity(0.35)))
            .overlay(Capsule(style: .continuous).stroke(HushStyle.ink.opacity(0.08), lineWidth: 0.5))
    }
}

/// A ratchet-like tick for each row that passes while you scroll (same rhythm on every tab).
/// Only while your finger is scrolling or the list is gliding — not for jumps made with the A–Z
/// index, which tick on their own. Needs iOS 18.
private struct ScrollTickHaptics: ViewModifier {
    let stepHeight: CGFloat

    @State private var isUserScrolling = false

    func body(content: Content) -> some View {
        if stepHeight > 0 {
            if #available(iOS 18.0, *) {
                content
                    .onScrollPhaseChange { _, phase in
                        isUserScrolling = phase == .interacting || phase == .decelerating
                        // Warm up as soon as a scroll starts so the first row tick isn't late.
                        if phase == .interacting { Haptics.prepare() }
                    }
                    .onScrollGeometryChange(for: Int.self) { geometry in
                        let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
                        return Int((max(scrolled, 0) / stepHeight).rounded(.down))
                    } action: { oldStep, newStep in
                        if isUserScrolling, oldStep != newStep { Haptics.selection() }
                    }
            } else {
                content
            }
        } else {
            content
        }
    }
}

/// Reports how far a scroll view is scrolled from its top. Needs iOS 18; on older versions the header just stays put.
private struct ScrollOffsetReporter: ViewModifier {
    let action: ((CGFloat, CGFloat) -> Void)?

    func body(content: Content) -> some View {
        if let action {
            if #available(iOS 18.0, *) {
                content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { oldValue, newValue in
                    action(oldValue, newValue)
                }
            } else {
                content
            }
        } else {
            content
        }
    }
}

private struct ScrollViewAccess: UIViewRepresentable {
    let onResolve: (UIScrollView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.resolveScrollView(from: view, onResolve: onResolve)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.resolveScrollView(from: view, onResolve: onResolve)
    }

    final class Coordinator {
        weak var resolvedScrollView: UIScrollView?

        func resolveScrollView(from view: UIView, onResolve: @escaping (UIScrollView) -> Void) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                var ancestor = view.superview
                while let current = ancestor {
                    if let scrollView = current as? UIScrollView {
                        guard self.resolvedScrollView !== scrollView else { return }
                        self.resolvedScrollView = scrollView
                        onResolve(scrollView)
                        return
                    }
                    ancestor = current.superview
                }
            }
        }
    }
}

/// One letter of the A–Z index and the first item filed under it.
struct AlphabeticalLetterTarget<ItemID: Hashable>: Identifiable {
    let letter: String
    let itemID: ItemID

    var id: String { letter }

    /// The first item for each letter, in list order. Built when a tab's list is rebuilt, not on
    /// every redraw.
    static func firstOfEachLetter(ids: [ItemID], letters: [String]) -> [AlphabeticalLetterTarget] {
        var seen = Set<String>()
        return zip(letters, ids).compactMap { letter, itemID in
            guard seen.insert(letter).inserted else { return nil }
            return AlphabeticalLetterTarget(letter: letter, itemID: itemID)
        }
    }
}

private struct AlphabeticalLetterIndex<ItemID: Hashable>: View {
    let targets: [AlphabeticalLetterTarget<ItemID>]
    let onSelect: (ItemID, Bool) -> Void

    @State private var activeIndex: Int?
    @State private var lastDraggedIndex: Int?
    @State private var isScrubbing = false
    @State private var focusGeneration = 0

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height.isFinite ? max(geometry.size.height, 0) : 0
            let cellHeight = availableHeight / CGFloat(max(targets.count, 1))
            VStack(spacing: 0) {
                ForEach(Array(targets.enumerated()), id: \.element.letter) { index, target in
                    let isActive = activeIndex == index
                    let regularSize = min(12, max(9, cellHeight * 0.52))
                    let activeSize = min(15, max(regularSize + 3, cellHeight * 0.76))
                    Button {
                        isScrubbing = false
                        lastDraggedIndex = nil
                        setActiveIndex(index, isDragging: false)
                        onSelect(target.itemID, false)
                        scheduleFocusReset(for: index)
                    } label: {
                        Text(target.letter)
                            .font(.system(size: isActive ? activeSize : regularSize, weight: .semibold))
                            .foregroundStyle(isActive ? HushStyle.accent : HushStyle.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: cellHeight)
                            .background {
                                if isActive {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(HushStyle.accent.opacity(0.20))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .stroke(HushStyle.accent.opacity(0.55), lineWidth: 0.7)
                                        }
                                        .frame(width: 15, height: min(26, max(0, cellHeight - 2)))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scroll to \(target.letter)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        guard !targets.isEmpty, availableHeight > 0 else { return }
                        let position = min(max(value.location.y / availableHeight, 0), 0.999)
                        let index = min(Int(position * CGFloat(targets.count)), targets.count - 1)
                        isScrubbing = true
                        guard index != lastDraggedIndex else { return }
                        lastDraggedIndex = index
                        setActiveIndex(index, isDragging: true)
                        onSelect(targets[index].itemID, true)
                    }
                    .onEnded { _ in
                        isScrubbing = false
                        lastDraggedIndex = nil
                        if let activeIndex { scheduleFocusReset(for: activeIndex) }
                    }
            )
        }
        .accessibilityElement(children: .contain)
        .onChange(of: activeIndex) { _, newValue in
            if newValue != nil { Haptics.selection() }
        }
    }

    private func setActiveIndex(_ index: Int, isDragging: Bool) {
        if isDragging {
            withAnimation(.easeOut(duration: 0.07)) {
                activeIndex = index
            }
        } else {
            withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                activeIndex = index
            }
        }
    }

    private func scheduleFocusReset(for index: Int) {
        focusGeneration += 1
        let generation = focusGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard !isScrubbing, activeIndex == index, focusGeneration == generation else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                activeIndex = nil
            }
        }
    }
}

private struct FastScrollRail: View {
    let progress: CGFloat
    let visibleFraction: CGFloat
    let onDrag: (CGFloat) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeWidth = geometry.size.width.isFinite ? max(geometry.size.width, 0) : 0
            let safeHeight = geometry.size.height.isFinite ? max(geometry.size.height, 0) : 0
            let safeProgress = progress.isFinite ? min(max(progress, 0), 1) : 0
            let safeVisibleFraction = visibleFraction.isFinite ? min(max(visibleFraction, 0), 1) : 1
            let verticalInset = min(10, safeHeight / 2)
            let trackHeight = max(safeHeight - verticalInset * 2, 1)
            let thumbHeight = min(trackHeight, max(38, trackHeight * safeVisibleFraction))
            let travel = max(trackHeight - thumbHeight, 0)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(HushStyle.line.opacity(0.65))
                    .frame(width: 2, height: trackHeight)

                Capsule()
                    .fill(HushStyle.accent.opacity(0.9))
                    .frame(width: 5, height: thumbHeight)
                    .offset(y: safeProgress * travel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, verticalInset)
            .frame(width: safeWidth, height: safeHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard travel > 0 else { return }
                        let position = (value.location.y - verticalInset - thumbHeight / 2) / travel
                        onDrag(min(max(position, 0), 1))
                    }
                    .onEnded { _ in onDragEnded() }
            )
            .accessibilityElement()
            .accessibilityLabel("Fast scroll")
            .accessibilityValue("\(Int((safeProgress * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onDrag(min(safeProgress + 0.1, 1))
                case .decrement:
                    onDrag(max(safeProgress - 0.1, 0))
                @unknown default:
                    break
                }
            }
        }
    }
}

private struct FastScrollMetrics: Equatable {
    var contentHeight: CGFloat = 0
    var contentMinY: CGFloat = 0
}

private struct FastScrollMetricsPreferenceKey: PreferenceKey {
    static let defaultValue = FastScrollMetrics()

    static func reduce(value: inout FastScrollMetrics, nextValue: () -> FastScrollMetrics) {
        value = nextValue()
    }
}
