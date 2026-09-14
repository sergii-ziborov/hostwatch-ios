import AVFoundation
import CoreImage.CIFilterBuiltins
import LocalAuthentication
import Security
import SwiftUI

enum QRPayload {
    static func url(server: String, id: String) -> URL? {
        guard let base = URL(string: server), var parts = URLComponents(url: base, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? "") else { return nil }
        parts.path = "/"
        parts.query = nil
        parts.fragment = "approve=\(id)"
        return parts.url
    }

    static func id(from value: String, server: String) -> String? {
        guard let target = URL(string: value), let base = URL(string: server),
              target.scheme?.lowercased() == base.scheme?.lowercased(),
              target.host?.lowercased() == base.host?.lowercased(),
              target.port == base.port,
              let fragment = target.fragment, fragment.hasPrefix("approve=") else { return nil }
        let id = String(fragment.dropFirst("approve=".count))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return id.count == 24 && id.unicodeScalars.allSatisfy(allowed.contains) ? id : nil
    }

    static func deviceTicket(from value: String) -> DeviceQRTicket? {
        guard let parts = URLComponents(string: value), let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(host.lowercased())),
              let fragment = parts.fragment, fragment.hasPrefix("device-login=") else { return nil }
        let pair = String(fragment.dropFirst("device-login=".count)).split(separator: ".", omittingEmptySubsequences: false)
        guard pair.count == 2 else { return nil }
        let id = String(pair[0]), secret = String(pair[1])
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard id.count == 24, secret.count == 43,
              id.unicodeScalars.allSatisfy(allowed.contains), secret.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        var origin = parts
        origin.path = "/"; origin.query = nil; origin.fragment = nil
        guard let server = origin.url?.absoluteString else { return nil }
        return DeviceQRTicket(server: server, id: id, secret: secret)
    }
}

struct DeviceQRTicket {
    let server: String
    let id: String
    let secret: String
}

struct QRCodeImage: View {
    let value: String
    var size: CGFloat = 220

    var body: some View {
        Group {
            if let image = makeImage() {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .frame(width: size, height: size).padding(10).background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("One-time QR code")
            } else {
                ContentUnavailableView("QR unavailable", systemImage: "qrcode")
            }
        }
    }

    private func makeImage() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct DeviceQRSignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scanning = false
    @State private var ticket: DeviceQRTicket?
    @State private var claim: QRApproval?
    @State private var proof = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Scan the QR on your website").font(.title3.bold())
            Text("First sign in on gethostwatch.com with your email and password. There, open Organization → Account security → Sign in on iPhone or iPad → Show sign-in QR. Scan that code with this iPhone, compare the number, and approve on the website. If you cannot access the website, use Password above instead.")
                .font(.footnote).foregroundStyle(HW.secondary).multilineTextAlignment(.center)
            Button { scanning = true } label: { Label("Scan website QR", systemImage: "qrcode.viewfinder") }
                .buttonStyle(.borderedProminent).disabled(busy)
            if let ticket, claim == nil {
                Text("Website: \(ticket.server)").font(.footnote).foregroundStyle(HW.secondary).textSelection(.enabled)
                Button(busy ? "Connecting…" : "Continue with this website") { Task { await connect(ticket) } }
                    .buttonStyle(.bordered).disabled(busy)
            }
            if let claim {
                Text("Compare this number with the website, then approve on the website:")
                    .font(.footnote).foregroundStyle(HW.secondary).multilineTextAlignment(.center)
                Text(claim.verificationCode).font(.largeTitle.monospacedDigit().bold()).tracking(4).foregroundStyle(HW.teal)
                ProgressView("Waiting for website approval…").font(.footnote)
                Button("Cancel") { self.claim = nil; self.ticket = nil; proof = "" }.buttonStyle(.bordered)
            }
            if !error.isEmpty { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(HW.red) }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $scanning) {
            NavigationStack {
                CameraQRScanner { value in
                    scanning = false
                    claim = nil; proof = ""; error = ""
                    if let parsed = QRPayload.deviceTicket(from: value) { ticket = parsed }
                    else { ticket = nil; error = "Scan the sign-in QR shown in your Hostwatch website account settings." }
                }
                .navigationTitle("Scan website QR")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
            }
        }
        .task(id: claim?.id) {
            guard let ticket, claim != nil, !proof.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                do {
                    if try await model.redeemDeviceQR(ticket, proof: proof) { return }
                } catch {
                    self.error = error.localizedDescription
                    self.claim = nil; self.ticket = nil; proof = ""
                    return
                }
            }
        }
    }

    private func connect(_ ticket: DeviceQRTicket) async {
        busy = true; error = ""; defer { busy = false }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            error = "Could not create a secure device proof."; return
        }
        let proof = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        do {
            claim = try await model.claimDeviceQR(ticket, proof: proof)
            self.proof = proof
        } catch { self.error = error.localizedDescription }
    }
}

