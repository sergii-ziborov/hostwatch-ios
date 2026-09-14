import SwiftUI

@main
struct HostwatchApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("biometricUnlockEnabled") private var biometricUnlockEnabled = false
    @State private var unlocked = false
    @State private var unlocking = false
    @State private var unlockError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if model.restoringSession {
                    AppSplashView()
                } else if model.session.authenticated {
                    if biometricUnlockEnabled && !unlocked {
                        AppUnlockView(busy: unlocking, error: unlockError,
                                      unlock: { Task { await unlockIfNeeded() } },
                                      signOut: { Task { await model.signOut() } })
                    } else {
                        RootView().environmentObject(model)
                    }
                } else {
                    SignInView().environmentObject(model)
                }
            }
            .preferredColorScheme(.dark)
            .tint(HW.teal)
            .overlay {
                if scenePhase != .active && model.session.authenticated && biometricUnlockEnabled {
                    HW.background.ignoresSafeArea().overlay { LaunchBrand() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && biometricUnlockEnabled { unlocked = false }
                if phase == .active { Task { await unlockIfNeeded() } }
            }
            .onChange(of: model.restoringSession) { _, restoring in
                if !restoring { Task { await unlockIfNeeded() } }
            }
            .onChange(of: model.session.authenticated) { _, authenticated in
                unlocked = false
                if authenticated { Task { await unlockIfNeeded() } }
            }
            .onChange(of: biometricUnlockEnabled) { _, enabled in
                unlocked = !enabled
                if enabled { Task { await unlockIfNeeded() } }
            }
        }
    }

    @MainActor private func unlockIfNeeded() async {
        guard !model.restoringSession, model.session.authenticated,
              biometricUnlockEnabled, !unlocked, !unlocking, scenePhase == .active else { return }
        unlocking = true; unlockError = nil
        defer { unlocking = false }
        do {
            try await DeviceUnlock.authenticate()
            if scenePhase == .active && model.session.authenticated && biometricUnlockEnabled { unlocked = true }
        } catch {
            if scenePhase == .active { unlockError = error.localizedDescription }
        }
    }
}
