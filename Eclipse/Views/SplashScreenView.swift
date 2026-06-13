//
//  SplashScreenView.swift
//  Eclipse
//
//  Animated moon splash screen that hides the cold boot loading.
//

import SwiftUI

struct SplashScreenView: View {
    @Binding var isFinished: Bool
    var onDismissed: () -> Void = {}

    // MARK: - Animation state

    @State private var moonScale: CGFloat = 0.3
    @State private var moonOpacity: Double = 0
    @State private var glowRadius: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var crescentOffset: CGFloat = 40
    @State private var coronaScale: CGFloat = 0.82
    @State private var coronaOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 12
    @State private var accentLineWidth: CGFloat = 0
    @State private var minimumTimeElapsed = false
    @State private var dismissing = false

    // Minimum display time so the animation does not flash.
    private let minimumDuration: Double = 1.6

    var body: some View {
        ZStack {
            splashBackground

            VStack(spacing: 22) {
                ZStack {
                    eclipseHalo

                    Circle()
                        .trim(from: 0.06, to: 0.42)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.92, green: 0.82, blue: 1.0).opacity(0.78),
                                    Color(red: 0.38, green: 0.70, blue: 1.0).opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 132, height: 132)
                        .rotationEffect(.degrees(-28))
                        .opacity(coronaOpacity)
                        .scaleEffect(coronaScale)

                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.36),
                                    Color(red: 0.53, green: 0.36, blue: 0.88).opacity(0.12),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .frame(width: 104, height: 104)
                        .opacity(coronaOpacity * 0.9)
                        .scaleEffect(coronaScale)

                    SplashSparkle(size: 7)
                        .offset(x: -58, y: -36)
                        .opacity(coronaOpacity)

                    SplashSparkle(size: 5)
                        .offset(x: 64, y: -22)
                        .opacity(coronaOpacity * 0.8)

                    SplashSparkle(size: 4)
                        .offset(x: 46, y: 50)
                        .opacity(coronaOpacity * 0.55)

                    moonMark
                }
                .frame(width: 180, height: 180)
                .scaleEffect(moonScale)
                .opacity(moonOpacity)

                VStack(spacing: 10) {
                    Text("Eclipse")
                        .font(.system(size: 29, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.91, blue: 1.0),
                                    Color(red: 0.64, green: 0.54, blue: 0.88)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.92, green: 0.80, blue: 1.0).opacity(0.85),
                                    Color(red: 0.44, green: 0.66, blue: 1.0).opacity(0.3)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: accentLineWidth, height: 2)
                        .shadow(color: Color(red: 0.60, green: 0.42, blue: 0.95).opacity(0.45), radius: 7, x: 0, y: 0)
                }
                .opacity(titleOpacity)
                .offset(y: titleOffset)

                ProgressView()
                    .tint(Color(red: 0.75, green: 0.70, blue: 0.90))
                    .opacity(minimumTimeElapsed && !isFinished ? 1 : 0)
                    .frame(height: 20)
                    .animation(.easeInOut(duration: 0.2), value: minimumTimeElapsed && !isFinished)
            }
        }
        .onAppear { runEntrance() }
        .onChange(of: isFinished) { finished in
            if finished { tryDismiss() }
        }
        .onChange(of: minimumTimeElapsed) { elapsed in
            if elapsed { tryDismiss() }
        }
        .opacity(dismissing ? 0 : 1)
        .scaleEffect(dismissing ? 1.08 : 1)
    }

    private var splashBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.025, blue: 0.035),
                    Color(red: 0.055, green: 0.045, blue: 0.075),
                    Color(red: 0.04, green: 0.035, blue: 0.045)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color(red: 0.35, green: 0.24, blue: 0.66).opacity(0.42),
                    Color(red: 0.10, green: 0.12, blue: 0.22).opacity(0.18),
                    Color.clear
                ],
                center: .top,
                startRadius: 12,
                endRadius: 360
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    Color(red: 0.40, green: 0.66, blue: 0.88).opacity(0.15),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 360
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }

    private var eclipseHalo: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.58, green: 0.42, blue: 0.92).opacity(glowOpacity * 0.55),
                        Color(red: 0.22, green: 0.47, blue: 0.84).opacity(glowOpacity * 0.18),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: 104
                )
            )
            .frame(width: 188, height: 188)
    }

    private var moonMark: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.94, blue: 1.0),
                            Color(red: 0.62, green: 0.54, blue: 0.88),
                            Color(red: 0.35, green: 0.46, blue: 0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 84, height: 84)

            Circle()
                .strokeBorder(Color.white.opacity(0.34), lineWidth: 1)
                .frame(width: 84, height: 84)

            Circle()
                .fill(Color(red: 0.035, green: 0.032, blue: 0.044))
                .frame(width: 66, height: 66)
                .offset(x: crescentOffset)
        }
        .shadow(color: Color(red: 0.50, green: 0.36, blue: 0.86).opacity(0.64), radius: glowRadius, x: 0, y: 0)
    }

    // MARK: - Animate in

    private func runEntrance() {
        withAnimation(.easeOut(duration: 0.6)) {
            moonScale = 1.0
            moonOpacity = 1.0
        }

        withAnimation(.easeInOut(duration: 0.8).delay(0.3)) {
            crescentOffset = 18
            glowRadius = 20
            glowOpacity = 0.7
            coronaScale = 1.0
            coronaOpacity = 1.0
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            titleOpacity = 1.0
            titleOffset = 0
            accentLineWidth = 74
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + minimumDuration) {
            minimumTimeElapsed = true
        }
    }

    // MARK: - Dismiss (fires as soon as BOTH conditions are met)

    private func tryDismiss() {
        guard minimumTimeElapsed, isFinished, !dismissing else { return }
        withAnimation(.easeIn(duration: 0.35)) {
            dismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismissed()
        }
    }
}

private struct SplashSparkle: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.8))
                .frame(width: size, height: 1)

            Capsule()
                .fill(Color.white.opacity(0.8))
                .frame(width: 1, height: size)
        }
        .shadow(color: Color(red: 0.67, green: 0.50, blue: 1.0).opacity(0.55), radius: 4, x: 0, y: 0)
    }
}
