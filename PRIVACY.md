# Hostwatch iOS privacy policy

Effective September 13, 2026. Contact: [serhii.ziborov@gmail.com](mailto:serhii.ziborov@gmail.com).

Hostwatch is an infrastructure control-plane client for organizations. The iPhone and iPad app connects to the control-plane URL supplied by your organization. Depending on your deployment, the control plane is operated by Hostwatch (managed edition) or by your organization (self-hosted enterprise edition). Your organization's administrator determines which servers, accounts and operational records are connected.

## Data used by the app

- **Account and authentication:** The service processes your name, email address, role, sign-in attempts and session information to grant access. Passwords and authenticator codes are sent to the selected control plane over HTTPS. The app uses session cookies for authentication. QR pairing uses a short-lived ticket and confirmation code. Face ID or the device passcode can confirm an approval and, if you enable app unlock, unlock an existing session locally; the app does not receive your biometric data.
- **Infrastructure and request evidence:** An authorized account can view host and service metrics, project names, processes, storage, incidents, request paths, HTTP status and timing, client IP addresses, approximate network-derived locations, referrer information and user agents collected by the organization's control plane and agent. Privileged actions such as a traffic rule or job execution are sent to that control plane and may be audited there.
- **Device permissions:** Camera access is requested only to scan a sign-in QR code. The app does not request device location. Maps display approximate locations derived by the control plane from network requests; they are not the iPhone's location.
- **Local settings:** The control-plane URL and optional app-unlock preference are saved on your device. The app uses the system's cookie storage for its session. It does not contain an advertising SDK or third-party analytics SDK.

The service uses this information to authenticate users, display and investigate infrastructure activity, apply authorized controls, protect accounts and maintain operational audit records. It does not sell personal data or use the app for advertising. Network service providers and the hosting provider for a managed control plane may process data to deliver the service; for a self-hosted installation, your organization manages its own hosting and retention.

## Retention and choices

Individual request evidence is kept in a bounded in-memory buffer at the control plane, while normalized historical aggregates and audit records can be retained under the organization's deployment and retention settings. Request query strings and request or response bodies are not collected for the traffic views. Account records persist while your organization maintains access; server-side retention varies by installation and contract. Signing out ends the app session, but does not erase organizational operational history.

To request access, correction, deletion, or removal of an account, contact your organization's administrator. If Hostwatch operates your managed control plane, you may also email [serhii.ziborov@gmail.com](mailto:serhii.ziborov@gmail.com), identifying your organization. We will route or handle the request according to the deployment agreement. The app does not offer self-service registration.

We may update this policy when the product or data handling changes. The effective date above identifies the current version.