struct AccountSecurityView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("biometricUnlockEnabled") private var biometricUnlockEnabled = false
    @State private var deviceUnlockAvailable = false
    @State private var showApproval = false
    @State private var pendingCount = 0
    @State private var currentPassword = ""
    @State private var setupOtp = ""
    @State private var disableOtp = ""
    @State private var setup: TOTPSetup?
    @State private var message = ""
    @State private var busy = false
    private var enabled: Bool { model.session.user?.totpEnabled == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("App unlock").font(.title3.bold())
                Toggle("Use Face ID or device passcode", isOn: $biometricUnlockEnabled)
                    .disabled(!deviceUnlockAvailable)
                Text(deviceUnlockAvailable
                     ? "Lock Hostwatch when it goes to the background and confirm again on return. This protects the app on this device; it does not replace website sign-in or account two-factor authentication."
                     : "Set up Face ID and a device passcode in Settings to enable app unlock.")
                    .font(.footnote).foregroundStyle(HW.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).panel()
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Account security")
                Text("Approve a sign-in").font(.title2.bold())
                Text("Scan the other device's QR code or approve a waiting password verification. You'll confirm with Face ID or your device passcode.")
                    .font(.footnote).foregroundStyle(HW.secondary)
                Button { showApproval = true } label: {
                    Label(pendingCount > 0 ? "Review \(pendingCount) pending sign-in\(pendingCount == 1 ? "" : "s")" : "Scan or enter pairing code", systemImage: "qrcode.viewfinder")
                }.buttonStyle(.borderedProminent)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).panel()

            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Authenticator").font(.title3.bold()); Spacer(); Text(enabled ? "ON" : "OFF").font(.caption.bold()).foregroundStyle(enabled ? HW.teal : HW.amber) }
                Text(enabled ? "A code or approval in an already signed-in app is required after your password." : "Add a time-based authenticator for your account.")
                    .font(.footnote).foregroundStyle(HW.secondary)
                SecureField("Current password", text: $currentPassword).textContentType(.password).textFieldStyle(.roundedBorder)
                Button(enabled ? "Replace authenticator" : "Set up authenticator") { Task { await beginSetup() } }
                    .buttonStyle(.bordered).disabled(currentPassword.isEmpty || busy)

                if let setup {
                    Divider()
                    Text("Scan in an authenticator app, then enter its first six-digit code.").font(.footnote).foregroundStyle(HW.secondary)
                    QRCodeImage(value: setup.uri, size: 180)
                    Text(setup.totpSecret).font(.footnote.monospaced()).textSelection(.enabled)
                    TextField("Six-digit code", text: $setupOtp).keyboardType(.numberPad).textContentType(.oneTimeCode).textFieldStyle(.roundedBorder)
                    Button("Confirm and enable") { Task { await confirmSetup() } }.buttonStyle(.borderedProminent).disabled(setupOtp.count != 6 || busy)
                }
                if enabled {
                    Divider()
                    TextField("Current authenticator code", text: $disableOtp).keyboardType(.numberPad).textContentType(.oneTimeCode).textFieldStyle(.roundedBorder)
                    Button("Disable authenticator", role: .destructive) { Task { await disable() } }
                        .buttonStyle(.bordered).disabled(currentPassword.isEmpty || disableOtp.count != 6 || busy)
                }
                if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(HW.red) }
                Text("Changing two-factor settings signs out existing sessions. Sign in again with your updated method.")
                    .font(.caption).foregroundStyle(HW.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).panel()
        }
        .sheet(isPresented: $showApproval) { QRApprovalView() }
        .task { deviceUnlockAvailable = DeviceUnlock.isAvailable() }
        .task {
            guard !model.fixtures else { return }
            while !Task.isCancelled {
                pendingCount = (try? await model.pendingQRApprovals().count) ?? 0
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func beginSetup() async {
        busy = true; message = ""; defer { busy = false }
        do { setup = try await model.beginTOTP(currentPassword: currentPassword); currentPassword = "" }
        catch { message = error.localizedDescription }
    }
    private func confirmSetup() async {
        busy = true; message = ""; defer { busy = false }
        do { try await model.confirmTOTP(otp: setupOtp) }
        catch { message = error.localizedDescription }
    }
    private func disable() async {
        busy = true; message = ""; defer { busy = false }
        do { try await model.disableTOTP(currentPassword: currentPassword, otp: disableOtp) }
        catch { message = error.localizedDescription }
    }
}

struct QRApprovalView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    @State private var ticket: QRApproval?
    @State private var pending: [QRApproval] = []
    @State private var scanning = false
    @State private var confirmed = false
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Scan QR code", systemImage: "qrcode.viewfinder") { scanning = true }
                    HStack {
                        TextField("Pairing code", text: $manualCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Button("Find") { Task { await inspect(manualCode) } }.disabled(manualCode.isEmpty || busy)
                    }
                } header: { Text("From another device") } footer: { Text("The other device shows a short pairing code if its camera is unavailable.") }

                if !pending.isEmpty {
                    Section("Waiting for your second-factor approval") {
                        ForEach(pending) { item in
                            Button { ticket = item; confirmed = false } label: {
                                VStack(alignment: .leading) { Text(item.device).lineLimit(2); Text("\(item.clientIP) · \(item.verificationCode)").font(.caption).foregroundStyle(HW.secondary) }
                            }
                        }
                    }
                }
                if let ticket {
                    Section("Verify before approving") {
                        LabeledContent("Type", value: ticket.kind == "second-factor" ? "After password" : "New device sign-in")
                        LabeledContent("Device", value: ticket.device)
                        LabeledContent("Network address", value: ticket.clientIP)
                        LabeledContent("Pairing code", value: ticket.entryCode)
                        Text(ticket.verificationCode).font(.largeTitle.monospacedDigit().bold()).foregroundStyle(HW.teal)
                        Toggle("This number matches the other device", isOn: $confirmed)
                        Button("Approve sign-in") { Task { await handle(approve: true) } }
                            .disabled(!confirmed || busy || ticket.status != "pending")
                        Button("Deny sign-in", role: .destructive) { Task { await handle(approve: false) } }
                            .disabled(busy || ticket.status != "pending")
                    }
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(HW.red) } }
            }
            .navigationTitle("Approve sign-in")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    CameraQRScanner { value in
                        scanning = false
                        if let id = QRPayload.id(from: value, server: model.baseURLText) { Task { await inspect(id) } }
                        else { error = "This QR code belongs to a different control plane." }
                    }
                    .navigationTitle("Scan Hostwatch QR")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
                }
            }
            .task {
                while !Task.isCancelled {
                    if let approvals = try? await model.pendingQRApprovals() { pending = approvals }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func inspect(_ value: String) async {
        busy = true; error = ""; confirmed = false; defer { busy = false }
        do { ticket = try await model.inspectQR(value) }
        catch { self.error = error.localizedDescription }
    }
    private func handle(approve: Bool) async {
        guard let ticket else { return }
        busy = true; error = ""; defer { busy = false }
        do {
            if approve {
                let context = LAContext()
                try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Approve Hostwatch sign-in for another device")
            }
            try await model.approveQR(ticket, approve: approve)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct CameraQRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> QRScannerController { QRScannerController(onCode: onCode) }
    func updateUIViewController(_ controller: QRScannerController, context: Context) { controller.onCode = onCode }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (String) -> Void
    private let session = AVCaptureSession()
    private let preview = AVCaptureVideoPreviewLayer()
    private let status = UILabel()
    private var delivered = false

    init(onCode: @escaping (String) -> Void) { self.onCode = onCode; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview.session = session; preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        status.text = "Point the camera at a Hostwatch sign-in QR code"
        status.textColor = .white; status.textAlignment = .center; status.numberOfLines = 2
        status.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        view.addSubview(status)
        Task { [weak self] in
            guard let self else { return }
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            if allowed { self.configure() }
            else { self.status.text = "Camera permission is needed to scan. You can enter the pairing code manually." }
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
        status.frame = CGRect(x: 20, y: view.safeAreaInsets.top + 20, width: view.bounds.width - 40, height: 70)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session.stopRunning()
    }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            status.text = "Camera is unavailable. Enter the pairing code manually."
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { status.text = "QR scanning is unavailable."; return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        delivered = true
        onCode(value)
    }
}
