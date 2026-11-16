# Drainage Guard Field app: run it from VS Code, step by step

The Flutter app, the web worker app (`worker.html`) and the website (`dashboard.html`) all connect to the **same HiveMQ broker** and use the **same report format**. A report sent from the Flutter app appears on the website within a second, and the reverse also works.

```
Flutter app (phones) ──┐
worker.html (judges) ──┼──► HiveMQ broker ──► dashboard.html (website, "Field reports" panel)
ESP32 sensor ──────────┘
```

> **Time warning:** the first-time Flutter install downloads about 3–5 GB. Do Part A **today**, on good Wi-Fi.
> If anything blocks you before the pitch, `worker.html` does the same job in a phone browser, so you still have a working demo.

---

## Part A: One-time install (about 1–2 hours, mostly downloading)

**A1. Install Git:** https://git-scm.com/download/win (accept the defaults).

**A2. Install the Flutter SDK**
1. Go to https://docs.flutter.dev/get-started/install/windows/mobile and download the Flutter SDK zip.
2. Unzip it to `C:\src\flutter`. **Not** inside `Program Files`, and no spaces in the path.
3. Add Flutter to PATH: press Start, type **"environment variables"**, open **Edit environment variables for your account**, select **Path** → **Edit** → **New**, type `C:\src\flutter\bin`, then OK.
4. Close and reopen any terminals.

