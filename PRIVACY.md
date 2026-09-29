# Hostwatch Privacy

Hostwatch is an infrastructure control plane operated by Sergii Ziborov for managed installations, or by your organization for enterprise installations. Your administrator chooses the servers and operational records connected to it.

The service processes account email, name, role, hashed passwords, session credentials and security audit events to provide access. Infrastructure records may include host metrics, logs, request paths, status codes, IP addresses and approximate locations. Environment secrets are encrypted at rest in the control-plane shared store and agent vault; applying a secret writes it to the configured server environment. Access is limited by organization and role.

The iPhone/iPad app stores session credentials in the device keychain. Short sessions are renewed using a revocable device credential, valid for up to 90 days since renewal. Sign-out removes the local credential and revokes it on the server; password changes revoke existing credentials. Face ID and device passcodes are checked by iOS: Hostwatch never receives biometric data. Camera access is only used for QR scanning; frames are not uploaded. No device GPS access or advertising tracking is used.

Operational exports are created only when you choose export. Copies you save or share remain in the selected destination. Temporary export files are removed when the sharing screen closes. Service retention and backups are controlled by your deployment and organization agreement. Contact your administrator or serhii.ziborov@gmail.com for access, correction, deletion or retention requests. We do not sell personal data. Changes to this policy are published here.
