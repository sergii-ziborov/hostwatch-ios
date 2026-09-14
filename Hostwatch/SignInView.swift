import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var otp = ""
    @State private var showServer = false
    @State private var useQR = false

    var body: some View {
        ZStack {
            HW.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 44)
                    brand
                    VStack(spacing: 16) {
                        if model.session.requiresOtp == true {
                            otpForm
                            Button("Use another account") { Task { await model.signOut(); otp = "" } }
                                .font(.footnote).disabled(model.loading)
                        } else {
                            Picker("Sign-in method", selection: $useQR) {
                                Text("Password").tag(false)
                                Text("Scan website QR").tag(true)
                            }.pickerStyle(.segmented)
                            if useQR { DeviceQRSignInView() }
                            else { credentialsForm }
                        }
                        DisclosureGroup("Control-plane address", isExpanded: $showServer) {
                            TextField("https://control.example.com", text: $model.baseURLText)
                                .textInputAutocapitalization(.never).keyboardType(.URL).padding(.top, 10)
                            Text("Use the HTTPS address supplied by your administrator.").font(.caption).foregroundStyle(HW.secondary)
                        }.font(.footnote)
                        if let error = model.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(HW.red).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 460)
                    .panel()

                    Text("Hosted control plane or licensed enterprise installation. Access is provisioned by your organization.")
                        .font(.footnote).foregroundStyle(HW.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    HStack(spacing: 16) {
                        Link("Support", destination: URL(string: "https://github.com/sergii-ziborov/hostwatch-ios/blob/codex/initial-product/SUPPORT.md")!)
                        Link("Privacy policy", destination: URL(string: "https://github.com/sergii-ziborov/hostwatch-ios/blob/codex/initial-product/PRIVACY.md")!)
                    }
                    .font(.footnote.weight(.semibold))
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var brand: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).stroke(HW.teal, lineWidth: 2).frame(width: 72, height: 72)
                Text("H").font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(HW.teal)
            }
            Text("HOSTWATCH").font(.system(.title, design: .rounded, weight: .bold)).tracking(3)
            Text("Infrastructure control plane").foregroundStyle(HW.secondary)
        }
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign in").font(.title2.bold())
            Text("Use your company account. After signing in, this app can approve QR sign-ins on the website.")
                .font(.footnote).foregroundStyle(HW.secondary)
            TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                .padding(14).background(HW.background).clipShape(RoundedRectangle(cornerRadius: 12))
            SecureField("Password", text: $password).textContentType(.password)
                .padding(14).background(HW.background).clipShape(RoundedRectangle(cornerRadius: 12))
            Button {
                Task { await model.signIn(email: email, password: password) }
            } label: {
                if model.loading { ProgressView().frame(maxWidth: .infinity) }
                else { Text("Sign in").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(email.isEmpty || password.isEmpty || model.loading)

        }
    }

    private var otpForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Two-factor authentication").font(.title2.bold())
            Text("Enter the six-digit code from your authenticator.").foregroundStyle(HW.secondary)
            TextField("000000", text: $otp).keyboardType(.numberPad).textContentType(.oneTimeCode)
                .font(.title2.monospacedDigit()).padding(14).background(HW.background).clipShape(RoundedRectangle(cornerRadius: 12))
            Button("Verify") { Task { await model.verify(otp: otp) } }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).disabled(otp.count != 6 || model.loading)
        }
    }
}
