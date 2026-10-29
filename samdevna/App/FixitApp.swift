import CoreGraphics
import SwiftUI

@main
struct FixitLensApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Meta Wearables Device Access Toolkit: once, before any glasses call.
        GlassesCameraService.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                // fixitlens://join?code=K7M2QX, https://<relay>/j/K7M2QX (universal link if you add one),
                // and the Meta AI app's registration/permission callbacks (metaWearablesAction).
                .onOpenURL { model.open(url: $0) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if hasOnboarded {
                LensView()
                    .transition(.opacity)
            } else {
                OnboardingView { Motion.animate(Motion.smooth) { hasOnboarded = true } }
                    .transition(.opacity)
            }
        }
        .tint(Palette.amber)
        .preferredColorScheme(model.appearance.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshKey() }
            if phase == .background { model.mic.cancel() }
        }
    }
}
