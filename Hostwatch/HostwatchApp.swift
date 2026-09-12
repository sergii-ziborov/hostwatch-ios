import SwiftUI

@main
struct HostwatchApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.session.authenticated {
                    RootView()
                        .environmentObject(model)
                } else {
                    SignInView()
                        .environmentObject(model)
                }
            }
            .preferredColorScheme(.dark)
            .tint(HW.teal)
        }
    }
}

