import UIKit

/// Centralized tactile haptics for creation milestones.
@MainActor
public enum CraftHaptics {
    /// Fires a distinct, prominent haptic vibration to notify the user that an image,
    /// 3D model, or video animation generation has finished.
    public static func notifyCreationComplete() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        
        // A tactile follow-up pulse so the user feels an unmistakable "finished" signature
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.prepare()
            impact.impactOccurred(intensity: 0.95)
        }
    }

    /// Fires a distinct warning vibration when Token balance is insufficient.
    public static func notifyTokenShortfall() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            let impact = UIImpactFeedbackGenerator(style: .rigid)
            impact.prepare()
            impact.impactOccurred(intensity: 0.9)
            try? await Task.sleep(nanoseconds: 120_000_000)
            impact.impactOccurred(intensity: 0.75)
        }
    }

    /// Fires a subtle selection click when choosing filters, models, or categories.
    public static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
