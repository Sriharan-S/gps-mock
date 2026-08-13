# 📍 GPS Mock

A Flutter-based Android app for mocking/spoofing GPS locations on your device. Select any location on the map — or simulate an entire trip between two places — and your device will report that position to all other apps. 🗺️

**100% free stack**: maps by OpenStreetMap, search by Photon, routing by OSRM — no API keys, no accounts, no credit card required for anything. Clone, build, run. 🆓

> **🌐 Built for testing "My Globe"** — GPS Mock is the official testing companion for [My Globe](https://github.com/Sriharan-S), a maps & navigation project (think Google Maps, built from scratch). Simulating positions, movement, speed and bearing with GPS Mock makes it possible to develop and test My Globe's navigation features from a desk — no driving required. It works just as well for testing any other location-based app.

## ✨ Features

### Core
- **🧭 Three-tab layout**: a persistent **Map**, a **Saved** locations list, and a **History** log — all from a bottom navigation bar
- **🗺️ Interactive Map**: Pick your mock location by panning/zooming the map — opens where you left off, or calibrated to your real position when mocking is off
- **🎨 Switchable map styles**: Standard, Humanitarian, Topographic, Satellite and Dark basemaps — all free and keyless
- **🧭 Compass**: rotate the map with two fingers; tap the compass to snap back to north
- **📌 Saved locations on the map**: favorites show as dots when zoomed out and as named pins when you zoom in
- **🔍 Smart Location Search**: Fast, typo-tolerant place search with named suggestions (powered by Photon/OpenStreetMap — no API key needed)
- **⭐ Favorites**: Save frequently used locations; selecting one jumps the map straight to it. Delete with undo
- **🕑 History**: Every mock session is logged — fixed spots and routes (from → to, distance, planned vs. actual duration, when started/arrived/ended) — including sessions started from tiles and widgets
- **⚡ Real-time Mocking**: Start/stop GPS mocking with a single tap; survives closing the app (foreground service with a Stop action in the notification)
- **🚨 Honest failure reporting**: if Android rejects the mock (e.g. GPS Mock isn't selected as the mock location app), a heads-up notification appears immediately — the app never pretends to mock when it isn't

### 🧭 Mock Navigation Movement
Simulate actually *travelling* a route — perfect for testing turn-by-turn navigation in My Globe:

1. Tap the **Directions** button (or switch the bottom panel to **Route**)
2. Pick a start and destination (search, favorites, or the map pin) — e.g. **Chennai → Salem** — and add **stops** in between if you like
3. GPS Mock fetches the real driving route (free [OSRM](http://project-osrm.org/) routing, no key needed) and shows it on the map with distance and a realistic duration
4. Choose how long the trip should take — either a **duration** in minutes, or an **"arrive by"** time/date (GPS Mock works out the pace)
5. **START ROUTE**: your device's GPS now moves along the actual roads with correct **speed and bearing**, arriving exactly on schedule

The simulation runs natively in the foreground service, so it keeps driving even if you close the app. Reopen anytime to see live progress, remaining time, and a camera-follow mode.

**📥 Import a GPX track or coordinate list** — instead of picking two points, tap **Import** in the Route panel and paste either the contents of a **GPX file** (`.gpx` tracks, routes or waypoints) or a plain **list of coordinates** (one `latitude, longitude` per line). GPS Mock draws the exact geometry on the map and simulates driving it — no routing service involved, so it follows your track precisely. If the GPX carries timestamps, the recorded trip duration is used as the default pace.

### 📟 Quick Settings Tiles
Add up to **4 tiles** (one per saved favorite) to your notification shade. Toggle a tile to instantly mock that location **without opening the app** — turning one on automatically turns the others off.

### 🧩 Home-Screen Widgets
- **Favorite toggle widget**: bind a widget to any saved location and toggle mocking right from your home screen
- **Route status widget**: shows the running mock route's remaining time, progress bar, and a periodically refreshed map snapshot of the simulated position

### 🎨 Quality of life
- Material Design 3 with automatic **light/dark theme** (including a dark basemap)
- Warning banner + guided setup when the app isn't selected as the mock location app (and no nagging when it already is)
- **Setup & permissions checklist** (overflow menu): mock location app, location, notifications, and battery-optimization exemption — with one-tap fixes
- Share the selected location as an OpenStreetMap link
- Tooltips, 48dp touch targets and screen-reader labels/announcements throughout

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

No API keys of any kind — the map, search, and routing all use free OpenStreetMap-based services.

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

3. Run the app:
   ```bash
   flutter run
   ```

4. Build release APK:
   ```bash
   flutter build apk --release
   ```

## 🚀 Usage

GPS Mock has three tabs on the bottom navigation bar: **Map**, **Saved**, and **History**.

### Fixed location
1. **📱 Launch the app** and grant location permissions when prompted
2. **🔓 Enable mock location** via the setup banner (only shown if not configured yet) — or run through the full **Setup & permissions** checklist from the overflow menu
3. **📍 Select a location** by panning/zooming the map or using the search bar
4. **▶️ Tap START MOCKING** to begin mocking your GPS location
5. **⏹️ Tap STOP MOCKING** (in the app or the notification) to return to your real GPS location

If Android ever refuses the mock (e.g. GPS Mock got deselected as the mock location app), you'll get an immediate notification telling you what's wrong and a button to fix it — the app never pretends to be mocking when it isn't.

### Mock navigation (route simulation)
1. Tap the **Directions** button, or switch the bottom panel to **Route**
2. Choose **start** and **destination** (search, favorites, or the current map pin) — add **stops** in between if needed
3. Review the route, then set the trip length: either a **duration in minutes**, or an **"arrive by"** time/date
4. **▶️ START ROUTE** — watch the mock position drive the route; other apps (like My Globe) see a moving GPS fix with real speed/bearing
5. On arrival the position holds at the destination until you stop; the camera-follow button keeps the map centered on the moving marker

#### Importing a route (GPX / coordinates)
1. Switch the bottom panel to **Route** and tap **Import**
2. Paste a **GPX** document (track, route or waypoints) or a **coordinate list** — one `latitude, longitude` per line (extra columns like elevation are ignored, `#`/`//` lines are treated as comments)
3. The route appears on the map with its distance and a suggested duration; adjust the duration or **arrive by** time as usual
4. **▶️ START ROUTE** simulates driving the imported path exactly — great for replaying a recorded trip or a route exported from another tool

### 💾 Saving favorites

1. Navigate to your desired location
2. Tap the **❤️ heart icon** in the control panel
3. Enter a name for the location
4. Tap **Save**

Open the **Saved** tab to see all your favorites (shown as a mini map + name), jump to one, or delete it (with undo). Saved locations also appear directly on the map — as small dots when zoomed out, and as named pins once you zoom in.

### 🕑 History

The **History** tab logs every mock session — fixed locations and simulated routes, including ones started from a quick-settings tile or a widget. Each entry shows where (or from → to), when it started, the planned vs. actual duration, and when it arrived/ended. Tap an entry to jump back to that location on the map.

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

- Built with [Flutter](https://flutter.dev/) and [flutter_map](https://pub.dev/packages/flutter_map)
- Map tiles © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors
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
