import SwiftUI
import AppKit

// MARK: - About window (owner: ui-detail) — presented as a sheet from the sidebar

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let version = "۲.۰.۰"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    content
                }
                .padding(.horizontal, 34)
                .padding(.top, 26)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }

            footer
        }
        .frame(width: 680, height: 730)
        .background(Theme.bg)
        // Sheets do not reliably inherit the app's RTL environment; force it here.
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.accent.opacity(0.4), Theme.accent.opacity(0)],
                            center: .center, startRadius: 6, endRadius: 74
                        )
                    )
                    .frame(width: 148, height: 148)
                BrandLogo(size: 88)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 20, y: 6)
            }
            .frame(height: 142)

            Text("CCloud")
                .font(.ccloud(32, weight: .bold))
                .foregroundStyle(Theme.text)

            Text("نسخه مک • \(version)")
                .font(.ccloud(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)

            HStack(spacing: 7) {
                techChip("SwiftUI")
                techChip("AVFoundation")
                techChip("ffmpeg")
            }
            .padding(.top, 12)
        }
    }

    private func techChip(_ title: String) -> some View {
        Text(title)
            .font(.ccloud(9.5, weight: .semibold))
            .foregroundStyle(Theme.accentSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.accent.opacity(0.14)))
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            descriptionCard
            linksCard
        }
        .padding(.top, 22)
        .frame(maxWidth: .infinity)
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("درباره این نسخه")
                .font(.ccloud(13, weight: .bold))
                .foregroundStyle(Theme.text)

            Text("CCloud یک برنامه رایگان برای تماشای فیلم و سریال با دوبله و زیرنویس فارسی است. این نسخه، پورت بومی macOS برنامه اندروید CCloud است که با SwiftUI و AppKit ساخته شده؛ همان کاتالوگ زنده، جستجو، فیلتر کشورها، علاقه‌مندی‌ها و پخش‌کننده اختصاصی را به صورت یکپارچه با رابط راست‌به‌چپ در اختیار شما می‌گذارد.")
                .font(.ccloud(11.5))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: Theme.corner, fill: Theme.card)
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                Text("پیوندها و اعتبار")
                    .font(.ccloud(13, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            linkRow(icon: "chevron.left.forwardslash.chevron.right",
                    title: "مخزن GitHub پروژه",
                    detail: "github.com/code3-dev/CCloud",
                    url: "https://github.com/code3-dev/CCloud")
            divider
            linkRow(icon: "paperplane",
                    title: "تلگرام توسعه‌دهنده",
                    detail: "@h3dev",
                    url: "https://t.me/h3dev")
            divider
            linkRow(icon: "megaphone",
                    title: "کانال تلگرام",
                    detail: "@irdevs_dns",
                    url: "https://t.me/irdevs_dns")

            Text("سازنده اصلی اپلیکیشن اندروید: حسین پیرا (Hossein Pira)")
                .font(.ccloud(10))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: Theme.corner, fill: Theme.card)
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }

    private func linkRow(icon: String, title: String, detail: String, url: String) -> some View {
        Button {
            guard let link = URL(string: url) else { return }
            NSWorkspace.shared.open(link)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.ccloud(12, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(detail)
                        .font(.ccloud(9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer (always visible)

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            HStack(spacing: 12) {
                Text("این برنامه برای کاربران ایرانی ساخته شده است • بدون نیاز به ثبت‌نام")
                    .font(.ccloud(10))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                Button("بستن") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 14)
        }
        .background(Theme.bg)
    }
}
