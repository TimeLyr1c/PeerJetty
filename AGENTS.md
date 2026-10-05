# Project rules

Read Docs/development-plan.md and README.md before changing behavior. Preserve the Original source baseline. Never use SSH or auto-open received files in the new app. Credentials, certificates with private keys, device trust records, actual transfers and build outputs must stay out of Git.

Use system TLS and CryptoKit; changes to pairing require adversarial tests. Validate paths before writing and never overwrite existing received files. A transfer succeeds only after receiver integrity checks and final commit. Keep smoke tests isolated from production Keychain/configuration and explain real-device coverage honestly.

SwiftPM owns build/test configuration. Install the app at a stable Applications path after verification. Update each computer's management archive only with that computer's verified state. The project owner reports that they and the Starter author agreed to MIT licensing; the root LICENSE and LICENSE-NOTES.md record that decision. Preserve Original unchanged. Existing icon provenance and any third-party terms still need verification or replacement before public redistribution; do not treat a source license agreement as third-party artwork permission.
