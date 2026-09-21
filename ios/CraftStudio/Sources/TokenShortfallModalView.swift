import SwiftUI

/// Presented when a user attempts an action with insufficient Tokens.
/// Includes haptic vibration feedback and a direct CTA to jump to the Token Packs paywall.
struct TokenShortfallModalView: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let needed: Int
    let available: Int
    let onJumpToTokenPacks: () -> Void

    var missing: Int { max(0, needed - available) }

    var body: some View {
        VStack(spacing: 20) {
            // Glow badge
            ZStack {
                Circle()
                    .fill(appearance.fill.opacity(0.18))
                    .frame(width: 68, height: 68)
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(appearance.ink)
            }
            .padding(.top, 8)

            // Header
            VStack(spacing: 6) {
                Text(store.t("Tokens Needed", "Token 余额不足"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(appearance.ink)
                Text(store.t("This action requires \(needed) Tokens, but your current balance is \(available) Tokens (need \(missing) more).",
                             "本次操作需要 \(needed) 个 Token，你当前拥有 \(available) 个（还差 \(missing) 个）。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            }

            // Quick Info Callout
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(appearance.ink)
                Text(store.t("Add a Token pack to continue generating your 3D models and animations immediately.",
                             "购买 Token 包即可立即继续制作 3D 模型与动画。"))
                    .font(.caption)
                    .foregroundStyle(appearance.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(appearance.fill.opacity(0.3), lineWidth: 1)
            )

            // Action buttons
            VStack(spacing: 10) {
                Button {
                    dismiss()
                    onJumpToTokenPacks()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bag.fill")
                        Text(store.t("Go to Token Packs", "前往获取 Token 包"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(CraftPrimary())

                Button {
                    dismiss()
                } label: {
                    Text(store.t("Maybe Later", "稍后再说"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .background { StudioAtmosphere(intensity: 0.75) }
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .onAppear {
            CraftHaptics.notifyTokenShortfall()
        }
    }
}
