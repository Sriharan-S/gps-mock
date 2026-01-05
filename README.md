# GPS Mock

A Flutter-based Android app for mocking/spoofing GPS locations on your device. Select any location on the map, and your device will report that position to all other apps.

## Features

- **Interactive Map**: Use Google Maps to select your desired mock location by panning and zooming
- **Location Search**: Search for any address or place and jump directly to it
- **Favorites**: Save frequently used locations for quick access
- **Real-time Mocking**: Start/stop GPS mocking with a single tap
- **Material Design 3**: Modern dark-themed UI built with Flutter

## Prerequisites

Before using GPS Mock, you need to:

1. **Enable Developer Options** on your Android device:
   - Go to **Settings > About Phone**
   - Tap **Build Number** 7 times to enable Developer Options

2. **Set GPS Mock as the Mock Location App**:
   - Go to **Settings > Developer Options**
   - Find **Select mock location app**
   - Select **GPS Mock**

## Installation

### Download APK

Download the latest APK from the [Releases](../../releases) page.

### Build from Source

#### Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.5.0 or higher)
- [Android Studio](https://developer.android.com/studio) or [VS Code](https://code.visualstudio.com/) with Flutter extension
- Android SDK
- Google Maps API Key

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

## Usage

1. **Launch the app** and grant location permissions when prompted
2. **Enable mock location** by tapping "Open Settings" in the dialog (or manually set it in Developer Options)
3. **Select a location** by panning/zooming the map or using the search bar
4. **Tap START** to begin mocking your GPS location
5. **Tap STOP** to return to your real GPS location

### Saving Favorites

1. Navigate to your desired location
2. Tap the **heart icon** in the control panel
3. Enter a name for the location
4. Tap **Save**

Access your saved locations by tapping the **list icon** in the search bar.

## Open Source

GPS Mock is open source software released under the MIT License. You are free to use, modify, and distribute this software.

## Contributing

We welcome contributions from the community! Here's how you can help:

### Ways to Contribute

- **Report Bugs**: Found a bug? Open an [issue](../../issues) with details about the problem
- **Suggest Features**: Have an idea? Open an [issue](../../issues) to discuss it
- **Submit Pull Requests**: Fix bugs or add features by submitting a PR

### Getting Started

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

### Code Guidelines

- Follow the existing code style and conventions
- Write clear commit messages
- Test your changes before submitting
- Update documentation if needed

## License

This project is open source and available under the [MIT License](LICENSE).

## Acknowledgments

- Built with [Flutter](https://flutter.dev/)
- Maps provided by [Google Maps Platform](https://developers.google.com/maps)
- Geocoding by [geocoding](https://pub.dev/packages/geocoding) package
