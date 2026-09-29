import SwiftUI

@main
struct HostwatchApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("biometricUnlockEnabled") private var biometricUnlockEnabled = true
    @State private var unlocked = false
    @State private var unlocking = false
    @State private var unlockError: String?
    @State private var approvalID: String?

    init() {
        HWAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.restoringSession {
                    AppSplashView()
                } else if showsUnlock {
                    AppUnlockView(busy: unlocking, error: unlockError,
                                  unlock: { Task { await unlockIfNeeded() } },
                                  signOut: { Task { await model.signOut(); unlocked = false } })
                        .onAppear { Task { await unlockIfNeeded() } }
                } else if model.session.authenticated {
                    RootView().environmentObject(model)
                } else {
                    SignInView().environmentObject(model)
                }
            }
            .onOpenURL { handleLink($0) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { handleLink(url) }
            }
            .sheet(isPresented: Binding(get: { approvalID != nil && model.session.authenticated && unlocked }, set: { if !$0 { approvalID = nil } })) {
                QRApprovalView(initialID: approvalID).environmentObject(model)
            }
            .preferredColorScheme(.dark)
            .tint(HW.teal)
            .overlay {
                if scenePhase != .active && showsLockCover {
                    HW.background.ignoresSafeArea().overlay { LaunchBrand() }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    Task { await model.persistSession() }
                    if biometricUnlockEnabled && DeviceUnlock.isAvailable() && keepsSession {
                        unlocked = false
                    }
                }
                if phase == .active { Task { await unlockIfNeeded() } }
            }
            .onChange(of: model.restoringSession) { restoring in
                if !restoring { Task { await unlockIfNeeded() } }
            }
            .onChange(of: model.session.authenticated) { authenticated in
                if authenticated {
                    unlocked = true
                    Task { await model.persistSession() }
                } else if !model.hasSavedSession {
                    unlocked = false
                }
            }
            .onChange(of: biometricUnlockEnabled) { enabled in
                if !enabled { unlocked = true }
                else if keepsSession { unlocked = false; Task { await unlockIfNeeded() } }
            }
        }
    }

    private func handleLink(_ incoming: URL) {
        let url = URL(string: QRPayload.canonical(incoming.absoluteString)) ?? incoming
        if let id = QRPayload.id(from: url.absoluteString, server: model.baseURLText) {
            approvalID = id
            if !model.session.authenticated { model.errorMessage = "Sign in to Hostwatch first, then approve the website request." }
        } else if QRPayload.deviceTicket(from: url.absoluteString) != nil, !model.session.authenticated {
            model.deviceSignInURL = url
        }
    }

    private var keepsSession: Bool { model.session.authenticated || model.hasSavedSession }

    private var showsUnlock: Bool {
        !model.fixtures && !DeviceUnlock.isRunningTests && keepsSession && !unlocked && biometricUnlockEnabled && DeviceUnlock.isAvailable()
    }

    private var showsLockCover: Bool { showsUnlock || (keepsSession && biometricUnlockEnabled && !unlocked) }

    @MainActor private func unlockIfNeeded() async {
        guard !DeviceUnlock.isRunningTests, !model.restoringSession, !unlocked, !unlocking, scenePhase == .active, keepsSession else { return }
        if !biometricUnlockEnabled || !DeviceUnlock.isAvailable() {
            await model.unlockSavedSession()
            unlocked = true
            return
        }
        unlocking = true; unlockError = nil
        defer { unlocking = false }
        do {
            try await DeviceUnlock.authenticate()
            await model.unlockSavedSession()
            if scenePhase == .active { unlocked = true }
        } catch {
            if scenePhase == .active { unlockError = error.localizedDescription }
        }
    }
}
