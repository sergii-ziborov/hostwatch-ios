import LocalAuthentication
import SwiftUI

enum DeviceUnlock {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func context() -> LAContext {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return context
    }

    static func isAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static var methodName: String {
        switch context().biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "device passcode"
        }
    }

    static var symbolName: String {
        switch context().biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.fill"
        }
    }

    static func authenticate() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"
        try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock your saved Hostwatch session with \(methodName)"
        )
    }
}

struct LaunchBrand: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(HW.teal.opacity(0.75), lineWidth: 2)
                    .frame(width: 92, height: 92)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HW.teal.opacity(0.10))
                    .frame(width: 72, height: 72)
                Text("H").font(.system(size: 45, weight: .black, design: .rounded)).foregroundStyle(HW.teal)
            }
            Text("HOSTWATCH").font(.hw(.title, design: .rounded, weight: .bold)).kerning(4)
            Text("Infrastructure control plane").font(.subheadline).foregroundStyle(HW.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppSplashView: View {
    var body: some View {
        ZStack {
            HW.background.ignoresSafeArea()
            VStack(spacing: 40) {
                LaunchBrand()
                ProgressView("Connecting securely…").tint(HW.teal).foregroundStyle(HW.secondary)
            }
        }
    }
}

struct AppUnlockView: View {
    let busy: Bool
    let error: String?
    let unlock: () -> Void
    let signOut: () -> Void

    var body: some View {
        ZStack {
            HW.background.ignoresSafeArea()
            VStack(spacing: 25) {
                LaunchBrand()
                Image(systemName: DeviceUnlock.symbolName).font(.system(size: 52)).foregroundStyle(HW.teal)
                    .padding(20).panel()
                Text("Unlock Hostwatch").font(.title2.bold())
                Text("Your control-plane session stays on this device. Confirm with \(DeviceUnlock.methodName) to open it. Sign out only if you want this device forgotten.")
                    .font(.footnote).foregroundStyle(HW.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                if let error { Text(error).font(.footnote).foregroundStyle(HW.red).multilineTextAlignment(.center) }
                Button { unlock() } label: {
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    else { Label("Unlock with \(DeviceUnlock.methodName)", systemImage: DeviceUnlock.symbolName).frame(maxWidth: .infinity) }
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(busy).frame(maxWidth: 320)
                Button("Sign out", action: signOut).font(.footnote).disabled(busy)
            }.padding(24)
        }
    }
}
