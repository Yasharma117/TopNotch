import SwiftUI
import Combine
import UniformTypeIdentifiers
import PDFKit


enum NotchChromeMetrics {
    static let notchWidth: CGFloat = 210
    static let notchHeight: CGFloat = 44
    static let shoulderDrop: CGFloat = 18
    static let emergenceRadius: CGFloat = 18
    static let outerTopRadius: CGFloat = 22
    static let bottomRadius: CGFloat = 26
    static let seamOverdraw: CGFloat = 0.75
    static let rightRailWidth: CGFloat = 40
    static let contentInsetX: CGFloat = 18
    static let contentInsetBottom: CGFloat = 14
    static let popoverWidth: CGFloat = 360
    static let popoverCornerRadius: CGFloat = 22
    static let popoverPadding: CGFloat = 20
}

// MARK: - AppColors

enum AppColors {
    // Popover surface / control fills
    static let popoverBackground    = Color(red: 0.987, green: 0.989, blue: 0.995)
    static let popoverSectionFill   = Color(red: 0.965, green: 0.969, blue: 0.978)
    static let popoverControlFill   = Color(red: 0.93,  green: 0.936, blue: 0.95)
    // Accent blues
    static let accentBlue           = Color(red: 0.26, green: 0.52, blue: 0.97)
    static let iconBlue             = Color(red: 0.28, green: 0.54, blue: 0.97)
    // Notch overlay (text on dark background)
    static let overlayCaption       = Color.white.opacity(0.35)
    static let overlaySecondary     = Color.white.opacity(0.55)
    static let overlayMuted         = Color.white.opacity(0.72)
    static let overlayPrimary       = Color.white.opacity(0.94)
}

// MARK: - NotchBoxShape

/// Internal rather than private so the geometry can be regression-tested.
struct NotchBoxShape: Shape {
    var bottomRadius: CGFloat
    var notchWidth: CGFloat = NotchChromeMetrics.notchWidth
    var shoulderDrop: CGFloat = NotchChromeMetrics.shoulderDrop
    var outerTopRadius: CGFloat = NotchChromeMetrics.outerTopRadius
    var emergenceRadius: CGFloat = NotchChromeMetrics.emergenceRadius

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY
        let midX = rect.midX

        // Blend smoothly between collapsed (simple rect) and expanded (shouldered
        // notch) over a small width range so the shape doesn't pop during animated
        // frame transitions.
        let blendStart = notchWidth + 4
        let blendEnd = notchWidth + 40  // fully shouldered 36pt past threshold
        let blend = min(max((rect.width - blendStart) / (blendEnd - blendStart), 0), 1)

        // Effective shoulder drop: 0 when collapsed → full shoulderDrop when expanded
        let effectiveDrop = shoulderDrop * blend
        let effectiveEmergence = emergenceRadius * blend
        let effectiveOuterTop = outerTopRadius * blend

        if blend <= 0 {
            // Fully collapsed — simple rounded rect
            p.move(to: CGPoint(x: minX, y: minY))
            p.addLine(to: CGPoint(x: maxX, y: minY))
            p.addLine(to: CGPoint(x: maxX, y: maxY - bottomRadius))
            p.addQuadCurve(to: CGPoint(x: maxX - bottomRadius, y: maxY), control: CGPoint(x: maxX, y: maxY))
            p.addLine(to: CGPoint(x: minX + bottomRadius, y: maxY))
            p.addQuadCurve(to: CGPoint(x: minX, y: maxY - bottomRadius), control: CGPoint(x: minX, y: maxY))
            p.closeSubpath()
            return p
        }

        let notchLeft = midX - notchWidth / 2
        let notchRight = midX + notchWidth / 2
        let shoulderY = minY + effectiveDrop
        let rightShoulderEnd = CGPoint(x: notchRight + effectiveEmergence * 1.6, y: shoulderY)
        let leftShoulderStart = CGPoint(x: notchLeft - effectiveEmergence * 1.6, y: shoulderY)
        let topShelfMaxX = max(rightShoulderEnd.x, maxX - effectiveOuterTop)
        let topShelfMinX = min(leftShoulderStart.x, minX + effectiveOuterTop)

