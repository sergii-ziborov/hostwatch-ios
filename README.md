# Hostwatch for iPhone and iPad

Native SwiftUI control-plane client for Hostwatch. The iPhone and iPad app is intended for **public App Store distribution**, while access to a control plane is provisioned by an organization. It uses the same signed-in session and REST API as the web application. There is no public demo or registration flow.

**Release status:** a development build is installed on a paired iPhone 13 mini; a physical-device launch and account sign-in have not yet been verified because the phone was locked. The first Xcode Cloud build has been started. A TestFlight build or public App Store release is not yet confirmed. Do not describe the app as available in the App Store until Apple has approved and published it.

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

Sign-in supports password plus an authenticator code, or one-time QR approval from an already signed-in device. After password entry, a signed-in app can approve the second factor. **More → Account security** lets an account enroll, replace, or disable its authenticator, and review pending sign-ins. QR approval uses the device camera or a short manual pairing code, requires matching the displayed verification number, and asks for Face ID or the device passcode before sending approval. The controller keeps pairing tickets for two minutes in memory.

The minimum deployment target is iOS 18. The four primary areas are native phone tabs; less frequent controls are under **More**. iPad keeps a sidebar. Links to a request destination or external advisory open in the system browser, outside the app.

## Build

```bash
xcodegen generate
xcodebuild -project Hostwatch.xcodeproj -scheme Hostwatch \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

For local screenshot and UI verification only, launch the Debug build with `HOSTWATCH_FIXTURES=1`. This switch is read from the process environment and is absent from the production interface.

All app screens use SwiftUI, SceneKit, MapKit and direct JSON API calls. There are no embedded web pages, WebViews or bundled HTML assets. A shared `Hostwatch` scheme and an Xcode Cloud workflow are configured for this iOS repository. The controller and Go agent remain separate products; this iOS workflow does not build or publish them. Public App Store distribution still requires a validated archive, App Store Connect metadata, review credentials, on-device testing and App Review approval.

To run on a physical iPhone, open `Hostwatch.xcodeproj` in Xcode and select your device. Automatic signing uses the configured developer team; Xcode must have an authenticated Apple Account. For an Xcode Cloud archive, use the shared `Hostwatch` scheme, verify the selected branch and stable Xcode version, and explicitly enable App Store Connect distribution. Do not turn on automatic public release.

Apple reviewers need a dedicated, working account on a live control plane with representative data and any second-factor instructions. The sign-in screen alone is insufficient for review. The public privacy and support URLs, screenshots of the shipping build, app privacy answers, review notes and tester coverage must match the actual service before submission.

## License

The iOS source is public for inspection and evaluation but remains proprietary. It is **not MIT-licensed**. See [LICENSE](LICENSE). The backend, controller and agent are not included or licensed here.

## Verified layouts

| iPhone traffic | iPad runtime topology |
| --- | --- |
| ![iPhone traffic](docs/screenshots/iphone-traffic.png) | ![iPad runtime topology](docs/screenshots/ipad-topology.png) |

Additional checked states are stored in `docs/screenshots`: sign in, iPhone overview, iPhone topology and iPad overview.
