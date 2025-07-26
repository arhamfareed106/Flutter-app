# SOS Auto - Client Application

SOS Auto is a Flutter-based mobile application designed to connect users with car trouble to nearby technicians for quick and reliable roadside assistance.

## 🚀 Features

This application comes packed with features to ensure a seamless experience for users in need of help:

-   **Authentication**: Secure sign-up and login using Email/Password and Phone Number Verification.
-   **Real-time Location Services**: Find and track nearby technicians using Google Maps integration.
-   **Firestore Database**: All data is stored and synced in real-time using Cloud Firestore.
-   **Firebase Storage**: For handling file uploads and downloads, such as vehicle documents or photos of the issue.
-   **Push Notifications**: Get instant updates on your service request status.
-   **Real-time Chat**: Communicate directly with your assigned technician.
-   **Camera & Photo Library Access**: Easily upload photos of your vehicle's problem.
-   **Multi-platform**: Fully compatible with iOS, Android, and Web.

## 📋 Prerequisites

Before you begin, ensure you have the following installed:
-   [Flutter SDK](https://flutter.dev/docs/get-started/install)
-   A code editor like [VS Code](https://code.visualstudio.com/) or [Android Studio](https://developer.android.com/studio).
-   For iOS development: [Xcode](https://developer.apple.com/xcode/)
-   For Android development: [Android Studio](https://developer.android.com/studio) and Android SDK.

## ⚙️ Getting Started

1.  **Clone the repository:**
    ```bash
    git clone <your-repository-url>
    cd sos_auto
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Firebase Setup:**
    This project uses Firebase for its backend services. You will need to set up your own Firebase project.

    -   **Android**:
        1.  Create a new Android app in your Firebase project with the package name `com.sos.auto`.
        2.  Download the `google-services.json` file and place it in the `android/app/` directory.

    -   **iOS**:
        1.  Create a new iOS app in your Firebase project with the bundle ID `com.sos.auto`.
        2.  Download the `GoogleService-Info.plist` file and place it in the `ios/Runner/` directory. Open it in Xcode and add it to the Runner target.

    -   **Web**:
        1.  Create a new Web app in your Firebase project.
        2.  The Firebase configuration is managed in `lib/firebase_options.dart`. You can use the FlutterFire CLI to configure it automatically: `flutterfire configure`.

## 🛠️ Build and Run

### Running the app

-   **Run on a connected device or simulator:**
    ```bash
    flutter run
    ```

-   **Run on a specific device (e.g., Chrome for web):**
    ```bash
    flutter run -d chrome
    ```

### Building for Release

-   **iOS:**
    ```bash
    flutter build ios --release
    ```

-   **Android:**
    ```bash
    flutter build apk --release
    # or for an app bundle
    flutter build appbundle --release
    ```

-   **Web:**
    ```bash
    flutter build web
    ```

## 📞 Support

For any issues, please refer to:
-   **Firebase**: Check your Firebase console and the official documentation.
-   **Flutter**: Check the Flutter documentation and community forums.
-   **Project-specific**: Open an issue in this repository.
