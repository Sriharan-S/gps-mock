# 📍 GPS Mock

A Flutter-based Android app for mocking/spoofing GPS locations on your device. Select any location on the map — or simulate an entire trip between two places — and your device will report that position to all other apps. 🗺️

> **🌐 Built for testing "My Globe"** — GPS Mock is the official testing companion for [My Globe](https://github.com/Sriharan-S), a maps & navigation project (think Google Maps, built from scratch). Simulating positions, movement, speed and bearing with GPS Mock makes it possible to develop and test My Globe's navigation features from a desk — no driving required. It works just as well for testing any other location-based app.

## ✨ Features

### Core
- **🗺️ Interactive Map**: Pick your mock location by panning/zooming Google Maps — the app opens where you left off, or calibrated to your real position when mocking is off
- **🔍 Smart Location Search**: Fast, typo-tolerant place search with named suggestions (powered by Photon/OpenStreetMap — no API key needed)
- **⭐ Favorites**: Save frequently used locations; selecting one jumps the map straight to it. Delete with undo
- **⚡ Real-time Mocking**: Start/stop GPS mocking with a single tap; survives closing the app (foreground service with a Stop action in the notification)

### 🧭 Mock Navigation Movement
Simulate actually *travelling* a route — perfect for testing turn-by-turn navigation in My Globe:

1. Switch the bottom card to **Route** mode
2. Pick a start and destination (search, favorites, or the map pin) — e.g. **Chennai → Salem**
3. GPS Mock fetches the real driving route (free [OSRM](http://project-osrm.org/) routing, no key needed) and shows it on the map with distance and a realistic duration
4. Set **how long the trip should take** (prefilled with the realistic estimate — shorten it to fast-forward)
5. **START ROUTE**: your device's GPS now moves along the actual roads with correct **speed and bearing**, arriving exactly when the timer ends

The simulation runs natively in the foreground service, so it keeps driving even if you close the app. Reopen anytime to see live progress, remaining time, and a camera-follow mode.

### 📟 Quick Settings Tiles
Add up to **4 tiles** (one per saved favorite) to your notification shade. Toggle a tile to instantly mock that location **without opening the app** — turning one on automatically turns the others off.

### 🧩 Home-Screen Widgets
- **Favorite toggle widget**: bind a widget to any saved location and toggle mocking right from your home screen
- **Route status widget**: shows the running mock route's remaining time, progress bar, and a periodically refreshed map snapshot of the simulated position

### 🎨 Quality of life
- Material Design 3 with automatic **light/dark theme** (including a dark map style)
- Warning banner + guided setup when the app isn't selected as the mock location app (and no nagging when it already is)
- Share the selected location as a Google Maps link
- Tooltips, larger touch targets and screen-reader labels throughout

## 📋 Prerequisites

Before using GPS Mock, you need to:

1. **🔧 Enable Developer Options** on your Android device:
   - Go to **Settings > About Phone**
   - Tap **Build Number** 7 times to enable Developer Options

2. **📱 Set GPS Mock as the Mock Location App**:
   - Go to **Settings > Developer Options**
   - Find **Select mock location app**
   - Select **GPS Mock**

The app detects this automatically and only shows the setup guide when it's actually needed.

## 💾 Installation

### 📥 Download APK

Download the latest APK from the [Releases](../../releases) page.

### 🔨 Build from Source

#### Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.5.0 or higher)
- [Android Studio](https://developer.android.com/studio) or [VS Code](https://code.visualstudio.com/) with Flutter extension
- Android SDK
- Google Maps API Key (only for the map view — search and routing are keyless)

#### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Sriharan-S/gps-mock.git
   cd gps-mock
   ```

2. Get dependencies:
   ```bash
   flutter pub get
   ```

3. Add your Google Maps API Key:
   - In `android/app/src/main/AndroidManifest.xml`, replace `API_KEY_PLACEHOLDER` with your API key
   - In `lib/utils/constants.dart`, replace `API_KEY_PLACEHOLDER` with your API key

4. Run the app:
   ```bash
   flutter run
   ```

5. Build release APK:
   ```bash
   flutter build apk --release
   ```

## 🚀 Usage

### Fixed location
1. **📱 Launch the app** and grant location permissions when prompted
2. **🔓 Enable mock location** via the setup banner (only shown if not configured yet)
3. **📍 Select a location** by panning/zooming the map or using the search bar
4. **▶️ Tap START** to begin mocking your GPS location
5. **⏹️ Tap STOP** (in the app or the notification) to return to your real GPS location

### Mock navigation (route simulation)
1. Switch the bottom card to **Route**
2. Choose **start** and **destination** (defaults offer the current pin and your favorites)
3. Review the route, set the trip **duration in minutes**
4. **▶️ START ROUTE** — watch the mock position drive the route; other apps (like My Globe) see a moving GPS fix with real speed/bearing
5. On arrival the position holds at the destination until you stop

### 💾 Saving favorites

1. Navigate to your desired location
2. Tap the **❤️ heart icon** in the control panel
3. Enter a name for the location
4. Tap **Save**

Access your saved locations by tapping the **📋 list icon** in the search bar.

### 📟 Quick settings tiles
1. Save at least one favorite
2. Open the notification shade → tap the ✏️ edit button → drag the **GPS Mock favorite 1–4** tiles into your quick settings
3. Tiles map to your first four favorites (in list order) and show their names
4. Tap to mock / tap again to stop — no need to open the app

### 🧩 Widgets
Long-press your home screen → **Widgets** → **GPS Mock**:
- **Favorite toggle** — pick which saved location it controls when placing it
- **Mock route status** — shows live progress whenever a route simulation is running

## 🌟 Open Source

GPS Mock is open source software released under the MIT License. You are free to use, modify, and distribute this software. ✨

## 🤝 Contributing

We welcome contributions from the community! Here's how you can help:

### 💡 Ways to Contribute

- **🐛 Report Bugs**: Found a bug? Open an [issue](../../issues) with details about the problem
- **💭 Suggest Features**: Have an idea? Open an [issue](../../issues) to discuss it
- **🔧 Submit Pull Requests**: Fix bugs or add features by submitting a PR

### 🚀 Getting Started

1. Fork the repository
2. Create a new branch for your feature or fix:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. Make your changes and commit them:
   ```bash
   git commit -m "Add your descriptive commit message"
   ```
4. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
5. Open a Pull Request against the `main` branch

### 📝 Code Guidelines

- Follow the existing code style and conventions
- Write clear commit messages
- Test your changes before submitting
- Update documentation if needed

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- Built with [Flutter](https://flutter.dev/)
- Maps provided by [Google Maps Platform](https://developers.google.com/maps)
- Place search by [Photon](https://photon.komoot.io/) (OpenStreetMap)
- Routing by [OSRM](http://project-osrm.org/) (OpenStreetMap)
- Geocoding by [geocoding](https://pub.dev/packages/geocoding) package

## ⚠️ Disclaimer

**IMPORTANT: Please read before using this app**

This application is intended for **educational and testing purposes only** — first and foremost as the location-simulation test bench for the **My Globe** maps & navigation project. GPS mocking/spoofing can be used for:
- Testing location-based apps during development (like My Globe's navigation features)
- Privacy protection in controlled scenarios
- Educational demonstrations

**⚠️ Users are solely responsible for how they use this app.** The developers assume no liability for misuse. Please be aware that:

- Using GPS mocking to deceive or defraud others is **illegal** in many jurisdictions
- Many apps and services have terms of service that **prohibit** location spoofing
- Violating these terms may result in account suspension or legal consequences
- Some uses (e.g., gaming, ride-sharing fraud, location-based dating deception) may be **unethical and/or illegal**

**Use this app responsibly and in accordance with all applicable laws and terms of service.**
