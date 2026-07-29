import AppKit
import SwiftUI
import Combine

final class TeleprompterWindowController: NSWindowController {
    // Overlay interactivity: when true, window ignores mouse events (safe reading)
    private var passThroughEnabled: Bool = true {
        didSet { setIgnoresMouseEvents(passThroughEnabled) }
    }
    
    private let hostingView: NSHostingView<AnyView>

    init<Content: View>(content: Content, screen: NSScreen) {
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

    func update<Content: View>(content: Content) {
        hostingView.rootView = AnyView(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setIgnoresMouseEvents(_ flag: Bool) {
        window?.ignoresMouseEvents = flag
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }
    
    func teleprompterView(text: Binding<String>, speed: Binding<Double>, isScrolling: Binding<Bool>, speechManager: SpeechRecognitionManager) -> TeleprompterView {
        TeleprompterView(text: text, speed: speed, isScrolling: isScrolling, speechManager: speechManager) { passThrough in
            self.passThroughEnabled = passThrough
        }
    }

    func closeWindow() {
        window?.orderOut(nil)
    }

    private func positionNearNotch(on screen: NSScreen) {
        guard let window = window else { return }
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame

        // Menu bar height is the difference between full and visible heights
        let menuBarHeight = fullFrame.height - visibleFrame.height

        // Desired size
        let width: CGFloat = min(800, visibleFrame.width - 40)
        let height: CGFloat = 100

        // Center horizontally within the visible frame (this aligns with the notch on MacBook Pro)
        let x = visibleFrame.origin.x + (visibleFrame.width - width) / 2

        // Place just below the menu bar, with a small padding
        let topPadding: CGFloat = 12
        let y = visibleFrame.origin.y + visibleFrame.height - height - topPadding

        let newFrame = NSRect(x: x, y: y, width: width, height: height)
        window.setFrame(newFrame, display: true)
    }
}

// MARK: - TeleprompterView

/// The TeleprompterView displays scrolling text with optional speech synchronization.
/// It includes an overlay control strip that auto-hides and appears on mouse hover,
/// providing controls for playback, visibility, compact mode, and interactivity (pass-through).
struct TeleprompterView: View {
    @Binding var text: String
    @Binding var speed: Double
    @Binding var isScrolling: Bool

    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var timerCancellable: AnyCancellable?
    
    // Speech sync support
    @StateObject private var speechManager: SpeechRecognitionManager
    @StateObject private var textMatcher = TeleprompterTextMatcher()
    @StateObject private var settings = SettingsManager.shared
    
    @State private var highlightedRange: Range<String.Index>?
    
    // Overlay controls state
    @State private var showControls: Bool = false
    @State private var overlayOpacity: Double = 0.78 // maps to overlay-glass rgba alpha
    @State private var compactMode: Bool = false
    @State private var localPassThrough: Bool = true // mirrors controller pass-through

    // Callback to update window mouse event passthrough
    var onPassThroughChanged: (Bool) -> Void = { _ in }

    init(text: Binding<String>, speed: Binding<Double>, isScrolling: Binding<Bool>, speechManager: SpeechRecognitionManager? = nil, onPassThroughChanged: @escaping (Bool) -> Void = { _ in }) {
        self._text = text
        self._speed = speed
        self._isScrolling = isScrolling
        self._speechManager = StateObject(wrappedValue: speechManager ?? SpeechRecognitionManager())
        self.onPassThroughChanged = onPassThroughChanged
    }

    var body: some View {
        ZStack {
            // Background glass material with adjustable overlay opacity
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .overlay(Color.black.opacity(overlayOpacity * 0.9))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    ZStack(alignment: .topLeading) {
                        Text(text)
                            .font(compactMode ? .system(size: 34, weight: .semibold) : .system(size: 40, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(HeightReader())
                            .offset(y: -offset)
                        
                        // Highlight overlay for speech sync
                        if settings.speechSyncEnabled && settings.speechHighlightPhrase, 
                           let range = highlightedRange {
                            HighlightedText(text: text, highlightRange: range)
                                .font(compactMode ? .system(size: 34, weight: .semibold) : .system(size: 40, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .offset(y: -offset)
                        }
                    }
                }
                .disabled(true)
                .onPreferenceChange(HeightPreferenceKey.self) { value in
                    contentHeight = value
                    containerHeight = geo.size.height
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            
            // Bottom control strip (auto-hide on hover)
            VStack {
                Spacer()
                if showControls {
                    controlStrip
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                showControls = hovering
            }
        }
        .onChange(of: isScrolling) { active in
            if active {
                if settings.speechSyncEnabled {
                    startSpeechSync()
                } else {
                    startScrolling()
                }
            } else {
                stopScrolling()
                stopSpeechSync()
            }
        }
        .onChange(of: speechManager.currentPhrase) { phrase in
            if settings.speechSyncEnabled && speechManager.isListening && !phrase.isEmpty {
                updateScrollPosition(phrase: phrase)
            }
        }
        .onChange(of: settings.speechLocale) { newLocale in
            speechManager.setLocale(newLocale)
        }
        .onAppear {
            textMatcher.setText(text)
            // Ensure window starts in pass-through mode for safe reading
            localPassThrough = true
            onPassThroughChanged(localPassThrough)
            if settings.speechSyncEnabled {
                Task {
                    _ = await speechManager.requestAuthorization()
                }
            }
        }
        .onChange(of: text) { newText in
            textMatcher.setText(newText)
        }
        .onDisappear {
            stopScrolling()
            stopSpeechSync()
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 12) {
            // Left cluster: Play/Pause + Reset + Status
            Button {
                isScrolling.toggle()
            } label: {
                Image(systemName: isScrolling ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(isScrolling ? Color.accentColor.opacity(0.9) : Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            
            Button {
                textMatcher.reset()
                speechManager.reset()
                offset = 0
                isScrolling = false
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            
            if settings.speechSyncEnabled {
                HStack(spacing: 6) {
                    Circle()
                        .fill(speechManager.isListening ? Color.green : Color.yellow)
                        .frame(width: 8, height: 8)
                    Text(speechManager.isListening ? "Listening" : "Paused")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            
            Spacer(minLength: 8)
            
            // Center cluster: Mode-specific control (Speed or Sensitivity placeholder)
            if settings.speechSyncEnabled {
                HStack(spacing: 8) {
                    Text("Sensitivity")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Slider(value: .constant(1.0), in: 0.6...1.4)
                        .frame(width: 140)
                }
            } else {
                HStack(spacing: 8) {
                    Text("Speed")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Slider(value: $speed, in: 10...120)
                        .frame(width: 140)
                    Text("\(Int(speed))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, alignment: .trailing)
                }
            }
            
            Spacer(minLength: 8)
            
            // Right cluster: Visibility + Compact + Pass-through
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.fill")
                        .foregroundColor(.white.opacity(0.9))
                    Slider(value: $overlayOpacity, in: 0.3...1.0)
                        .frame(width: 120)
                }
                
                Toggle(isOn: $compactMode) {
                    Text("Compact")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .toggleStyle(.switch)
                
                Toggle(isOn: Binding(get: { !localPassThrough }, set: { newValue in
                    localPassThrough = !newValue
                    onPassThroughChanged(localPassThrough)
                })) {
                    Text("Interact")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .toggleStyle(.switch)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
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
    
    // MARK: - Speech Sync Functions
    
    private func startSpeechSync() {
        if speechManager.isAuthorized {
            do {
                try speechManager.startListening()
            } catch {
                print("Failed to start speech recognition: \(error)")
                // Fallback to manual scrolling
                startScrolling()
            }
        } else {
            // Request permission and fallback to manual scrolling
            startScrolling()
        }
    }
    
    private func stopSpeechSync() {
        speechManager.stopListening()
    }
    
    private func updateScrollPosition(phrase: String) {
        guard let position = textMatcher.findPosition(for: phrase) else { return }
        
        let maxOffset = contentHeight - containerHeight
        guard maxOffset > 0 else { return }
        
        let percentage = Double(position.characterOffset) / Double(max(text.count, 1))
        let targetOffset = contentHeight * percentage
        
        withAnimation(.easeOut(duration: 0.3)) {
            offset = max(0, min(targetOffset, maxOffset))
        }
        
        if settings.speechHighlightPhrase {
            highlightCurrentPhrase(at: position)
        }
    }
    
    private func highlightCurrentPhrase(at position: TextPosition) {
        guard position.characterOffset < text.count else { return }
        
        let startIndex = text.index(text.startIndex, offsetBy: position.characterOffset)
        
        let wordsAfterPhrase = max(0, position.matchedWordCount - 1)
        let bufferWords = 2
        let extraWords = wordsAfterPhrase + bufferWords
        let charCount = max(textMatcher.characterLength(for: position.wordIndex, count: extraWords), 15)
        
        let remainingLength = text.count - position.characterOffset
        let highlightLength = min(charCount, remainingLength)
        let endIndex = text.index(startIndex, offsetBy: highlightLength)
        
        highlightedRange = startIndex..<endIndex
    }
}

// MARK: - Highlighted Text View

private struct HighlightedText: View {
    let text: String
    let highlightRange: Range<String.Index>
    
    private var attributedString: AttributedString {
        var attributed = AttributedString(text)
        let nsRange = NSRange(highlightRange, in: text)
        if let range = Range(nsRange, in: attributed) {
            attributed[range].foregroundColor = .green.opacity(0.65)
        }
        return attributed
    }
    
    var body: some View {
        Text(attributedString)
            .multilineTextAlignment(.center)
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

struct VisualEffectView: NSViewRepresentable {
    enum Material {
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
            // Legacy aliases mapped to non-deprecated semantic materials.
            case .appearanceBased: return .contentBackground
            case .light: return .underWindowBackground
            case .dark: return .hudWindow
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

    enum BlendingMode {
        case behindWindow
        case withinWindow

        var nsBlendingMode: NSVisualEffectView.BlendingMode {
            switch self {
            case .behindWindow: return .behindWindow
            case .withinWindow: return .withinWindow
            }
        }
    }

    var material: Material = .contentBackground
    var blendingMode: BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    init(material: Material = .contentBackground, blendingMode: BlendingMode = .withinWindow, state: NSVisualEffectView.State = .followsWindowActiveState) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material.nsMaterial
        view.blendingMode = blendingMode.nsBlendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material.nsMaterial
        nsView.blendingMode = blendingMode.nsBlendingMode
        nsView.state = state
    }
}