        p.move(to: CGPoint(x: notchLeft, y: minY))
        p.addLine(to: CGPoint(x: notchRight, y: minY))

        p.addCurve(
            to: rightShoulderEnd,
            control1: CGPoint(x: notchRight + effectiveEmergence * 0.55, y: minY),
            control2: CGPoint(x: notchRight + effectiveEmergence * 1.05, y: shoulderY)
        )
        p.addLine(to: CGPoint(x: topShelfMaxX, y: shoulderY))
        p.addQuadCurve(
            to: CGPoint(x: maxX, y: shoulderY + effectiveOuterTop),
            control: CGPoint(x: maxX, y: shoulderY)
        )
        p.addLine(to: CGPoint(x: maxX, y: maxY - bottomRadius))
        p.addQuadCurve(to: CGPoint(x: maxX - bottomRadius, y: maxY), control: CGPoint(x: maxX, y: maxY))
        p.addLine(to: CGPoint(x: minX + bottomRadius, y: maxY))
        p.addQuadCurve(to: CGPoint(x: minX, y: maxY - bottomRadius), control: CGPoint(x: minX, y: maxY))
        p.addLine(to: CGPoint(x: minX, y: shoulderY + effectiveOuterTop))
        p.addQuadCurve(
            to: CGPoint(x: minX + effectiveOuterTop, y: shoulderY),
            control: CGPoint(x: minX, y: shoulderY)
        )
        p.addLine(to: CGPoint(x: topShelfMinX, y: shoulderY))
        // Land on the shoulder before curving up to the tab. Without this the curve
        // starts at topShelfMinX — which is minX + outerTop for any panel wider than
        // ~338 — and the left emergence stretches across the whole shelf while the
        // right stays a tight 1.6 * emergence curve, leaving the notch visibly lopsided.
        p.addLine(to: leftShoulderStart)
        p.addCurve(
            to: CGPoint(x: notchLeft, y: minY),
            control1: CGPoint(x: notchLeft - effectiveEmergence * 1.05, y: shoulderY),
            control2: CGPoint(x: notchLeft - effectiveEmergence * 0.55, y: minY)
        )
        p.closeSubpath()
        return p
    }
}

private struct NotchScriptContent {
    let title: String?
    let body: String

    init(text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let (extractedTitle, extractedBody) = SectionParser.extractTitleAndBody(from: normalized)
        title = extractedTitle
        body = extractedBody
    }
}

private struct PopoverCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
            )
    }
}

private extension View {
    func popoverControlCard() -> some View {
        modifier(PopoverCardModifier())
    }
}

// MARK: - NotchContentView

