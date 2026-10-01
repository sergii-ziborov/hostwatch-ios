# App Store submission — Hostwatch 1.0.9 (19)

Updated 2026-10-01. Build 19 is in the internal TestFlight group; Apple has not approved or published a public App Store release.

## Internal TestFlight status

- Version **1.0.9 (19)** reflows Code health and Cleanup on iPhone: titles and descriptions use the available width, long coverage text sits below the project name, Markdown actions do not split, and Cleanup's scan message stays in one panel. The release archive was built on stable Xcode, signed, validated and uploaded on 2026-10-01. Apple reports `VALID` and `IN_BETA_TESTING`; assignment to **Hostwatch Internal** was verified. Physical-device verification remains pending.
- Version **1.0.9 (18)** removes the duplicate custom `Updating…` indicator during pull-to-refresh, prevents a second manual reload while one is running, and clears an earlier error when the user retries. It was archived on stable Xcode, signed, validated and uploaded on 2026-10-01. Apple reports `VALID` processing and `IN_BETA_TESTING`; assignment to **Hostwatch Internal** was verified through App Store Connect. Physical-device verification of this build remains pending.
- Version **1.0.9 (17)** was archived by GitHub Actions with stable **Xcode 26.6**, signed for App Store distribution, validated and uploaded on 2026-10-01. The exported IPA's signed entitlements include `applinks:gethostwatch.com`.
- Apple reports processing state `VALID`, internal state `IN_BETA_TESTING` and `USES-NON-EXEMPT-ENCRYPTION: false`.
- Build 17 is assigned to the **Hostwatch Internal** group. Its “What to Test” note asks testers to inspect a site's normal and peak memory limits, overflow warning, and persisted edits while checking that other resource limits remain intact.
- TestFlight should offer build 19 as an update to internal testers. Its behavior on a physical device still needs confirmation.
- The label placement was inspected in simulator Debug fixture captures in both modes. These images are development evidence, not App Store screenshots.
- The primary node now includes the `weavatrix-hosted` project and scheduled code-health scan. The first report contains 11 modules, 10 communities and 5,504 graph nodes. Its status is `PARTIAL` because the deployed repository has no measured coverage report.

The GitHub Actions archive is intentionally unsigned. Before exporting it locally, sign the archived app with the distribution profile and expanded entitlements: the profile's app/team identifiers plus `applinks:gethostwatch.com` from `Hostwatch.entitlements`. Exporting an unsigned archive directly omits Associated Domains from the IPA. Verify the final IPA's signature includes the domain before Apple validation. Keep the signing certificate, profile and API key outside Git.

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

Code health now presents its heading, Markdown actions and long project status without narrow columns or broken words. Cleanup keeps its description full width and displays scan progress in one aligned panel. The previous build removed the duplicate pull-to-refresh indicator.

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
- [x] Version 1.0.9 (19), shared archive scheme, iPhone/iPad targets.
- [x] Custom QR URL scheme and associated-domain entitlement in release source.
- [x] Privacy manifest and accessible Privacy/Terms/Support links.
- [x] Parser/session API test coverage; build 17's simulator suite passed 43 tests with one optional test skipped. Earlier candidates passed additional targeted checks, including mixed HTTP errors and Runtime labels.
- [ ] Physical QR scan, biometric unlock and eight-hour-expiry renewal on the candidate.
- [x] Distribution provisioning with Associated Domains; build 17 archived using stable Xcode 26.6, signed, validated and uploaded. The final IPA signature contains the domain entitlement, and Apple recognized its export-compliance flag.
- [x] Build 17 assigned to the internal TestFlight group. Physical-device verification of this build remains pending.
- [x] Build 18 assigned to the internal TestFlight group. Apple reports `VALID` and `IN_BETA_TESTING`; physical-device verification remains pending.
- [x] Build 19 assigned to the internal TestFlight group. Apple reports `VALID` and `IN_BETA_TESTING`; iPhone simulator layout inspection passed, physical-device verification remains pending.
- [ ] Authenticated iPhone/iPad screenshots and dedicated reviewer account.
- [ ] Store privacy, age rating and export-compliance forms completed and verified.
- [ ] App Review submission and approval; public release remains manual.

The local development profile used for device installation does not include Associated Domains. Installation used a local signing override; the repository keeps the release entitlement. The custom URL scheme works independently of that entitlement.

Reference: [App Review](https://developer.apple.com/app-store/review/), [account deletion requirements](https://developer.apple.com/support/offering-account-deletion-in-your-app), [app privacy details](https://developer.apple.com/app-store/app-privacy-details/).
