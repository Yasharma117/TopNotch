import AppKit
import SwiftUI
import Combine
import Speech

// MARK: - NonActivatingPanel

/// A borderless NSPanel that can become key (to receive keyboard events) but
/// never becomes the main window, so it never steals focus from user apps.
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - ManagedHostingView

/// NSHostingView subclass that prevents SwiftUI from ever calling setFrame on
/// the window. The default NSHostingView implementation calls
/// updateAnimatedWindowSize() inside windowDidLayout, which calls setFrame,
/// which triggers another layout pass — creating an infinite loop that crashes
/// with "The window has been marked as needing another Layout Window pass".
///
/// Two overrides break this loop:
///   1. intrinsicContentSize → noIntrinsicMetric: AppKit never sizes the window
///      to fit a "natural" content size.
///   2. sizingOptions = []: SwiftUI's per-animation-frame window resize is
///      disabled entirely.
///
/// Note: intentionally NOT generic. A generic `NSHostingView` subclass triggers
/// a Swift optimizer crash (EarlyPerfInliner on the generated generic `deinit`)
/// under `-O`/Release. It's only ever instantiated with `NotchContentView`, so
/// hardcoding the content type sidesteps the compiler bug while keeping Release
/// optimizations enabled.
@MainActor
private final class ManagedHostingView: NSHostingView<NotchContentView> {
    required init(rootView: NotchContentView) {
        super.init(rootView: rootView)
        if #available(macOS 13.0, *) {
            sizingOptions = []
        }
    }

    @MainActor required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

// MARK: - ScrollAnimationState

/// Drives the scroll offset at up to 60Hz without involving SwiftUI's reactive
/// system. The offset is applied to an NSView layer transform from the timer
/// callback, so SwiftUI never re-evaluates any view body for scroll updates.
@MainActor
final class ScrollAnimationState: ObservableObject {
    @Published var highlightedRange: Range<String.Index>?

    /// The display offset that SwiftUI reads for `.offset(y:)`.
    /// Updated by the lerp timer at 60Hz. This IS @Published so SwiftUI
    /// can apply it, but ScrollAnimationState is a SEPARATE ObservableObject
    /// from NotchViewModel — only the scroll container re-evaluates, not
    /// the entire NotchContentView.
    @Published var displayOffset: CGFloat = 0

    /// Internal scroll offset used for calculations. Mirrors displayOffset
    /// but is NOT @Published to avoid double-triggering.
    var scrollOffset: CGFloat = 0

    var contentHeight: CGFloat = 0
    var containerHeight: CGFloat = 0
    var targetScrollOffset: CGFloat = 0
    var scrollVelocity: CGFloat = 0
    var lastForwardScrollTime: Date = .distantPast
    var lastSpeechActivityTime: Date = .distantPast
    private var lerpTimer: AnyCancellable?

    // MARK: - Lerp Timer (smooth scroll interpolation)

    func startLerpTimer() {
        guard lerpTimer == nil else { return }
        let stiffness: CGFloat = 0.03
        let damping: CGFloat = 0.82
        lerpTimer = Timer.publish(every: 1 / 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let maxOffset = max(0, self.contentHeight - self.containerHeight)
                self.targetScrollOffset = min(self.targetScrollOffset, maxOffset)
                let diff = self.targetScrollOffset - self.scrollOffset
                self.scrollVelocity = self.scrollVelocity * damping + diff * stiffness
                if abs(diff) < 0.5 && abs(self.scrollVelocity) < 0.1 {
                    self.scrollOffset = self.targetScrollOffset
                    self.scrollVelocity = 0
                    self.displayOffset = self.scrollOffset
                    self.stopLerpTimer()
                } else {
                    self.scrollOffset += self.scrollVelocity
                    self.displayOffset = self.scrollOffset
                }
            }
    }

    func stopLerpTimer() {
        lerpTimer?.cancel()
        lerpTimer = nil
    }

    func reset() {
        scrollOffset = 0
        targetScrollOffset = 0
        scrollVelocity = 0
        displayOffset = 0
        highlightedRange = nil
        lastForwardScrollTime = .distantPast
        lastSpeechActivityTime = .distantPast
    }
}