struct NotchContentView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var settings = SettingsManager.shared

    @State private var resizeStartWidth: Double?
    @State private var scrollTimer: AnyCancellable?
    @State private var isDropTargeted = false
    @State private var showSettings = false
    @State private var hoveredRailControl: String?

    private var fontSize: CGFloat { model.fontSize }
    private var textMultilineAlignment: TextAlignment {
        model.settings.teleprompterTextAlignment == "center" ? .center : .leading
    }

    private var textFrameAlignment: Alignment {
        textMultilineAlignment == .center ? .center : .leading
    }

    private var bodyHeight: CGFloat {
        model.visibleLines * fontSize * NotchViewModel.lineSpacing
    }

    private var chromeShape: NotchBoxShape {
        NotchBoxShape(bottomRadius: NotchChromeMetrics.bottomRadius,
                      notchWidth: NotchChromeMetrics.notchWidth,
                      shoulderDrop: NotchChromeMetrics.shoulderDrop,
                      outerTopRadius: NotchChromeMetrics.outerTopRadius,
                      emergenceRadius: NotchChromeMetrics.emergenceRadius)
    }

    private var seamOverdrawHeight: CGFloat {
        NotchChromeMetrics.shoulderDrop + NotchChromeMetrics.outerTopRadius + 4
    }

    private var speechTestPreviewText: String {
        let transcript = model.speechManager.currentPhrase.isEmpty
            ? model.speechManager.recognizedText
            : model.speechManager.currentPhrase
        return transcript.isEmpty
            ? "Speak a few words to verify permission, recognition, and live phrase updates."
            : transcript
    }

    private var popoverPrimaryColor: Color { Color.black.opacity(0.82) }
    private var popoverSecondaryColor: Color { Color.black.opacity(0.56) }
    private var popoverMutedColor: Color { Color.black.opacity(0.42) }
    private var popoverSectionFill: Color { AppColors.popoverSectionFill }
    private var popoverControlFill: Color { AppColors.popoverControlFill }

    var body: some View {
        ZStack {
            mainContent
            if model.showCountdown { countdownOverlay }
        }
        .onChange(of: model.isScrolling) { active in
            if active && !model.settings.speechSyncEnabled { startAutoScroll() }
            else { stopAutoScroll() }
        }
        .onChange(of: model.settings.speechSyncEnabled) { voiceMode in
            if !voiceMode && model.isVoiceTesting {
                model.stopVoiceTest()
            }
            if model.isScrolling {
                if voiceMode { stopAutoScroll() } else { startAutoScroll() }
            }
        }
        .onChange(of: showSettings) { presented in
            model.setSettingsPresented(presented)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleScriptDrop(providers: providers)
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            collapsedIndicator

            if model.isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    textColumn
                        .padding(.leading, NotchChromeMetrics.contentInsetX)
                        .padding(.bottom, NotchChromeMetrics.contentInsetBottom)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    iconStrip
                        .padding(.trailing, 10)
                        .padding(.bottom, NotchChromeMetrics.contentInsetBottom)
                        .transition(.opacity)
                }

                if model.statusMessage != nil {
                    statusBanner
                        .padding(.horizontal, NotchChromeMetrics.contentInsetX)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                } else if model.canUndoArrangeText {
                    undoArrangeBanner
                        .padding(.horizontal, NotchChromeMetrics.contentInsetX)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                } else if model.shouldShowArrangeTextBanner {
                    arrangeTextBanner
                        .padding(.horizontal, NotchChromeMetrics.contentInsetX)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }
        }
        // View-level animation drives expand/collapse transitions.
        // withAnimation is intentionally NOT used in the view model because it
        // causes NSHostingView.updateAnimatedWindowSize to call setFrame on every
        // animation frame during a layout pass → infinite layout loop → crash.
        .animation(.spring(response: NotchAnimationConstants.springResponse,
                          dampingFraction: NotchAnimationConstants.springDamping),
                   value: model.isExpanded)
        .background(
            chromeShape
                .fill(Color.black)
        )
        .overlay {
            if isDropTargeted {
                chromeShape
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(AppColors.overlayCaption)
                    .overlay {
                        Text("Drop script here")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
            }
        }
        .clipShape(chromeShape)
        .overlay {
            if !model.isExpanded {
                ZStack {
                    chromeShape
                        .stroke(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.12), .white.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 3
                        )
                    chromeShape
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 3
                        )
                    chromeShape
                        .stroke(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.25)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 3
                        )
                }
                .blur(radius: 2)
                .clipShape(chromeShape)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            chromeShape
                .fill(Color.black)
                .offset(y: -NotchChromeMetrics.seamOverdraw)
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(height: seamOverdrawHeight)
                }
                .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) {
            if model.isExpanded { invisibleWidthHandle(side: .left) }
        }
        .overlay(alignment: .trailing) {
            if model.isExpanded { invisibleWidthHandle(side: .right) }
        }
    }

    // MARK: - Collapsed indicator

    private var collapsedIndicator: some View {
        ZStack {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                recordDot
                    .frame(width: NotchChromeMetrics.notchWidth, height: NotchChromeMetrics.notchHeight)
                Spacer(minLength: 0)
            }

            if !model.isExpanded {
                Text("hover to expand")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColors.overlayMuted)
            }
        }
    }

    @ViewBuilder
    private var recordDot: some View {
        ZStack {
            if model.isRecording {
                Circle()
                    .fill(Color.red.opacity(0.28))
                    .frame(width: 14, height: 14)
                    .blur(radius: 4)
                    .scaleEffect(model.isRecording ? 1.35 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: model.isRecording)
            }
            Circle()
                .fill(model.isRecording ? Color.red : Color.white.opacity(0.26))
                .frame(width: 7, height: 7)
        }
    }

    // MARK: - Text column

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isScrolling {
                TeleprompterReadingView(
                    scrollState: model.scrollState,
                    model: model,
                    fontSize: fontSize,
                    bodyHeight: bodyHeight,
                    textMultilineAlignment: textMultilineAlignment,
                    textFrameAlignment: textFrameAlignment
                )
            } else {
                TextEditor(text: Binding(
                    get: { model.settings.teleprompterText },
                    set: { model.settings.teleprompterText = $0 }
                ))
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.overlayPrimary)
                .tint(Color.white.opacity(0.9))
                .scrollContentBackground(.hidden)
                .frame(height: bodyHeight)
                .multilineTextAlignment(textMultilineAlignment)
            }

            // Time estimate / countdown
            if model.parsedScript.totalWords > 0 {
                timeEstimateLabel
                    .padding(.top, 4)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Time estimate label

    private var timeEstimateLabel: some View {
        let text: String
        if model.isRecording {
            text = "\(ParsedScript.formatRemaining(model.estimatedTimeRemaining)) remaining"
        } else {
            text = ParsedScript.formatDuration(model.parsedScript.estimatedDuration())
        }

        return Text(text)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(AppColors.overlaySecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Reading view is now a separate struct (TeleprompterReadingView) to avoid
    // 60Hz full-body re-evaluation of this 1200-line view.

    // MARK: - Right icon strip

    private var iconStrip: some View {
        VStack(spacing: 10) {
            railButton(
                id: "record",
                icon: model.isRecording ? "stop.fill" : "play.fill",
                active: model.isRecording,
                emphasize: true
            ) {
                Task { await model.toggleRecording() }
            }
            .help(model.isRecording ? "Stop Recording" : "Start Recording")

            railButton(
                id: "settings",
                icon: "gearshape",
                active: showSettings
            ) {
                showSettings.toggle()
            }
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                settingsPopover
            }
            .help("Settings")

            if model.isRecording {
                railButton(id: "reset", icon: "arrow.counterclockwise") {
                    model.resetScroll()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .help("Reset Scroll")
            }

            Spacer(minLength: 0)
        }
        .frame(width: NotchChromeMetrics.rightRailWidth)
        .padding(.top, 10)
    }

    private func railButton(
        id: String,
        icon: String,
        active: Bool = false,
        emphasize: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredRailControl == id
        let backgroundOpacity = active ? (emphasize ? 0.14 : 0.10) : (isHovered ? 0.07 : 0.0)

        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    emphasize && active
                    ? Color.red.opacity(0.92)
                    : Color.white.opacity(active ? 0.95 : 0.72)
                )
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(backgroundOpacity))
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            hoveredRailControl = hovering ? id : (hoveredRailControl == id ? nil : hoveredRailControl)
        }
    }

    // MARK: - Settings popover

    private var settingsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsTeleprompterSection
                settingsAppearanceSection
                settingsGeneralSection
                settingsShortcutsSection
            }
            .padding(NotchChromeMetrics.popoverPadding)
        }
        .frame(width: NotchChromeMetrics.popoverWidth)
        .background(
            RoundedRectangle(cornerRadius: NotchChromeMetrics.popoverCornerRadius, style: .continuous)
                .fill(AppColors.popoverBackground)
                .shadow(color: Color.black.opacity(0.16), radius: 20, y: 10)
        )
        .padding(10)
        .colorScheme(.light)
        .tint(AppColors.accentBlue)
    }

    private var settingsTeleprompterSection: some View {
        popoverSection("Teleprompter", systemImage: "text.alignleft") {
            VStack(spacing: 12) {
                HStack {
                    Text("Mode")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(popoverSecondaryColor)
                    Spacer()
                    HStack(spacing: 0) {
                        modeButton(label: "Classic", icon: "gauge.with.dots.needle.bottom.50percent",
                                   active: !model.settings.speechSyncEnabled) {
                            model.settings.speechSyncEnabled = false
                        }
                        modeButton(label: "Voice", icon: "mic.fill",
                                   active: model.settings.speechSyncEnabled) {
                            model.settings.speechSyncEnabled = true
                        }
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(popoverControlFill)
                    )
                }

                if model.settings.speechSyncEnabled {
                    HStack {
                        Text("Language")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(popoverSecondaryColor)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.settings.speechLocale },
                            set: {
                                model.settings.speechLocale = $0
                                model.speechManager.setLocale($0)
                            }
                        )) {
                            ForEach(SpeechLocale.allCases) { l in
                                Text(l.displayName).tag(l.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 178)
                        .colorScheme(.light)
                        .popoverControlCard()
                    }

                    if model.isRecording {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(model.speechManager.isListening ? Color.green : Color.black.opacity(0.18))
                                .frame(width: 7, height: 7)
                            Text(model.speechManager.isListening ? "Listening" : "Starting…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(popoverMutedColor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Voice Test")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(popoverPrimaryColor)
                                Text("Test speech sync without starting a recording.")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(popoverMutedColor)
                            }
                            Spacer()
                            Button(model.isVoiceTesting ? "Stop Test" : "Start Test") {
                                Task { await model.toggleVoiceTest() }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(model.isVoiceTesting ? Color.black.opacity(0.88) : Color.white)
                                    .shadow(color: Color.black.opacity(0.07), radius: 4, y: 2)
                            )
                            .foregroundStyle(model.isVoiceTesting ? Color.white : popoverPrimaryColor)
                        }

                        Text(speechTestPreviewText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(model.speechManager.recognizedText.isEmpty ? popoverMutedColor : popoverPrimaryColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(3)

                        HStack(spacing: 8) {
                            Circle()
                                .fill(model.speechManager.isAuthorized ? Color.green.opacity(0.85) : Color.yellow.opacity(0.85))
                                .frame(width: 7, height: 7)
                            Text(model.speechManager.isAuthorized ? "Speech permission ready" : "Speech permission will be requested on first test")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(popoverMutedColor)
                        }
                    }
                    .popoverControlCard()
                } else {
                    VStack(spacing: 7) {
                        HStack {
                            Text("Speed")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(popoverSecondaryColor)
                            Spacer()
                            Text("\(Int(model.settings.teleprompterSpeed))")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(popoverMutedColor)
                        }
                        Slider(
                            value: Binding(
                                get: { model.settings.teleprompterSpeed },
                                set: { model.settings.teleprompterSpeed = $0 }
                            ),
                            in: 10...120, step: 5
                        )
                        .colorScheme(.light)
                    }
                    .popoverControlCard()
                }
            }
        }
    }

    private var settingsAppearanceSection: some View {
        popoverSection("Appearance", systemImage: "paintbrush.pointed") {
            VStack(spacing: 12) {
                HStack {
                    Text("Size")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(popoverSecondaryColor)
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach([(14.0, "A", 9.0), (16.0, "A", 11.0), (20.0, "A", 13.5), (28.0, "A", 16.0)], id: \.0) { size, lbl, display in
                            Button {
                                model.settings.teleprompterFontSize = size
                                model.onExpansionChanged?()
                            } label: {
                                Text(lbl)
                                    .font(.system(size: display, weight: .semibold))
                                    .frame(width: 32, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(model.settings.teleprompterFontSize == size ? Color.white : Color.clear)
                                            .shadow(color: Color.black.opacity(model.settings.teleprompterFontSize == size ? 0.08 : 0), radius: 4, y: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(model.settings.teleprompterFontSize == size ? popoverPrimaryColor : popoverMutedColor)
                        }
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(popoverControlFill)
                    )
                }

                HStack {
                    Text("Align")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(popoverSecondaryColor)
                    Spacer()
                    HStack(spacing: 0) {
                        alignButton(icon: "text.alignleft", value: "leading")
                        alignButton(icon: "text.aligncenter", value: "center")
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(popoverControlFill)
                    )
                }

                HStack {
                    Text("Lines")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(popoverSecondaryColor)
                    Spacer()
                    Stepper("\(Int(model.visibleLines))", value: Binding(
                        get: { model.visibleLines },
                        set: { model.visibleLines = max(2, min(10, $0)) }
                    ), in: 2...10, step: 1)
                    .colorScheme(.light)
                    .frame(maxWidth: 118)
                    .popoverControlCard()
                }
            }
        }
    }

    private var settingsGeneralSection: some View {
        popoverSection("General", systemImage: "gearshape") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show in Dock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(popoverSecondaryColor)
                    Text("Keeps a Dock icon you can right-click to quit. Turn off to live only in the notch and the menu bar.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(popoverMutedColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                Toggle("", isOn: Binding(
                    get: { model.settings.showInDock },
                    set: { model.settings.showInDock = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .colorScheme(.light)
            }
            .popoverControlCard()
        }
    }

    private var settingsShortcutsSection: some View {
        popoverSection("Shortcuts", systemImage: "keyboard") {
            VStack(spacing: 10) {
                shortcutRow(keys: ["⇧", "↑"], label: "Move up")
                shortcutRow(keys: ["⇧", "↓"], label: "Move down")
                shortcutRow(keys: ["⇧", "←"], label: "Slower")
                shortcutRow(keys: ["⇧", "→"], label: "Faster")
                shortcutRow(keys: ["⌘", "⇧", "R"], label: "Start / stop")
                shortcutRow(keys: ["⌘", "⇧", "T"], label: "Toggle teleprompter")
            }
            .popoverControlCard()

            Text("Move and speed shortcuts work while the teleprompter is running.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(popoverMutedColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func shortcutRow(keys: [String], label: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(popoverSecondaryColor)
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(popoverPrimaryColor)
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(popoverControlFill)
                        )
                }
            }
        }
    }

    // MARK: - Popover helpers

    @ViewBuilder
    private func popoverSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.iconBlue)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(popoverPrimaryColor)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(popoverSectionFill)
        )
    }

    @ViewBuilder
    private func modeButton(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? Color.white : Color.clear)
                    .shadow(color: Color.black.opacity(active ? 0.07 : 0.0), radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? popoverPrimaryColor : popoverMutedColor)
    }

    @ViewBuilder
    private func alignButton(icon: String, value: String) -> some View {
        let active = model.settings.teleprompterTextAlignment == value
        Button {
            model.settings.teleprompterTextAlignment = value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 42, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(active ? Color.white : Color.clear)
                        .shadow(color: Color.black.opacity(active ? 0.07 : 0.0), radius: 4, y: 2)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? popoverPrimaryColor : popoverMutedColor)
    }

    // MARK: - Status banner

    @ViewBuilder
    private var statusBanner: some View {
        if let msg = model.statusMessage {
            HStack(spacing: 8) {
                Circle()
                    .fill(msg.kind == .error ? Color.yellow.opacity(0.85) : Color.green.opacity(0.8))
                    .frame(width: 6, height: 6)
                Text(msg.text)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColors.overlayMuted)
                    .lineLimit(1)
                Spacer()
                Button { model.statusMessage = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.32))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Arrange text banner

    private var arrangeTextBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.blue.opacity(0.7))
                .frame(width: 6, height: 6)
            Text("Add section breaks for paced reading")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.overlayMuted)
                .lineLimit(1)
            Spacer()
            Button("Arrange") {
                model.arrangeText()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.blue.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.15))
            .clipShape(Capsule())

            Button {
                model.settings.arrangeTextBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.32))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Undo arrange banner

    private var undoArrangeBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green.opacity(0.7))
                .frame(width: 6, height: 6)
            Text("Text arranged with section breaks")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.overlayMuted)
                .lineLimit(1)
            Spacer()
            Button("Undo") {
                model.undoArrangeText()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.orange.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Section divider

    private func sectionDivider(pauseDuration: TimeInterval, isPaused: Bool, countdown: Int) -> some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(Color.white.opacity(isPaused ? 0.25 : 0.12))
                .frame(height: 1)

            if isPaused {
                Text("\(countdown)s")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.5))
            } else {
                Text("· \(Int(pauseDuration))s pause ·")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.22))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Countdown overlay

    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.75)
            Text("\(model.countdownValue)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                .transition(.scale(scale: 1.3).combined(with: .opacity))
                .id(model.countdownValue)
        }
        .clipShape(chromeShape)
        .transition(.opacity)
    }

    // MARK: - Invisible width drag handles

    @ViewBuilder
    private func invisibleWidthHandle(side: WidthHandleSide) -> some View {
        Color.clear
            .frame(width: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStartWidth == nil { resizeStartWidth = model.panelWidth }
                        let direction: Double = side == .right ? 3.5 : -3.5
                        let next = max(320, min(680,
                            quantize(
                                (resizeStartWidth ?? model.panelWidth) + Double(value.translation.width) * direction,
                                step: 16
                            )
                        ))
                        if next != model.panelWidth { model.panelWidth = next }
                    }
                    .onEnded { _ in resizeStartWidth = nil }
            )
    }

    // MARK: - Auto-scroll

    private func startAutoScroll() {
        scrollTimer?.cancel()
        scrollTimer = Timer.publish(every: 1 / 60, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard !model.isTextHovered, !model.sectionPauseActive else { return }
                if model.checkSectionPause(at: model.scrollState.scrollOffset, dividerPositions: model.dividerPositions) {
                    return
                }
                let maxOffset = max(0, model.scrollState.contentHeight - model.scrollState.containerHeight)
                let increment = CGFloat(model.settings.teleprompterSpeed) / 60
                let newOffset = min(model.scrollState.scrollOffset + increment, maxOffset)
                model.scrollState.scrollOffset = newOffset
                model.scrollState.displayOffset = newOffset
                if newOffset >= maxOffset { stopAutoScroll() }
            }
    }

    private func stopAutoScroll() {
        scrollTimer?.cancel()
        scrollTimer = nil
    }

    // MARK: - Drag-and-drop handler

    private func handleScriptDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            let fileExtension = url.pathExtension.lowercased()
            guard ["txt", "md", "rtf", "pdf"].contains(fileExtension) else { return }
            
            DispatchQueue.main.async {
                do {
                    let text: String
                    if fileExtension == "pdf" {
                        guard let pdfText = self.extractTextFromPDF(at: url) else {
                            model.statusMessage = .error("Could not extract text from PDF")
                            return
                        }
                        text = pdfText
                    } else {
                        text = try String(contentsOf: url, encoding: .utf8)
                    }
                    model.settings.teleprompterText = text
                    model.statusMessage = .success("Loaded: \(url.lastPathComponent)")
                } catch {
                    model.statusMessage = .error("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return true
    }

    private func extractTextFromPDF(at url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                fullText += pageText + "\n"
            }
        }
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}


