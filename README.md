# Hostwatch for iPhone and iPad

Native SwiftUI control-plane client for Hostwatch. It uses the same signed-in session and REST API as the web application. There is no public demo or registration flow.

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

All app screens use SwiftUI, SceneKit, MapKit and direct JSON API calls. There are no embedded web pages, WebViews or bundled HTML assets. No CI/CD workflow is included. Release signing and distribution are intentionally manual.

To run on a physical iPhone, open `Hostwatch.xcodeproj` in Xcode, select the Hostwatch target, choose your Apple development team under Signing & Capabilities, then select the device. A signed device build requires that team's provisioning profile; the simulator build above does not.

## Verified layouts

| iPhone traffic | iPad runtime topology |
| --- | --- |
| ![iPhone traffic](docs/screenshots/iphone-traffic.png) | ![iPad runtime topology](docs/screenshots/ipad-topology.png) |

Additional checked states are stored in `docs/screenshots`: sign in, iPhone overview, iPhone topology and iPad overview.