// MARK: - NotchViewModel

@MainActor
final class NotchViewModel: ObservableObject {
    // Layout
    @Published var isExpanded = false
    @Published var isHovering = false
    @Published var panelWidth: Double = 420 {
        didSet { onExpansionChanged?() }
    }
    @Published var visibleLines: Double = 5 {
        didSet { onExpansionChanged?() }
    }

    /// Drives the NSWindow frame size — set BEFORE isExpanded to prevent content overflow.
    var targetExpanded = false

    // Recording state
    @Published var isRecording = false
    @Published var showCountdown = false
    @Published var countdownValue = 3
    @Published var outputURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Recording.m4a")
    }()

    // Teleprompter scroll state (active during recording)
    @Published var isScrolling = false

    /// Scroll animation lives in a separate ObservableObject so that 60Hz offset
    /// changes don't trigger re-evaluation of the entire NotchContentView body.
    let scrollState = ScrollAnimationState()

    // Divider positions for section-pause detection (non-published, only used by timer)
    var dividerPositions: [CGFloat] = []

    // Voice-sync state
    @Published var isTextHovered: Bool = false
    @Published var isVoiceTesting = false
    @Published var isSettingsPresented = false

    // Inline error/status messages
    @Published var statusMessage: StatusMessage?

    // Section parsing & time estimation
    @Published var parsedScript: ParsedScript = .empty
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var currentSectionIndex: Int = -1
    @Published var sectionPauseActive: Bool = false
    @Published var sectionPauseCountdown: Int = 0
    private var countdownTimer: AnyCancellable?
    private var sectionPauseTimer: AnyCancellable?

    // Text arrangement undo
    @Published var preArrangeText: String?
    var canUndoArrangeText: Bool { preArrangeText != nil && !isRecording }
    private var isArranging = false

    var onExpansionChanged: (() -> Void)?

    let captureController = CaptureController()
    let settings = SettingsManager.shared
    let speechManager = SpeechRecognitionManager()
    let textMatcher = TeleprompterTextMatcher()

    private var collapseWorkItem: DispatchWorkItem?
    private var speechCancellable: AnyCancellable?
    private var textCancellable: AnyCancellable?
    private var speechRestartCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    // Panel geometry
    static let collapsedWidth: CGFloat = NotchChromeMetrics.notchWidth
    static let collapsedHeight: CGFloat = NotchChromeMetrics.notchHeight
    static let lineSpacing: CGFloat = 1.55

    var fontSize: CGFloat { CGFloat(settings.teleprompterFontSize) }

    var actualExpandedHeight: CGFloat {
        let indicatorH = NotchChromeMetrics.notchHeight
        let textTopPad: CGFloat = 12
        let textH = visibleLines * fontSize * Self.lineSpacing
        let timeH: CGFloat = parsedScript.totalWords > 0 ? 20 : 0
        let textBottomPad = NotchChromeMetrics.contentInsetBottom
        let statusH: CGFloat = (statusMessage != nil || canUndoArrangeText || shouldShowArrangeTextBanner) ? 36 : 0
        return indicatorH + textTopPad + textH + timeH + textBottomPad + statusH + 2 // +2 safety buffer
    }

    // MARK: - Init

    init() {
        setupHotkeys()

        if !settings.lastOutputPath.isEmpty {
            outputURL = URL(fileURLWithPath: settings.lastOutputPath)
        }

        // Set initial script text in matcher
        textMatcher.setText(settings.teleprompterText)
        speechManager.setLocale(settings.speechLocale)

        // Parse initial text
        parsedScript = SectionParser.parse(settings.teleprompterText)

        // Observe text changes to keep matcher in sync and reset scroll
        textCancellable = settings.$teleprompterText
            .dropFirst()
            .sink { [weak self] newText in
                guard let self else { return }
                self.textMatcher.setText(newText)
                self.parsedScript = SectionParser.parse(newText)
                self.scrollState.scrollOffset = 0
                self.scrollState.targetScrollOffset = 0
                self.scrollState.displayOffset = 0
                self.scrollState.highlightedRange = nil

                // Skip banner/undo state changes when the text change was
                // triggered by arrangeText() — otherwise the sink clears
                // preArrangeText before the view ever renders the undo banner.
                if !self.isArranging {
                    if !SectionParser.containsSectionBreaks(newText) {
                        self.settings.arrangeTextBannerDismissed = false
                    }
                    self.preArrangeText = nil
                }
            }

        // Voice-sync pipeline: spoken phrase → find position → smooth scroll.
        // Throttle (not debounce) so the highlight tracks speech continuously
        // instead of only catching up when the speaker pauses. Jitter is absorbed
        // downstream by the forward-only guards below and the matcher's hysteresis.
        speechCancellable = speechManager.$currentPhrase
            .filter { !$0.isEmpty }
            .throttle(for: .milliseconds(120), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] phrase in
                guard let self, self.settings.speechSyncEnabled,
                      self.isScrolling, !self.isTextHovered else { return }

                self.scrollState.lastSpeechActivityTime = Date()

                if let position = self.textMatcher.findPosition(for: phrase) {
                    let wordPercentage = Double(position.wordIndex) / Double(max(self.textMatcher.words.count, 1))
                    let maxOffset = max(0, self.scrollState.contentHeight - self.scrollState.containerHeight)
                    let newTarget = max(0, min(CGFloat(wordPercentage) * self.scrollState.contentHeight, maxOffset))

                    // Strict forward-only: only allow backward if >2s since last
                    // forward move AND distance >50px (genuine rewind, not jitter)
                    if newTarget < self.scrollState.scrollOffset {
                        let timeSinceForward = Date().timeIntervalSince(self.scrollState.lastForwardScrollTime)
                        let backwardDistance = self.scrollState.scrollOffset - newTarget
                        guard timeSinceForward > 2.0 && backwardDistance > 50 else {
                            self.updateHighlight(at: position)
                            return
                        }
                    } else {
                        self.scrollState.lastForwardScrollTime = Date()
                    }

                    self.scrollState.targetScrollOffset = newTarget
                    self.scrollState.startLerpTimer()
                    self.updateHighlight(at: position)
                }
            }

        // Auto-restart speech recognition on timeout (Apple's ~60s limit)
        speechRestartCancellable = speechManager.$isListening
            .receive(on: DispatchQueue.main)
            .sink { [weak self] listening in
                guard let self, !listening else { return }
                if self.isVoiceTesting && !self.isRecording {
                    self.isVoiceTesting = false
                    self.isScrolling = false
                    if !self.isHovering && !self.isSettingsPresented {
                        self.scheduleCollapseIfAllowed()
                    }
                    return
                }
                guard self.isRecording, self.settings.speechSyncEnabled else { return }
                // Brief delay before restarting to avoid rapid loops on real errors
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.isRecording, self.settings.speechSyncEnabled else { return }
                    do {
                        try self.speechManager.startListening()
                    } catch {
                        self.statusMessage = .error("Speech restart failed: \(error.localizedDescription)")
                    }
                }
            }
    }

    // MARK: - Hover

    func handleHover(_ hovering: Bool) {
        if hovering == isHovering { return }
        isHovering = hovering
        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        if hovering {
            expandPanel()
        } else {
            scheduleCollapseIfAllowed()
        }
    }

    // MARK: - Recording

    func toggleRecording() async {
        if isRecording { await stopRecording() }
        else { await startRecording() }
    }

    func startRecording() async {
        guard await requestCapturePermissionsIfNeeded() else { return }

        if settings.speechSyncEnabled {
            guard await prepareSpeechRecognition() else { return }
        }

        // Run countdown if configured
        if settings.countdownDuration > 0 {
            showCountdown = true
            countdownValue = settings.countdownDuration
            for tick in stride(from: settings.countdownDuration, through: 1, by: -1) {
                countdownValue = tick
                NSSound(named: "Tink")?.play()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            showCountdown = false
        }

        do {
            try await captureController.startCapture(outputURL: outputURL)
            isRecording = true
            isVoiceTesting = false
            scrollState.reset()
            currentSectionIndex = -1
            sectionPauseActive = false
            textMatcher.reset()
            expandPanel()
            onExpansionChanged?()  // Recalculate height for speed row

            // Start time countdown
            estimatedTimeRemaining = parsedScript.estimatedDuration()
            startCountdownTimer()

            if settings.teleprompterEnabled {
                isScrolling = true
                if settings.speechSyncEnabled {
                    do {
                        try speechManager.startListening()
                    } catch {
                        statusMessage = .error("Voice sync failed to start: \(error.localizedDescription)")
                    }
                }
            }
            NSSound(named: "Hero")?.play()
        } catch {
            showCountdown = false
            statusMessage = .error("Start failed: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        isScrolling = false
        isVoiceTesting = false
        sectionPauseActive = false
        stopCountdownTimer()
        stopSectionPauseTimer()
        speechManager.stopListening()
        speechManager.reset()
        await captureController.stopCapture()
        isRecording = false
        onExpansionChanged?()  // Recalculate height (speed row removed)

        if !isHovering && !isSettingsPresented {
            scheduleCollapseIfAllowed()
        }
    }

    // MARK: - Scroll control (for teleprompter during recording)

    func resetScroll() {
        scrollState.reset()
    }

    // MARK: - Countdown Timer

    private func startCountdownTimer() {
        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isRecording else { return }
                // Pause countdown when not actively progressing:
                // - Classic mode: paused on hover or at a section break
                // - Voice mode: paused when no speech detected in last 1.5s
                if self.isTextHovered || self.sectionPauseActive { return }
                if self.settings.speechSyncEnabled {
                    let silenceDuration = Date().timeIntervalSince(self.scrollState.lastSpeechActivityTime)
                    if silenceDuration > 1.5 { return }
                }
                self.estimatedTimeRemaining = max(0, self.estimatedTimeRemaining - 1)
            }
    }

    private func stopCountdownTimer() {
        countdownTimer?.cancel()
        countdownTimer = nil
    }

    // MARK: - Section Pause (Classic auto-scroll mode)

    /// Called from the scroll timer to check if we've crossed into a section break.
    /// Returns true if scroll should be paused.
    func checkSectionPause(at scrollY: CGFloat, dividerPositions: [CGFloat]) -> Bool {
        guard !sectionPauseActive, !settings.speechSyncEnabled else { return sectionPauseActive }

        // Check if we just crossed a divider position
        for (index, dividerY) in dividerPositions.enumerated() {
            if index <= currentSectionIndex { continue }
            if scrollY >= dividerY {
                // Crossed into next section — start pause
                currentSectionIndex = index
                let pauseDuration = parsedScript.sections[safe: index]?.pauseAfter ?? SectionParser.defaultPauseDuration
                startSectionPause(duration: Int(pauseDuration))
                return true
            }
        }
        return false
    }

    private func startSectionPause(duration: Int) {
        sectionPauseActive = true
        sectionPauseCountdown = duration
        sectionPauseTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.sectionPauseCountdown -= 1
                if self.sectionPauseCountdown <= 0 {
                    self.stopSectionPauseTimer()
                    self.sectionPauseActive = false
                }
            }
    }

    private func stopSectionPauseTimer() {
        sectionPauseTimer?.cancel()
        sectionPauseTimer = nil
    }

    // MARK: - Highlight

    private func updateHighlight(at position: TextPosition) {
        let text = settings.teleprompterText
        guard position.characterOffset < text.count else {
            scrollState.highlightedRange = nil
            return
        }
        let startIndex = text.index(text.startIndex, offsetBy: position.characterOffset)

        let wordsAfterPhrase = max(0, position.matchedWordCount - 1)
        let bufferWords = 2
        let extraWords = wordsAfterPhrase + bufferWords
        var charCount = 0
        var idx = position.wordIndex
        for _ in 0..<extraWords {
            guard idx < textMatcher.words.count else { break }
            charCount += textMatcher.words[idx].count + 1
            idx += 1
        }
        charCount = max(charCount, 15)

        let remainingLength = text.count - position.characterOffset
        let highlightLength = min(charCount, remainingLength)
        let endIndex = text.index(startIndex, offsetBy: highlightLength)
        scrollState.highlightedRange = startIndex..<endIndex
    }

    // MARK: - Testing / interaction helpers

    // MARK: - Text Arrangement

    func arrangeText() {
        preArrangeText = settings.teleprompterText
        let arranged = TextArrangementEngine.arrange(
            settings.teleprompterText,
            speed: settings.teleprompterSpeed
        )
        isArranging = true
        settings.teleprompterText = arranged
        isArranging = false
        settings.arrangeTextBannerDismissed = true
    }

    func undoArrangeText() {
        guard let previous = preArrangeText else { return }
        settings.teleprompterText = previous
        preArrangeText = nil
        // Re-show the arrange banner so the user can try again
        settings.arrangeTextBannerDismissed = false
    }

    func setSettingsPresented(_ presented: Bool) {
        if isSettingsPresented == presented { return }
        isSettingsPresented = presented
        if presented {
            expandPanel()
        } else if !isHovering {
            scheduleCollapseIfAllowed()
        }
    }

    func toggleVoiceTest() async {
        if isVoiceTesting {
            stopVoiceTest()
            return
        }
        guard settings.speechSyncEnabled else {
            statusMessage = .error("Enable Voice mode first")
            return
        }
        guard await prepareSpeechRecognition() else { return }

        speechManager.reset()
        textMatcher.reset()
        scrollState.reset()
        isVoiceTesting = true
        isScrolling = true
        expandPanel()

        do {
            try speechManager.startListening()
        } catch {
            isVoiceTesting = false
            isScrolling = false
            statusMessage = .error("Voice test failed: \(error.localizedDescription)")
        }
    }

    func stopVoiceTest() {
        isVoiceTesting = false
        isScrolling = false
        speechManager.stopListening()
        if !isHovering && !isSettingsPresented && !isRecording {
            scheduleCollapseIfAllowed()
        }
    }

    // MARK: - Private helpers

    private var shouldRemainExpanded: Bool {
        isHovering || isSettingsPresented || isVoiceTesting || isRecording
    }

    var shouldShowArrangeTextBanner: Bool {
        !settings.arrangeTextBannerDismissed
            && !isRecording
            && parsedScript.totalWords >= 80
            && !SectionParser.containsSectionBreaks(settings.teleprompterText)
    }

    private func expandPanel() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if !targetExpanded {
            targetExpanded = true
            onExpansionChanged?()  // Resize window FIRST so content won't overflow
        }
        // Do NOT use withAnimation here. withAnimation drives SwiftUI's
        // updateAnimatedWindowSize on every animation frame, which calls setFrame
        // on the window during a layout pass → infinite layout loop → crash.
        // Instead, animations are declared with .animation(_:value:) in the view.
        isExpanded = true
    }

    private func scheduleCollapseIfAllowed() {
        guard !shouldRemainExpanded else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.shouldRemainExpanded else { return }
            self.isExpanded = false
            // Start shrinking window while content is still fading — the animated
            // frame interpolation overlaps with the SwiftUI spring for a unified feel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, !self.shouldRemainExpanded else { return }
                self.targetExpanded = false
                self.onExpansionChanged?()
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func requestMicrophonePermissionIfNeeded() async -> Bool {
        switch PermissionsHelper.microphonePermissionState() {
        case .authorized:
            return true
        case .notDetermined:
            return await PermissionsHelper.requestMicrophonePermission() == .authorized
        case .denied:
            return false
        }
    }

    private func requestCapturePermissionsIfNeeded() async -> Bool {
        guard await requestMicrophonePermissionIfNeeded() else {
            statusMessage = .error("Microphone permission is required")
            return false
        }
        return true
    }

    private func prepareSpeechRecognition() async -> Bool {
        guard await requestMicrophonePermissionIfNeeded() else {
            statusMessage = .error("Microphone permission is required for voice mode")
            return false
        }
        if speechManager.isAuthorized { return true }
        let granted = await speechManager.requestAuthorization()
        if !granted {
            statusMessage = .error("Speech recognition permission is required for voice mode")
        }
        return granted
    }

    private func setupHotkeys() {
        HotkeyManager.shared.registerStartStopHotkey {
            Task { await self.toggleRecording() }
        }
        HotkeyManager.shared.registerToggleTeleprompterHotkey {
            self.settings.teleprompterEnabled.toggle()
        }
        // Shift+Arrow: speed and scroll control (active when recording)
        HotkeyManager.shared.registerSpeedDownHotkey { [weak self] in
            guard let self, self.isRecording else { return }
            self.settings.teleprompterSpeed = max(10, self.settings.teleprompterSpeed - 5)
        }
        HotkeyManager.shared.registerSpeedUpHotkey { [weak self] in
            guard let self, self.isRecording else { return }
            self.settings.teleprompterSpeed = min(120, self.settings.teleprompterSpeed + 5)
        }
        HotkeyManager.shared.registerScrollUpHotkey { [weak self] in
            guard let self, self.isRecording else { return }
            self.scrollState.scrollOffset = max(0, self.scrollState.scrollOffset - 40)
            self.scrollState.displayOffset = self.scrollState.scrollOffset
        }
        HotkeyManager.shared.registerScrollDownHotkey { [weak self] in
            guard let self, self.isRecording else { return }
            self.scrollState.scrollOffset += 40
            self.scrollState.displayOffset = self.scrollState.scrollOffset
        }
    }
}