// MARK: - Helpers

private enum WidthHandleSide { case left, right }

private func quantize(_ value: Double, step: Double) -> Double {
    (value / step).rounded() * step
}

// MARK: - Divider Positions Preference

struct DividerPosition: Equatable {
    let index: Int
    let y: CGFloat
}

private struct DividerPositionsKey: PreferenceKey {
    static var defaultValue: [DividerPosition] = []
    static func reduce(value: inout [DividerPosition], nextValue: () -> [DividerPosition]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - TeleprompterReadingView

/// Pure SwiftUI reading view that observes ScrollAnimationState for 60Hz offset
/// updates. This is the ONLY view that re-evaluates when displayOffset changes,
/// keeping the 1200-line NotchContentView body out of the 60Hz hot path.
/// Reports the height of the view it's attached to (as background) via preference.
private struct HeightReaderView: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { onChange(proxy.size.height) }
                .onChange(of: proxy.size.height) { h in onChange(h) }
        }
    }
}

private struct TeleprompterReadingView: View {
    @ObservedObject var scrollState: ScrollAnimationState
    @ObservedObject var model: NotchViewModel
    let fontSize: CGFloat
    let bodyHeight: CGFloat
    let textMultilineAlignment: TextAlignment
    let textFrameAlignment: Alignment

