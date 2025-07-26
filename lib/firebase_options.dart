// File generated manually for Firebase configuration

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCBx9ye9Z2A4DWHmYdXKj1Ib_a6RN1GkA4',
    appId: '1:907011038084:android:0dda8e38234aaa1eef5bd1',
    messagingSenderId: '907011038084',
    projectId: 'sos-auto-506b5',
    storageBucket: 'sos-auto-506b5.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCBx9ye9Z2A4DWHmYdXKj1Ib_a6RN1GkA4',
    appId: '1:907011038084:ios:0dda8e38234aaa1eef5bd1',
    messagingSenderId: '907011038084',
    projectId: 'sos-auto-506b5',
    storageBucket: 'sos-auto-506b5.firebasestorage.app',
    iosBundleId: 'com.sos.auto',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCBx9ye9Z2A4DWHmYdXKj1Ib_a6RN1GkA4',
    appId: '1:907011038084:ios:0dda8e38234aaa1eef5bd1',
    messagingSenderId: '907011038084',
    projectId: 'sos-auto-506b5',
    storageBucket: 'sos-auto-506b5.firebasestorage.app',
    iosBundleId: 'com.sos.auto',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCBx9ye9Z2A4DWHmYdXKj1Ib_a6RN1GkA4',
    appId: '1:907011038084:android:0dda8e38234aaa1eef5bd1',
    messagingSenderId: '907011038084',
    projectId: 'sos-auto-506b5',
    storageBucket: 'sos-auto-506b5.firebasestorage.app',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyCBx9ye9Z2A4DWHmYdXKj1Ib_a6RN1GkA4',
    appId: '1:907011038084:android:0dda8e38234aaa1eef5bd1',
    messagingSenderId: '907011038084',
    projectId: 'sos-auto-506b5',
    storageBucket: 'sos-auto-506b5.firebasestorage.app',
  );
}
