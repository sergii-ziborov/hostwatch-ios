import LocalAuthentication
import SwiftUI

enum DeviceUnlock {
    static func isAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static func authenticate() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your Hostwatch control plane")
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
            Text("HOSTWATCH").font(.system(.title, design: .rounded, weight: .bold)).tracking(4)
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
                Image(systemName: "faceid").font(.system(size: 52)).foregroundStyle(HW.teal)
                    .padding(20).panel()
                Text("Your session is locked").font(.title2.bold())
                Text("Confirm with Face ID or your device passcode. Your server session still requires its own sign-in and two-factor settings.")
                    .font(.footnote).foregroundStyle(HW.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                if let error { Text(error).font(.footnote).foregroundStyle(HW.red).multilineTextAlignment(.center) }
                Button { unlock() } label: {
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    else { Label("Unlock Hostwatch", systemImage: "faceid").frame(maxWidth: .infinity) }
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(busy).frame(maxWidth: 320)
                Button("Sign out", action: signOut).font(.footnote).disabled(busy)
            }.padding(24)
        }
    }
}
