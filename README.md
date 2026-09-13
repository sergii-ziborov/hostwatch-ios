# Hostwatch for iPhone and iPad

Native SwiftUI control-plane client for Hostwatch. The iPhone and iPad app is intended for **public App Store distribution**, while access to a control plane is provisioned by an organization. It uses the same signed-in session and REST API as the web application. There is no public demo or registration flow.

**Release status:** the App Store Connect record and public privacy declaration exist. Xcode Cloud builds the current branch, and the Release configuration builds and launches in iPhone and iPad simulators. A local development-signed archive also builds, but exporting it for App Store Connect requires a distribution account and profile that the command-line Xcode environment does not have. A development build is installed on a paired iPhone 13 mini, but physical-device sign-in has not yet been verified because the device was locked. An App Store distribution archive, TestFlight upload, authenticated screenshots and public release are still pending.

## Product structure

- **Overview** — host resources and capacity with resource drilldowns.
- **Traffic** — requests, errors, destinations, sources, locations and retained evidence.
- **Incidents & risks** — operational incidents, anomaly signals and vulnerabilities in separate tabs.
- **Runtime topology** — a native SceneKit view of live project towers and node-to-project traffic. Drag to orbit, pinch or use controls to zoom, double tap to focus, and tap a tower or layer for a native inspector.
- **Workloads** — project traffic, processes, storage, limits and controls.
- **Traffic policies** — bandwidth, anomaly and IP/country access rules.
- **Environment** — per-project environment variable management.
- **Code health** — repository evidence, findings and vulnerabilities.
- **Automations**, **Access**, **Organization** — scheduled services, users and license/deployment settings.

The app supports the hosted control plane and licensed enterprise installations. The control-plane URL can be changed on the sign-in screen. Enterprise licenses remain created and verified by the controller REST API; the mobile app only displays and installs a signed license for an authorized owner.

On iPhone or iPad, sign in by scanning the one-time QR shown in **Organization → Account security → Sign in on iPhone or iPad** on an already signed-in Hostwatch website. Compare the six-digit number on both screens and approve on the website. The QR expires after two minutes and can only sign in the device that claimed it. Password and authenticator-code sign-in remain available. **More → Account security** lets an account enroll, replace, or disable its authenticator and approve another device's website sign-in with the camera or a short manual pairing code. That approval asks for Face ID or the device passcode.

The minimum deployment target is iOS 18. The four primary areas are native phone tabs; less frequent controls are under **More**. iPad keeps a sidebar. Links to a request destination or external advisory open in the system browser, outside the app.

## Build

```bash
xcodegen generate
xcodebuild -project Hostwatch.xcodeproj -scheme Hostwatch \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

For local UI development only, a Debug build may be launched with `HOSTWATCH_FIXTURES=1`. These values are fabricated test fixtures and display a prominent **SAMPLE DATA · DEBUG BUILD** notice instead of a Live status. A Release build ignores the flag and requires a real, authenticated control plane. No fixture screenshot is used as an App Store asset.

All app screens use SwiftUI, SceneKit, MapKit and direct JSON API calls. There are no embedded web pages, WebViews or bundled HTML assets. A shared `Hostwatch` scheme and an Xcode Cloud workflow are configured for this iOS repository. The controller and Go agent remain separate products; this iOS workflow does not build or publish them. Public App Store distribution still requires a validated archive, App Store Connect metadata, review credentials, on-device testing and App Review approval.

To run on a physical iPhone, open `Hostwatch.xcodeproj` in Xcode and select your device. Automatic signing uses the configured developer team; Xcode must have an authenticated Apple Account. For an Xcode Cloud archive, use the shared `Hostwatch` scheme, verify the selected branch and stable Xcode version, and explicitly enable App Store Connect distribution. Do not turn on automatic public release.

Apple reviewers need a dedicated, working account on a live control plane with representative data and any second-factor instructions. The sign-in screen alone is insufficient for review. The public privacy and support URLs, screenshots of the shipping build, app privacy answers, review notes and tester coverage must match the actual service before submission.

## License

The iOS source is public for inspection and evaluation but remains proprietary. It is **not MIT-licensed**. See [LICENSE](LICENSE). The backend, controller and agent are not included or licensed here.

For App Store review and users, see the [privacy policy](PRIVACY.md) and [support](SUPPORT.md). These links are also available from the signed-out app.

## App Store screenshots

The old UI-development screenshots used fabricated telemetry and have been removed. These are real **Release simulator captures of the signed-out screen**: [iPhone](docs/screenshots/iphone-sign-in.png) (1284 × 2778) and [iPad](docs/screenshots/ipad-sign-in.png) (2064 × 2752). They do not claim to show traffic. The store listing still needs authenticated captures from a provisioned account with representative real control-plane data; screenshot fields remain incomplete until that review setup is ready.
