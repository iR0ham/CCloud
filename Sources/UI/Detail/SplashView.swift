import SwiftUI

// MARK: - Animated splash (owner: ui-detail) — fills the window, RootView dismisses it after 1.5 s

struct SplashView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.bg
                    .ignoresSafeArea()

                glowField(time: time)

                VStack(spacing: 14) {
                    logo(time: time)

                    Text("CCloud")
                        .font(.ccloud(40, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 4)

                    Text("پخش رایگان فیلم و سریال")
                        .font(.ccloud(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)

                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accentSoft)
                        .padding(.top, 16)
                }
                .offset(y: -10)

                VStack {
                    Spacer()
                    Text("نسخه مک • ۲.۰.۰")
                        .font(.ccloud(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .ignoresSafeArea()
    }

    // MARK: Pieces

    private func glowField(time: TimeInterval) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0)],
                        center: .center, startRadius: 4, endRadius: 190
                    )
                )
                .frame(width: 380, height: 380)
                .offset(x: cos(time * 0.7) * 150, y: sin(time * 0.9) * 90 - 70)
                .blur(radius: 24)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.accentBright.opacity(0.34), Theme.accentBright.opacity(0)],
                        center: .center, startRadius: 4, endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: cos(time * 0.55 + 2.1) * 190, y: sin(time * 0.75 + 1.2) * 110 + 90)
                .blur(radius: 26)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.accentDeep.opacity(0.42), Theme.accentDeep.opacity(0)],
                        center: .center, startRadius: 4, endRadius: 170
                    )
                )
                .frame(width: 330, height: 330)
                .offset(x: sin(time * 0.6 + 1.0) * 210, y: cos(time * 0.8 + 0.4) * 70 - 180)
                .blur(radius: 30)
        }
        .allowsHitTesting(false)
    }

    private func logo(time: TimeInterval) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.accent.opacity(0.32), Theme.accent.opacity(0)],
                        center: .center, startRadius: 8, endRadius: 120
                    )
                )
                .frame(width: 220, height: 220)
                .scaleEffect(1 + 0.04 * sin(time * 1.6))
                .opacity(0.85)

            BrandLogo(size: 98)
                .shadow(color: Theme.accent.opacity(0.5), radius: 22, y: 8)
                .scaleEffect(1 + 0.015 * sin(time * 1.6))
        }
        .frame(width: 230, height: 210)
    }
}
