# Android public configuration and upload signing

The application ID remains `vn.homemind.homemind_mobile`; versionName/versionCode
come from `pubspec.yaml` (`1.0.0` / `1`). Do not change them for a signing test.

## Public configuration boundary

| Setting | Classification | Destination |
|---|---|---|
| BACKEND_BASE_URL | PUBLIC CLIENT CONFIG | Dart define/public JSON |
| Database URLs/passwords, AUTH_*_SECRET | PRIVATE SERVER SECRET | Backend ignored .env.local |
| GEMINI_API_KEY and other provider keys | PRIVATE SERVER SECRET | Backend ignored .env.local |
| ANDROID_UPLOAD_* passwords/private keystore | PRIVATE SIGNING MATERIAL | Local protected directory/CI secret store |

The app does not read or package `.env`. Never put private credentials in
`--dart-define`, JSON public configs, resources, BuildConfig or manifest metadata.
The Android build accepts only BACKEND_BASE_URL as application config, validates
the URL and rejects .env assets/private credential patterns in production sources.
Flutter framework version/build defines are allowed separately.

```powershell
adb -s <device-id> reverse tcp:3000 tcp:3000
flutter run -d <device-id> --dart-define-from-file=config/development.json
flutter build apk --debug --dart-define-from-file=config/development.json
```

Debug uses Android Debug signing and permits local HTTP. Release requires HTTPS;
URLs with username/password, query or fragment are rejected. The checked-in
`config/release.example.json` uses `https://api.example.com/v1` as a **placeholder**.
Replace it with the real public HTTPS endpoint for a production build. A signed
bundle with the placeholder proves signing/packaging, not service availability.

## Upload key and environment

The dedicated local upload key is outside the repository. This task created
RSA-4096/SHA256withRSA material with a 10,000-day validity, alias stored in the
protected local signing configuration. No passwords or personal paths are in Gradle.

Required environment variables:

```text
ANDROID_UPLOAD_STORE_FILE
ANDROID_UPLOAD_STORE_PASSWORD
ANDROID_UPLOAD_KEY_ALIAS
ANDROID_UPLOAD_KEY_PASSWORD
```

On this Windows workstation, a protected permanent configuration is available at
`$env:USERPROFILE\.homemind\signing\upload-signing.json`, beside
`homemind-upload.jks`. Load it into the current process without printing its values:

```powershell
$signingConfig = Get-Content -LiteralPath (Join-Path $env:USERPROFILE '.homemind\signing\upload-signing.json') | ConvertFrom-Json
foreach ($setting in $signingConfig.PSObject.Properties) {
  [Environment]::SetEnvironmentVariable($setting.Name, [string]$setting.Value, 'Process')
}
try {
  flutter build appbundle --release --dart-define=BACKEND_BASE_URL=https://api.example.com/v1
  if ($LASTEXITCODE -ne 0) { throw 'Release build failed' }
} finally {
  foreach ($setting in $signingConfig.PSObject.Properties) {
    [Environment]::SetEnvironmentVariable($setting.Name, $null, 'Process')
  }
  $signingConfig = $null
}
```

Use your actual HTTPS endpoint instead of the example. CI should inject the same
four variables from its secret store and keep the keystore outside the checkout.
Release never falls back to debug signing: missing/inaccessible signing material,
wrong passwords/alias, a key inside the repository or an Android Debug certificate
fail before release compilation. Debug builds require no upload variables.

This is an **upload key**, not a claim that the application is enrolled in Google
Play. In Play App Signing, the upload certificate verifies the developer's upload;
Google's app-signing key signs distributed APKs. Keep those certificate identities
separate. See [Android app signing](https://developer.android.com/studio/publish/app-signing)
and [Flutter Android release](https://docs.flutter.dev/deployment/android).

## Verify the final artifacts

Normal outputs are `build/app/outputs/flutter-apk/app-debug.apk` and
`build/app/outputs/bundle/release/app-release.aab`. Scan every ZIP entry, including
compiled Dart/native libraries, against current and previously exposed private
secret values in secure memory. Include UTF-16/base64 variants and strong API-key,
private-key and credential-bearing database URL patterns. Print match labels/counts,
never secret values. `.env` assets and known private matches must be zero.

Inspect the actual signer, not just the Gradle build type:

```powershell
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
jarsigner -verify build/app/outputs/bundle/release/app-release.aab
apksigner verify --print-certs build/app/outputs/flutter-apk/app-debug.apk
```

Compare the AAB certificate SHA-256 with the certificate in your upload keystore.
They must match, differ from the debug APK certificate and have a non-debug subject.
Self-signed upload certificates are expected; do not interpret the absence of a
public CA chain as an Android signing error. Check the merged release manifest for
debuggable/testOnly/cleartext/debug network overrides.

## Preserve the key; rotate exposed provider credentials

Securely back up **both the keystore and its password configuration**, preferably
with encrypted offline storage and access restricted to release owners. They are
permanent signing material, not temporary test files. No automatic cloud backup,
transmission, Play upload or Git commit is performed by this workflow.

The Gemini credential previously shipped in app/Git history requires owner-side
revocation/regeneration in the provider console. Removing it from today's artifact
does not make the old key safe. Put its replacement only in backend .env.local.
Current locally generated DB/auth secrets have no observed exposure and remain
protected; historical demo/default credentials are development fixtures and must
not become production accounts. Git history is preserved, not rewritten.