**A3. Install Android Studio** (it provides the Android SDK, even though you'll code in VS Code)
1. Download it from https://developer.android.com/studio and install with the defaults.
2. Open it once and let the **Setup Wizard** download the Android SDK.
3. In Android Studio go to **More Actions → SDK Manager → SDK Tools tab**, tick **Android SDK Command-line Tools**, then Apply.

**A4. Accept the Android licences and check everything.** Open **Command Prompt** and run:
```
flutter doctor --android-licenses
flutter doctor
```
Press `y` for every licence. `flutter doctor` should show ✓ for **Flutter**, **Android toolchain** and **VS Code**. A ✗ for Visual Studio (C++) or Chrome doesn't matter for this app.

**A5. VS Code extensions:** open VS Code → Extensions (Ctrl+Shift+X) → install **Flutter** (by Dart Code). This also installs the Dart extension.

---

## Part B: Create the project and add our code (10 minutes)

**B1. Create a blank Flutter project.** In Command Prompt:
```
cd %USERPROFILE%\Documents
flutter create --org za.ac.cut --platforms android smartdrain_field
```
This makes the Android build files that match your Flutter version, which is why we don't copy those.

**B2. Copy our files over the blank ones.** From the `smartdrain_field` folder in the zip, copy these into `Documents\smartdrain_field`, and choose **Replace** when Windows asks:

| Copy this from the zip | Into the new project |
| --- | --- |
| `pubspec.yaml` | `smartdrain_field\pubspec.yaml` |
| the whole `lib` folder | `smartdrain_field\lib` (replace it) |
| `android\app\src\main\AndroidManifest.xml` | `smartdrain_field\android\app\src\main\AndroidManifest.xml` |

Delete `smartdrain_field\test\widget_test.dart`. It tests the default counter app and would show errors.

**B3. Open it in VS Code:** File → Open Folder → `Documents\smartdrain_field`.

**B4. Download the packages.** In VS Code: Terminal → New Terminal, then run:
```
flutter pub get
```
It should end with `Got dependencies!`.

**B5. Put in the broker details.** Open `lib/config.dart` and fill in the cluster URL and the **worker** credential from HiveMQ (Access Management):
```dart
static const String brokerHost = 'abc123def.s1.eu.hivemq.cloud';
static const String brokerUser = 'sdg-worker';
static const String brokerPassword = 'your-password';
```
Every phone you install the app on then connects automatically. Workers only type their name.

---

## Part C: Run it on your phone (15 minutes)

**C1. Turn on Developer mode** on the Android phone: Settings → About phone → tap **Build number** 7 times.
**C2.** Settings → **Developer options** → turn on **USB debugging**.
**C3.** Plug the phone into the laptop with a USB cable. On the phone, tap **Allow** on the "Allow USB debugging?" pop-up.
**C4.** In VS Code, look at the bottom-right status bar: click the device name and pick your phone. Or run `flutter devices` in the terminal to check it's listed.
**C5.** Press **F5** (Run → Start Debugging). The first build takes 3–8 minutes; later runs take seconds. The app opens on the phone.
**C6.** In the app: go to **Settings**, enter your name and team, then tap **Save and connect**. The chip at the top should turn green: **Online**.

**No Android phone or cable?** Use an emulator instead: Ctrl+Shift+P → **Flutter: Launch Emulator** → **Create Android Emulator**, then press F5. GPS works with the emulator's fake location, and the camera shows a test scene. Use **Gallery** for photos.

**While coding:** save a file and press **r** in the terminal (or the ⚡ hot-reload button) to see changes instantly without rebuilding.

---

## Part D: Test it end to end with the website

1. Open `dashboard.html` (from the earlier kit) on the laptop → **Connect broker** → cluster URL, port `8884`, path `/mqtt`, the `sdg-dashboard` login, topic `sdg/#`.
2. On the phone: **Report** → Blocked → take a photo → **Send report to team**.
3. The report appears on the dashboard under **Field reports from workers**, with the photo and an **Open in Maps** link.
4. Open `worker.html` on a second phone and tap **On my way** on that report. The Flutter app's Jobs tab updates to "On the way", and so does the dashboard.

**Put the website online** so it isn't just a file on your laptop: go to **app.netlify.com/drop**, drag the folder containing `dashboard.html` and `worker.html`, and you get a public https link to use on the big screen.

---

## Part E: Make an APK to install on other phones (team, demo phone)

```
flutter build apk --release
```
The file is at `build\app\outputs\flutter-apk\app-release.apk`. Send it on WhatsApp or by USB, open it on the phone and allow **Install unknown apps** when asked. This test build is signed with a debug key, which is fine for demos but not for the Play Store.

---

## Troubleshooting

| What you see | Fix |
| --- | --- |
| `'flutter' is not recognized` | PATH not set (A2 step 3), or the terminal was open before you changed it. Close and reopen VS Code. |
| `flutter doctor`: Android licences ✗ | Run `flutter doctor --android-licenses` and press `y` to everything. |
| `cmdline-tools component is missing` | Step A3.3 (SDK Manager → SDK Tools → Android SDK Command-line Tools). |
| Phone not listed in `flutter devices` | Use a data USB cable (some only charge), accept the USB debugging pop-up, and set the USB mode to **File transfer**. |
| Build error mentioning `compileSdk`, `minSdk` or `geolocator` | In `android/app/build.gradle` (or `build.gradle.kts`), inside `defaultConfig`, set `minSdk = 21`. If it asks for compileSdk 34/35, set `compileSdk = 35` in the `android {}` block. Then run `flutter clean` and `flutter pub get` and press F5 again. |
| Error about the Kotlin or Gradle version | Run `flutter upgrade`, delete the project, and redo Part B. A fresh `flutter create` uses matching versions. |
| `version solving failed` on `flutter pub get` | Your Flutter is older than 3.22. Run `flutter upgrade`. |
| App says **No connection** | The settings must say port **8883** (not 8884, which is the website's), and the URL has no `https://`. Check the username and password in HiveMQ Access Management, and that the credential has **Publish and Subscribe**. The red "Last error" line in Settings shows the reason. |
| App connects, but reports don't reach the website | The dashboard's topic must be `sdg/#` (or it must at least subscribe to `sdg/report/#`). Re-check the dashboard's Connect dialog. |
| Location never arrives | Turn on phone location, allow the app's location permission, step outside, then tap refresh ⟳. You can always type the street instead. |
| Camera button does nothing on the emulator | Use **Gallery**, or test on a real phone. |

**If you get stuck,** copy the red error text from the VS Code terminal and send it to me. Most first-build errors are one-line Gradle fixes.

---

## How the app is organised (for the judges' "how did you build it?" question)

| File | What it does |
| --- | --- |
| `lib/config.dart` | Broker address and login, pre-filled for all phones |
| `lib/models/report.dart` | The report data: type, urgency, GPS, photo, status history. Same JSON as the website. |
| `lib/services/report_service.dart` | Secure MQTT connection (TLS, port 8883), auto-reconnect, live report sync, offline queue |
| `lib/screens/report_screen.dart` | Report form: problem type, GPS, landmark, camera photo, urgency, notes |
| `lib/screens/jobs_screen.dart` | Team jobs sorted by urgency and distance: Directions, On my way, Cleared, WhatsApp share |
| `lib/screens/settings_screen.dart` | Worker name, team and connection details |

Security points to mention: the connection is encrypted (TLS). Workers' logins can only send and read reports, never sensor data. Reports contain no residents' personal information.
