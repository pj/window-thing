import SwiftUI
import AppKit
import CoreGraphics
import WindowThingCore

// MARK: - Onboarding Flow

/// Three-step first-run flow shown once when `hasCompletedOnboarding` is false.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep: Int = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to WindowThing",
            subtitle: "Your macOS window manager",
            icon: "rectangle.3.group",
            body: "WindowThing lets you organize your windows into layouts and move them instantly with hotkeys. Let's get you set up.",
            primaryLabel: "Get Started"
        ),
        OnboardingStep(
            title: "Accessibility Access",
            subtitle: "Required to move windows",
            icon: "lock.shield",
            body: "WindowThing needs Accessibility permission to reposition your windows. Click the button below to open System Settings and grant access.",
            primaryLabel: "Open System Settings",
            action: openAccessibilitySettings
        ),
        OnboardingStep(
            title: "Screen Recording (Optional)",
            subtitle: "Enables window previews",
            icon: "camera.on.rectangle",
            body: "For live window thumbnails in the layout editor, grant Screen Recording permission. You can skip this — the app works fine with icons instead.",
            primaryLabel: "Grant Permission",
            secondaryLabel: "Skip",
            action: requestScreenRecording
        )
    ]

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Step content
                OnboardingStepView(step: steps[currentStep])
                    .padding(.horizontal, 40)
                    .id(currentStep)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.2), value: currentStep)

                Spacer()

                // Navigation
                HStack(spacing: 12) {
                    // Step dots
                    HStack(spacing: 6) {
                        ForEach(0..<steps.count, id: \.self) { i in
                            Circle()
                                .fill(i == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 7, height: 7)
                                .animation(.easeInOut, value: currentStep)
                        }
                    }

                    Spacer()

                    // Secondary action (skip)
                    if let secondaryLabel = steps[currentStep].secondaryLabel {
                        Button(secondaryLabel) {
                            advance()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    // Primary action
                    Button(steps[currentStep].primaryLabel) {
                        steps[currentStep].action?()
                        if currentStep < steps.count - 1 {
                            advance()
                        } else {
                            finish()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.return)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 480, height: 340)
    }

    private func advance() {
        withAnimation { currentStep += 1 }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isPresented = false
    }
}

// MARK: - Step Model

private struct OnboardingStep {
    let title: String
    let subtitle: String
    let icon: String
    let body: String
    let primaryLabel: String
    var secondaryLabel: String? = nil
    var action: (() -> Void)? = nil
}

// MARK: - Step View

private struct OnboardingStepView: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: step.icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(height: 60)

            VStack(spacing: 6) {
                Text(step.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(step.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(step.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Permission Helpers

private func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}

private func requestScreenRecording() {
    // Preflight triggers the system prompt on first call
    _ = CGPreflightScreenCaptureAccess()
    CGRequestScreenCaptureAccess()
}

// MARK: - Onboarding Window

final class OnboardingWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.title = "Welcome to WindowThing"
        self.center()
        self.isReleasedWhenClosed = false

        let hv = NSHostingView(rootView: OnboardingBridge(window: self))
        hv.frame = NSRect(origin: .zero, size: NSSize(width: 480, height: 340))
        self.contentView = hv
    }
}

private struct OnboardingBridge: View {
    let window: NSWindow
    @State private var isPresented = true

    var body: some View {
        OnboardingView(isPresented: $isPresented)
            .onChange(of: isPresented) { visible in
                if !visible { window.close() }
            }
    }
}
