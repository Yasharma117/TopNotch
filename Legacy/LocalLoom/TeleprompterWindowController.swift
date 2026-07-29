import AppKit
import SwiftUI
import Combine

public final class TeleprompterWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>

    public init<Content: View>(content: Content, screen: NSScreen) {
        let styleMask: NSWindow.StyleMask = [.borderless]
        let frame = NSRect(origin: .zero, size: CGSize(width: 800, height: 100))
        let window = NSWindow(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false, screen: screen)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true

        hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.frame = window.contentView?.bounds ?? frame
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        super.init(window: window)
        positionNearNotch(on: screen)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setIgnoresMouseEvents(_ flag: Bool) {
        window?.ignoresMouseEvents = flag
    }

    public func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        window?.orderOut(nil)
    }

    private func positionNearNotch(on screen: NSScreen) {
        guard let window = window else { return }
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        let menuBarHeight = fullFrame.height - visibleFrame.height

        let width: CGFloat = min(800, visibleFrame.width)
        let height: CGFloat = 100
        let x = visibleFrame.origin.x + (visibleFrame.width - width) / 2
        let y = visibleFrame.origin.y + visibleFrame.height - height - 10 - menuBarHeight / 2

        let newFrame = NSRect(x: x, y: y, width: width, height: height)
        window.setFrame(newFrame, display: true)
    }
}

public struct TeleprompterView: View {
    @Binding public var text: String
    @Binding public var speed: Double
    @Binding public var isScrolling: Bool

    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var timerCancellable: AnyCancellable?

    public init(text: Binding<String>, speed: Binding<Double>, isScrolling: Binding<Bool>) {
        self._text = text
        self._speed = speed
        self._isScrolling = isScrolling
    }

    public var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.black.opacity(0), location: 0),
                            .init(color: Color.black.opacity(1), location: 0.1),
                            .init(color: Color.black.opacity(1), location: 0.9),
                            .init(color: Color.black.opacity(0), location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 48, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(HeightReader())
                        .offset(y: -offset)
                }
                .disabled(true)
                .onPreferenceChange(HeightPreferenceKey.self) { value in
                    contentHeight = value
                    containerHeight = geo.size.height
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onChange(of: isScrolling) { active in
            if active {
                startScrolling()
            } else {
                stopScrolling()
            }
        }
        .onDisappear {
            stopScrolling()
        }
    }

    private func startScrolling() {
        stopScrolling()
        guard contentHeight > containerHeight else { return }
        timerCancellable = Timer.publish(every: 1/60, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                let maxOffset = contentHeight - containerHeight
                let increment = speed / 60
                offset = min(offset + CGFloat(increment), maxOffset)
                if offset >= maxOffset {
                    stopScrolling()
                }
            }
    }

    private func stopScrolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}

private struct HeightReader: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
        }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct VisualEffectView: NSViewRepresentable {
    public enum Material {
        case appearanceBased
        case light
        case dark
        case titlebar
        case selection
        case menu
        case popover
        case sidebar
        case headerView
        case sheet
        case windowBackground
        case hudWindow
        case fullScreenUI
        case toolTip
        case contentBackground
        case underWindowBackground
        case underPageBackground

        var nsMaterial: NSVisualEffectView.Material {
            switch self {
            case .appearanceBased: return .appearanceBased
            case .light: return .light
            case .dark: return .dark
            case .titlebar: return .titlebar
            case .selection: return .selection
            case .menu: return .menu
            case .popover: return .popover
            case .sidebar: return .sidebar
            case .headerView: return .headerView
            case .sheet: return .sheet
            case .windowBackground: return .windowBackground
            case .hudWindow: return .hudWindow
            case .fullScreenUI: return .fullScreenUI
            case .toolTip: return .toolTip
            case .contentBackground: return .contentBackground
            case .underWindowBackground: return .underWindowBackground
            case .underPageBackground: return .underPageBackground
            }
        }
    }

    public enum BlendingMode {
        case behindWindow
        case withinWindow

        var nsBlendingMode: NSVisualEffectView.BlendingMode {
            switch self {
            case .behindWindow: return .behindWindow
            case .withinWindow: return .withinWindow
            }
        }
    }

    public var material: Material = .appearanceBased
    public var blendingMode: BlendingMode = .withinWindow
    public var state: NSVisualEffectView.State = .followsWindowActiveState

    public init(material: Material = .appearanceBased, blendingMode: BlendingMode = .withinWindow, state: NSVisualEffectView.State = .followsWindowActiveState) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material.nsMaterial
        view.blendingMode = blendingMode.nsBlendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material.nsMaterial
        nsView.blendingMode = blendingMode.nsBlendingMode
        nsView.state = state
    }
}