    var body: some View {
        mainContent
            .offset(y: -scrollState.displayOffset)
            .frame(height: bodyHeight, alignment: .top)
            .clipped()
            .onAppear {
                scrollState.containerHeight = bodyHeight
            }
            .onChange(of: bodyHeight) { newH in
                scrollState.containerHeight = newH
            }
            .onPreferenceChange(DividerPositionsKey.self) { positions in
                model.dividerPositions = positions.map(\.y)
            }
            .onHover { hovering in
                model.isTextHovered = hovering
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        let sections = model.parsedScript.sections
        if sections.count > 1 {
            sectionsContent(sections: sections)
        } else {
            singleSectionContent
        }
    }

    private func sectionsContent(sections: [TeleprompterSection]) -> some View {
        VStack(alignment: textMultilineAlignment == .center ? .center : .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                sectionText(section: section, sections: sections, index: idx)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(textMultilineAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: textFrameAlignment)

                if idx < sections.count - 1 {
                    sectionDivider(index: idx, pauseDuration: section.pauseAfter)
                }
            }
        }
        .coordinateSpace(name: "scrollStack")
        .background(HeightReaderView { h in
            scrollState.contentHeight = h
        })
    }

    private func sectionText(section: TeleprompterSection, sections: [TeleprompterSection], index: Int) -> Text {
        var charOffset = 0
        for i in 0..<index {
            charOffset += sections[i].text.count
        }

        let sectionText = section.text
        let fullText = model.settings.teleprompterText
        let textLength = sectionText.count
        guard textLength > 0 else { return Text(sectionText) }

        var attr = AttributedString(sectionText)

        if let r = Range(NSRange(location: 0, length: textLength), in: attr) {
            attr[r].foregroundColor = AppColors.overlayPrimary
        }

        if model.settings.speechSyncEnabled && model.settings.speechHighlightPhrase,
           let highlightedRange = scrollState.highlightedRange,
           highlightedRange.upperBound <= fullText.endIndex {

            let sectionStart = fullText.index(fullText.startIndex, offsetBy: charOffset)
            let sectionEnd = fullText.index(sectionStart, offsetBy: sectionText.count)
            let interStart = max(sectionStart, highlightedRange.lowerBound)
            let interEnd = min(sectionEnd, highlightedRange.upperBound)

            if interStart < interEnd {
                let localStart = fullText.distance(from: sectionStart, to: interStart)
                let localEnd = fullText.distance(from: sectionStart, to: interEnd)
                if let r = Range(NSRange(location: localStart, length: localEnd - localStart), in: attr) {
                    attr[r].foregroundColor = Color.green
                }
            }
        }

        return Text(attr)
    }