// MARK: - Animation Constants

enum NotchAnimationConstants {
    static let springResponse: Double = 0.32
    static let springDamping: Double = 0.80
    /// Duration after which the spring is considered settled (within < 1px).
    static let settleDuration: Double = 0.50

    /// Evaluate a critically/underdamped spring at time `t`.
    /// Returns the interpolated value from `from` toward `to`.
    static func springValue(t: Double, from: Double, to: Double) -> Double {
        guard t > 0 else { return from }
        guard t < settleDuration else { return to }

        let omega_n = 2.0 * .pi / springResponse          // natural frequency
        let zeta = springDamping                            // damping ratio
        let omega_d = omega_n * sqrt(1.0 - zeta * zeta)    // damped frequency
        let decay = exp(-zeta * omega_n * t)
        let cosComp = cos(omega_d * t)
        let sinComp = (zeta * omega_n / omega_d) * sin(omega_d * t)
        let progress = 1.0 - decay * (cosComp + sinComp)
        return from + (to - from) * progress
    }
}

// MARK: - StatusMessage

struct StatusMessage: Identifiable {
    enum Kind { case error, success }
    let id = UUID()
    let kind: Kind
    let text: String

    static func error(_ text: String) -> StatusMessage { .init(kind: .error, text: text) }
    static func success(_ text: String) -> StatusMessage { .init(kind: .success, text: text) }
}

