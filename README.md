# EduPlanner AI

EduPlanner AI - yapon kasb-hunar maktabi talabasi uchun Flutter asosida yozilgan o'quv rejalashtirish ilovasi. Ilova dars jadvali, topshiriqlar, haftalik progress, Google login, Firebase Firestore saqlash, push notification va Gemini API orqali AI yordamchini birlashtiradi.

## Texnologiyalar

- Flutter SDK `>=3.3.0`
- State management: `flutter_riverpod`
- Routing: `go_router`
- Backend: Firebase Core, Auth, Firestore, Messaging
- AI: Gemini API (`google_generative_ai`, model: `gemini-1.5-flash`)
- UI: Material 3, NotoSansJP, `hugeicons`, `fl_chart`, `flutter_animate`, `table_calendar`
- Storage: `shared_preferences`, `flutter_secure_storage`
- Code generation: `freezed`, `json_serializable`, `build_runner`

## Asosiy Papkalar

- `lib/main.dart` - Flutter, Firebase, notification va app bootstrap.
- `lib/app.dart` - `MaterialApp.router`, theme va lokalizatsiya.
- `lib/core/` - theme, router, constants, provider, utility va notification service.
- `lib/shared/` - umumiy UI widgetlar.
- `lib/features/auth/` - Google login va user modeli.
- `lib/features/home/` - bosh sahifa, progress va AI maslahat.
- `lib/features/timetable/` - dars jadvali CRUD.
- `lib/features/assignments/` - topshiriqlar CRUD va filterlar.
- `lib/features/ai_chat/` - Gemini API bilan chat.
- `lib/features/settings/` - sozlamalar, theme, logout va Gemini API key saqlash.
- `firestore.rules` - Firestore xavfsizlik qoidalari.

## Kerakli Dasturlar

```bash
flutter --version
flutter doctor
dart --version
```

Android telefon orqali ishga tushirish uchun:

```bash
adb devices -l
flutter devices
```

## O'rnatish

Project root:

```bash
cd /home/yashiloyceo/Desktop/eduplanner_ai
flutter pub get
```

Code generation:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Firebase Sozlash

Loyiha quyidagi Firebase account/projectga ulangan:

```text
Firebase account: okiljonnabev@gmail.com
Firebase project name: EduPlannerAI
Firebase project id: eduplannerai-97365
Firebase project number: 351731284172
```

`lib/firebase_options.dart` FlutterFire CLI orqali real Android/iOS/Web app konfiguratsiyalari bilan generatsiya qilingan. Konfiguratsiyani qayta yaratish kerak bo'lsa:

```bash
flutterfire configure --project=eduplannerai-97365 --platforms=android,ios,web --android-package-name=com.example.eduplanner_ai --ios-bundle-id=com.example.eduplannerAi --yes
```

Firebase Console ichida quyidagilar yoqilgan bo'lishi kerak:

- Authentication: Google Sign-In
- Cloud Firestore
- Firebase Cloud Messaging
- iOS/Android app konfiguratsiyalari

Firestore rules deploy:

```bash
firebase deploy --only firestore:rules
```

Firestore API va default database yaratildi, `firestore.rules` deploy qilindi.

## Gemini API Key

Gemini API key kod ichida hardcode qilinmaydi. Ilova ishga tushgach:

1. Home sahifadan Settings ekraniga o'ting.
2. `Gemini API キー` bo'limini oching.
3. O'zingizning Anthropic API key qiymatingizni kiriting.

Key `flutter_secure_storage` ichida `gemini_api_key` nomi bilan saqlanadi.

## Ishga Tushirish

Chrome:

```bash
flutter run -d chrome
```

Gemini API key bilan lokal ishga tushirish:

```bash
flutter run -d chrome --dart-define-from-file=.env.local.json
```

Wi-Fi ADB orqali ulangan Android qurilma:

```bash
flutter run -d adb-Y5RGCMFMYDWGONZL-w7mdQ4._adb-tls-connect._tcp --dart-define-from-file=.env.local.json
```

Device id o'zgarsa, `flutter devices` dan yangi id ni oling.

## Tekshirish

Static analysis:

```bash
flutter analyze
```

Testlar:

```bash
flutter test
```

Web build:

```bash
flutter build web
```

Android debug APK:

```bash
flutter build apk --debug
```

APK manzili:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Common Errors

`intl` dependency conflict:

Current Flutter SDK `flutter_localizations` orqali `intl 0.20.2` ni pin qiladi. Shu sabab `pubspec.yaml` da `intl: ^0.20.2` ishlatilgan.

`FirebaseOptions` placeholder bilan login yoki Firestore ishlamayapti:

`flutterfire configure` bajaring va Firebase Console da Auth/Firestore yoqilganini tekshiring.

Gemini javob bermayapti:

Settings ekranida Gemini API key kiritilganini va key faol ekanini tekshiring.

Android qurilma ko'rinmayapti:

Telefon va laptop bir Wi-Fi tarmog'ida ekanini, Wireless debugging ulanganini va `adb devices -l` qurilmani ko'rsatayotganini tekshiring.

## Final Start Command

Hozir ulangan Wi-Fi ADB telefon uchun:

```bash
flutter run -d adb-Y5RGCMFMYDWGONZL-w7mdQ4._adb-tls-connect._tcp
```