    private var displayAttributedString: AttributedString {
        let text = model.settings.teleprompterText
        var attr = AttributedString(text)
        let textLength = text.count
        guard textLength > 0 else { return attr }

        if let fullRange = Range(NSRange(location: 0, length: textLength), in: attr) {
            attr[fullRange].foregroundColor = AppColors.overlayPrimary
        }

        if model.settings.speechSyncEnabled && model.settings.speechHighlightPhrase,
           let range = scrollState.highlightedRange,
           range.upperBound <= text.endIndex {
            let nsRange = NSRange(range, in: text)
            if let r = Range(nsRange, in: attr) {
                attr[r].foregroundColor = Color.green
            }
        }

        return attr
    }

    private var singleSectionContent: some View {
        Text(displayAttributedString)
            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .multilineTextAlignment(textMultilineAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: textFrameAlignment)
            .background(HeightReaderView { h in
                scrollState.contentHeight = h
            })
    }

    private func sectionDivider(index: Int, pauseDuration: TimeInterval) -> some View {
        let isPaused = model.sectionPauseActive
        let countdown = model.sectionPauseCountdown
        return VStack(spacing: 4) {
            Rectangle()
                .fill(Color.white.opacity(isPaused ? 0.25 : 0.12))
                .frame(height: 1)

            if isPaused {
                Text("\(countdown)s")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.5))
            } else {
                Text("· \(Int(pauseDuration))s pause ·")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.22))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            GeometryReader { proxy in
                let y = proxy.frame(in: .named("scrollStack")).midY
                Color.clear.preference(
                    key: DividerPositionsKey.self,
                    value: [DividerPosition(index: index, y: y)]
                )
            }
        )
    }
}