// MARK: - NotchPanelController

/// Creates and manages the non-activating notch panel. Owns the NotchViewModel
/// and synchronises the panel frame whenever expansion state or size changes.
///
/// Hover detection uses a 30Hz polling timer that checks `NSEvent.mouseLocation`
/// against the panel frame. This replaces NSTrackingArea which caused an infinite
/// hover loop: resizing the window during mouseEntered/mouseExited triggered
/// updateTrackingAreas(), which fired spurious events, re-entering handleHover().
@MainActor
final class NotchPanelController {
    let viewModel = NotchViewModel()
    private var panel: NonActivatingPanel?
    private var cancellables: Set<AnyCancellable> = []

    private var hoverTimer: DispatchSourceTimer?
    private var isPerformingLayout = false

    // Frame animation state
    private var frameAnimationTimer: DispatchSourceTimer?
    private var frameAnimationStart: CFTimeInterval = 0
    private var frameAnimationFrom: NSRect = .zero
    private var frameAnimationTo: NSRect = .zero

    init() {
        viewModel.onExpansionChanged = { [weak self] in
            self?.applyLayout()
        }
        setupPanel()
        observeViewModelChanges()
    }

    deinit {
        hoverTimer?.cancel()
        frameAnimationTimer?.cancel()
    }

    private func setupPanel() {
        let w = NotchViewModel.collapsedWidth
        let h = NotchViewModel.collapsedHeight

        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.animationBehavior = .utilityWindow

        let content = NotchContentView(model: viewModel)
        let hosting = ManagedHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: w, height: h)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        applyLayout()
        panel.orderFront(nil)
        startHoverPolling()
    }

    private func observeViewModelChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyLayout() }
            .store(in: &cancellables)
    }

    // MARK: - Hover polling

    /// Polls mouse position at 30Hz to detect hover enter/exit.
    /// This is completely decoupled from window frame changes, eliminating
    /// the re-entrant NSTrackingArea loop that caused the crash.
    private func startHoverPolling() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in
            self?.evaluateMousePosition()
        }
        timer.resume()
        hoverTimer = timer
    }

    private func evaluateMousePosition() {
        guard !isPerformingLayout, let panel = panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        let isInside = panel.frame.contains(mouseLocation)
        viewModel.handleHover(isInside)
    }

    // MARK: - Layout

    private func applyLayout() {
        guard let screen = NSScreen.main, let panel = panel else { return }

        let frame = panelFrame(for: screen)
        let currentFrame = panel.frame

        let epsilon: CGFloat = 0.5
        if abs(currentFrame.origin.x - frame.origin.x) < epsilon &&
           abs(currentFrame.origin.y - frame.origin.y) < epsilon &&
           abs(currentFrame.size.width - frame.size.width) < epsilon &&
           abs(currentFrame.size.height - frame.size.height) < epsilon { return }

        animateFrame(to: frame)
    }

    /// Animate the NSWindow frame using a timer-driven spring interpolation
    /// that matches the SwiftUI `.spring(response:dampingFraction:)` curve.
    /// This keeps the window resize in sync with content transitions without
    /// triggering the NSHostingView infinite layout loop.
    private func animateFrame(to target: NSRect) {
        guard let panel = panel else { return }

        // If an animation is running, start from the current interpolated position
        let from = panel.frame

        // Cancel any in-progress animation
        frameAnimationTimer?.cancel()
        frameAnimationTimer = nil

        frameAnimationFrom = from
        frameAnimationTo = target
        frameAnimationStart = CACurrentMediaTime()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        // ~120Hz for smooth interpolation on ProMotion and standard displays
        timer.schedule(deadline: .now(), repeating: 1.0 / 120.0)
        timer.setEventHandler { [weak self] in
            self?.tickFrameAnimation()
        }
        timer.resume()
        frameAnimationTimer = timer
    }

    private func tickFrameAnimation() {
        guard let panel = panel else {
            frameAnimationTimer?.cancel()
            frameAnimationTimer = nil
            return
        }

        let elapsed = CACurrentMediaTime() - frameAnimationStart
        let settle = NotchAnimationConstants.settleDuration

        let x = NotchAnimationConstants.springValue(t: elapsed, from: Double(frameAnimationFrom.origin.x), to: Double(frameAnimationTo.origin.x))
        let y = NotchAnimationConstants.springValue(t: elapsed, from: Double(frameAnimationFrom.origin.y), to: Double(frameAnimationTo.origin.y))
        let w = NotchAnimationConstants.springValue(t: elapsed, from: Double(frameAnimationFrom.size.width), to: Double(frameAnimationTo.size.width))
        let h = NotchAnimationConstants.springValue(t: elapsed, from: Double(frameAnimationFrom.size.height), to: Double(frameAnimationTo.size.height))

        let interpolated = NSRect(x: x, y: y, width: w, height: h)

        isPerformingLayout = true
        panel.setFrame(interpolated, display: true)
        isPerformingLayout = false

        if elapsed >= settle {
            // Snap to final frame and stop
            isPerformingLayout = true
            panel.setFrame(frameAnimationTo, display: true)
            isPerformingLayout = false
            frameAnimationTimer?.cancel()
            frameAnimationTimer = nil
        }
    }

    private func panelFrame(for screen: NSScreen) -> NSRect {
        let expanded = viewModel.targetExpanded
        let panelWidth = expanded ? viewModel.panelWidth : Double(NotchViewModel.collapsedWidth)
        let panelHeight = expanded ? Double(viewModel.actualExpandedHeight) : Double(NotchViewModel.collapsedHeight)
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screenFrame.maxY - panelHeight
        return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }
}
