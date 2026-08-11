import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return web;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCS2-ca8L6o-vm11EDGR4o1LI9k5A3Fsx0',
    appId: '1:351731284172:android:a2de2152df881b89582a69',
    messagingSenderId: '351731284172',
    projectId: 'eduplannerai-97365',
    storageBucket: 'eduplannerai-97365.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCS2-ca8L6o-vm11EDGR4o1LI9k5A3Fsx0',
    appId: '1:351731284172:ios:30f0d6434d41f25a582a69',
    messagingSenderId: '351731284172',
    projectId: 'eduplannerai-97365',
    storageBucket: 'eduplannerai-97365.firebasestorage.app',
    iosBundleId: 'com.eduplanner.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCS2-ca8L6o-vm11EDGR4o1LI9k5A3Fsx0',
    appId: '1:351731284172:web:7f379f1f8770a64e582a69',
    messagingSenderId: '351731284172',
    projectId: 'eduplannerai-97365',
    authDomain: 'eduplannerai-97365.firebaseapp.com',
    storageBucket: 'eduplannerai-97365.firebasestorage.app',
  );
}
