# App Store submission — Hostwatch 1.0.7 (12)

Updated 2026-09-30. These are submission materials, not a claim that Apple approved or published the app.

## Listing

- Name: Hostwatch
- Subtitle: Infrastructure in your pocket
- Category: Developer Tools
- Copyright: 2026 Sergii Ziborov
- Bundle: `com.hostwatch.controlplane`
- Privacy URL: https://gethostwatch.com/privacy
- Support URL: https://gethostwatch.com/support
- Terms: https://gethostwatch.com/terms
- Keywords: server,monitoring,infrastructure,traffic,docker,logs,operations

Description:

Hostwatch brings your organization's infrastructure control plane to iPhone and iPad. Inspect host resources, HTTP traffic, failures, databases and caches, project workloads and runtime connections through a native interface. Open retained requests and available log context, export error evidence to Files, and manage configured operational controls with your organization's permissions.

Sign in with your provisioned account or pair the app from an already signed-in website. A signed-in app can approve a website sign-in after comparing a one-time verification code. Face ID, Touch ID or the device passcode protects saved authorization locally. Shared environment settings and encrypted secrets can be assigned to multiple configured projects.

Requires access to a Hostwatch control plane. No public account registration, embedded website, advertising, tracking or in-app purchasing is included. Runtime health depends on the connected node and available collectors; missing evidence is shown as unavailable.

What's new:

Overview now loads when a site has no containers, and an incompatible server response identifies its affected field. SSL / TLS shows local certificate validity, served origin and public HTTPS, and the existing Certbot renewal schedule for each managed site. Organization owners can request a renewal check when due; the operation continues on the server. Password and authenticator feedback, QR pairing, error export, shared settings and policy links remain available.

## Reviewer instructions

Provide a dedicated account, password and any second-factor instructions privately in App Store Connect. Never commit review passwords or customer secrets. Provision representative telemetry in a review organization and keep its control plane available throughout review.

1. Open the app; keep the supplied control-plane address.
2. Sign in with the dedicated review account. Check Overview, Traffic, Database and Runtime.
3. Open More → Errors, select a project and export evidence to Files.
4. In Account security, enable local biometric protection on a supported device.
5. QR app sign-in starts on an already authenticated website under Organization → Account security → Sign in on iPhone or iPad. Website sign-in approval starts on the website's sign-in page and requires an already authenticated app. Compare the six-digit numbers before approval.

Organization owners provision accounts. The app has no public sign-up or third-party social login. Describe this accurately during review; do not claim account deletion is implemented. If in-app account creation is added later, implement in-app deletion before submission.

## Privacy and compliance

The bundled `PrivacyInfo.xcprivacy` declares the UserDefaults reason CA92.1 and account/operational data used for app functionality, linked to the organization account, without tracking. Reconcile the final App Store privacy questionnaire with the live control plane, including user-entered content, log data and network addresses. No location permission is requested; approximate visitor geography belongs to server telemetry. Camera permission is only for QR scanning. Face ID is evaluated by LocalAuthentication; biometric templates never reach Hostwatch.

The iOS source uses Apple's URLSession for HTTPS, Security framework Keychain, and CryptoKit AES-GCM to create encrypted environment-share links. It contains no third-party or proprietary cryptography. Apple's [export compliance reference](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/) says encryption limited to Apple's operating system requires no documentation in App Store Connect. Build 12 sets `ITSAppUsesNonExemptEncryption` to `false` in Info.plist on that basis. Recheck this declaration if cryptography changes. The app's source-available commercial LICENSE is separate from Apple's user EULA.

## Screenshots

Capture actual authenticated data from the Release candidate on iPhone and iPad. Do not submit debug fixtures, reconstructed screens or unverified historical screenshots. Redact operational secrets at the source, by using a provisioned review organization. Required device dimensions follow [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

Suggested captures: Overview with time axis, Traffic and request destination, Errors with export, Runtime, and Account security. Sign-in captures can complement these but cannot demonstrate authenticated functionality by themselves.

## Release gates

- [x] Native SwiftUI client, camera/Face ID usage descriptions and app icon.
- [x] Version 1.0.7 (12), shared archive scheme, iPhone/iPad targets.
- [x] Custom QR URL scheme and associated-domain entitlement in release source.
- [x] Privacy manifest and accessible Privacy/Terms/Support links.
- [x] Parser/session API test coverage; the 40-test native suite passed with one optional live sign-in test skipped for the previous candidate. The new empty-site decoding test and simulator build passed for this candidate. A full rerun was stopped after simulator launch failures.
- [ ] Physical QR scan, biometric unlock and eight-hour-expiry renewal on the candidate.
- [x] Distribution provisioning with Associated Domains; build 11 signed and validated by Apple after stable Xcode 26.6 archive. Build 12 must be validated after adding the export-compliance flag.
- [ ] Build 12 uploaded and available to the internal TestFlight group.
- [ ] Authenticated iPhone/iPad screenshots and dedicated reviewer account.
- [ ] Store privacy, age rating and export-compliance forms completed and verified.
- [ ] App Review submission and approval; public release remains manual.

The local development profile used for device installation does not include Associated Domains. Installation used a local signing override; the repository keeps the release entitlement. The custom URL scheme works independently of that entitlement.

Reference: [App Review](https://developer.apple.com/app-store/review/), [account deletion requirements](https://developer.apple.com/support/offering-account-deletion-in-your-app), [app privacy details](https://developer.apple.com/app-store/app-privacy-details/).
