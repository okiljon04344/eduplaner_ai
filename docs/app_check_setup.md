# Firebase App Check Sozlamalari va Debug Token Yo'riqnomasi

Loyiha ID: `eduplannerai-97365`  
Holat: **Enforcement O'CHIQ** (avval barcha platformalarda `app: VALID` tasdiqlangandan keyin yoqiladi).

---

## 1. Muammo sababi (`app: INVALID` / `Decoding App Check token failed`)

Cloud Functions loglarida quyidagi xato chiqayotgan edi:

```text
Failed to validate AppCheck token. FirebaseAppCheckError: Decoding App Check token failed.
verifications: { app: "INVALID", auth: "VALID" }
```

Tekshiruvda quyidagi sabablar aniqlandi:

1. **`firebaseappcheck.googleapis.com` API o'chiq edi** (`403 SERVICE_DISABLED`) — klient token almashinuvida xato olgach, Firebase SDK `X-Firebase-AppCheck` header'iga haqiqiy 3 qismli JWT o'rniga xato placeholder matnini yuborgan. API **yoqildi** (enforcement o'chiq qoldirildi).
2. **Debug token ro'yxatdan o'tkazilmagan edi** — Firebase App Check'da barcha 4 ta ilova uchun 0 ta debug token mavjud edi.
3. **Platforma bo'yicha klient sozlamasi (`lib/main.dart`) nuqsonlari**:
   - `macOS` oldin `!mobile` bilan tashlab ketilgan, lekin `FirebaseAppCheckPlugin` ilova startida `DeviceCheckProvider` ni avtomatik o'rnatib qo'ygani uchun imzosiz dev macOS build'lar `INVALID` token yuborgan.
   - `Web` da `RECAPTCHA_SITE_KEY` berilmasa debug rejimda ham App Check o'tkazib yuborilgan (`WebDebugProvider` ishlatilmagan).
   - `Android` / `iOS` / `Web` / `Windows` uchun `--dart-define=APP_CHECK_DEBUG_TOKEN=...` qo'llab-quvvatlanmagan.

Endi provider tanlovi [`lib/core/services/app_check_config.dart`](../lib/core/services/app_check_config.dart) (`resolveAppCheckPlan`) orqali boshqariladi. Debug provider'lar faqat `!kReleaseMode` holatda ishlaydi (release build'ga hech qachon kirmaydi).

---

## 2. Platformalar bo'yicha tekshiruv va talablar

| Platforma | Firebase App ID | Debug / Dev Provider | Release Provider | Hozirgi holat / Kerakli qadamlar |
|---|---|---|---|---|
| **Android** (`com.eduplanner.app`) | `1:351731284172:android:a2de2152df881b89582a69` | `AndroidDebugProvider` (avto yoki `APP_CHECK_DEBUG_TOKEN`) | `AndroidPlayIntegrityProvider` | Release uchun: `playintegrity.googleapis.com` ni yoqish, **SHA-256** larni Firebase Console'ga qo'shish (hozir faqat debug `SHA-1` bor) va App Check'da Play Integrity'ni yoqish. |
| **iOS** (`com.eduplanner.app`) | `1:351731284172:ios:30f0d6434d41f25a582a69` | `AppleDebugProvider` | `AppleAppAttestWithDeviceCheckFallbackProvider` | **Diqqat:** Firebase Console'da iOS ilovaning `bundleId` maydoni `com.example.eduplannerAi` bo'lib qolgan (`GoogleService-Info.plist` va Xcode'da `com.eduplanner.app`) hamda **Team ID** kiritilmagan. Release'dan oldin Firebase Console'da Team ID + to'g'ri bundle ID, Xcode'da **App Attest** capability va App Check'da App Attest/DeviceCheck ni sozlang. |
| **Web** | `1:351731284172:web:7f379f1f8770a64e582a69` | `WebDebugProvider` (avtomatik yoki `APP_CHECK_DEBUG_TOKEN`) | `ReCaptchaV3Provider(RECAPTCHA_SITE_KEY)` | Release build uchun reCAPTCHA v3 Site Key & Secret Key yarating, Secret Key ni Firebase App Check → Web ga kiriting va `--dart-define=RECAPTCHA_SITE_KEY=...` bilan build qiling. |
| **macOS** | (`ios` fallback) | `AppleDebugProvider` | `AppleAppAttestWithDeviceCheckFallbackProvider` | Debug endi tuzatildi (`AppleDebugProvider`). Release tarqatish uchun alohida macOS app + Team ID + App Attest kerak. |
| **Windows** | (`web` fallback) | `WindowsDebugProvider` (faqat `APP_CHECK_DEBUG_TOKEN` berilsa) | **Mavjud emas** | Firebase C++ SDK Windows'da release attestation provider qo'llamaydi. Enforcement yoqilsa Windows release build'lar rad etiladi. |
| **Linux** | — | Qo'llab-quvvatlanmaydi | Qo'llab-quvvatlanmaydi | Linux'da `firebase_app_check` mavjud emas (avtomatik o'tkazib yuboriladi). |

> **Eslatma (Web `localStorage` keshi):** `firebase_app_check_web` oxirgi ishlatilgan provider turini brauzer `localStorage` da saqlaydi (`FlutterFire-[DEFAULT]-recaptchaType` va `FlutterFire-[DEFAULT]-recaptchaSiteKey`). Agar debug va reCAPTCHA v3 o'rtasida almashsangiz, DevTools → Application → Local Storage dan shu 2 kalitni o'chirib sahifani yangilang.

---

## 3. Emulator / Dev uchun Debug Token ro'yxatdan o'tkazish

> Agar `USE_EMULATOR=true` bilan **lokal** Firebase emulyatorlariga ulangan bo'lsangiz, App Check avtomatik o'chiriladi (`emulator_disabled`). Quyidagi yo'riqnoma **haqiqiy Firebase loyihasiga (`eduplannerai-97365`)** debug/emulator build'dan ulanish uchun.

### 1-usul (Tavsiya etiladi — CLI orqali doimiy dev token)

Har safar emulator tozalanib yangi token generatsiya bo'lmasligi uchun bitta doimiy token yarating:

```bash
# Android (com.eduplanner.app) uchun:
firebase appcheck:debugtokens:create \
  --app 1:351731284172:android:a2de2152df881b89582a69 \
  --display-name "dev-android-emulator" \
  --project eduplannerai-97365

# Web (Chrome localhost) uchun:
firebase appcheck:debugtokens:create \
  --app 1:351731284172:web:7f379f1f8770a64e582a69 \
  --display-name "dev-web-chrome" \
  --project eduplannerai-97365

# iOS Simulator / macOS dev uchun:
firebase appcheck:debugtokens:create \
  --app 1:351731284172:ios:30f0d6434d41f25a582a69 \
  --display-name "dev-apple" \
  --project eduplannerai-97365
```

Chiqarilgan UUID token'ni `--dart-define=APP_CHECK_DEBUG_TOKEN=<UUID>` bilan ishga tushiring (hech qachon Git'ga saqlamang!):

```bash
flutter run --dart-define=APP_CHECK_DEBUG_TOKEN=<UUID>
# yoki Web uchun:
flutter run -d chrome --dart-define=APP_CHECK_DEBUG_TOKEN=<UUID>
```

### 2-usul (Avto-generatsiya qilingan token'ni Console'ga kiritish)

1. Ilovani oddiy debug rejimda ishga tushiring (`flutter run` yoki `flutter run -d chrome`).
2. Konsol / logcat dan debug token'ni toping:
   - **Android (`adb logcat | grep -i DebugAppCheckProvider`):**
     `Enter this debug secret into the allow list in the Firebase Console for your project: <UUID>`
   - **iOS / macOS (Xcode / Flutter console):**
     `Firebase App Check Debug Token: <UUID>`
   - **Web (Chrome DevTools Console):**
     `App Check debug token: <UUID>. You will need to add it to your app's App Check settings in the Firebase console...`
3. Token'ni Firebase Console → **App Check → Apps → kerakli ilova → ⋮ → Manage debug tokens → Add debug token** orqali saqlang.
4. Ilovani qayta ishga tushiring va Cloud Functions chaqiring.

Mavjud debug token'larni ko'rish / o'chirish:

```bash
firebase appcheck:debugtokens:list --app <APP_ID> --project eduplannerai-97365
firebase appcheck:debugtokens:delete <TOKEN_ID> --app <APP_ID> --project eduplannerai-97365 --force
```

---

## 4. `app: VALID` ekanini loglarda tekshirish

1. Ilovada biror Callable function'ni chaqiring (masalan, AI Chat → xabar yuborish).
2. Loglarni tekshiring:
   ```bash
   firebase functions:log --only chatWithTutor -n 20 --project eduplannerai-97365
   ```
3. Quyidagi ko'rinishda chiqishi kerak (xato va `app: INVALID` bo'lmasligi shart):
   ```json
   {"verifications":{"auth":"VALID","app":"VALID"},"message":"Callable request verification passed"}
   ```
4. **Firebase Console → App Check → APIs** bo'limida **Verified requests** ulushi o'sib borayotganini tasdiqlang.

---

## 5. Production Release (Play Integrity / App Attest / reCAPTCHA) ni tayyorlash

Enforcement'ni yoqishdan **oldin**:

1. **Android Play Integrity:**
   ```bash
   gcloud services enable playintegrity.googleapis.com --project=eduplannerai-97365
   ```
   Firebase Console → Project Settings → `com.eduplanner.app` ga quyidagi **SHA-256** larni qo'shing:
   - Google Play Console → App integrity → **Play App Signing** SHA-256
   - Upload keystore (`android/app/upload-keystore.jks`) SHA-256: `18:A9:9D:9C:89:99:5D:9F:CB:EB:7A:EE:95:AA:74:50:1A:5F:13:FF:4A:16:2A:93:47:5D:46:91:3D:64:AF:0C`
   - Lokal test (`profile`/`ALLOW_DEBUG_SIGNING=true`) uchun debug keystore SHA-256: `E8:1D:74:1E:CD:9D:A9:EA:D4:C5:A2:60:00:A8:16:61:A5:43:BD:C5:B8:4C:06:A1:8E:9E:71:FC:CE:F3:0F:02`
   So'ng Firebase Console → App Check → Apps → `com.eduplanner.app` → **Play Integrity** ni yoqing.
2. **iOS App Attest / DeviceCheck:**
   - Firebase Console'da iOS ilova (`1:351731284172:ios:30f0d6434d41f25a582a69`) **Team ID** sini kiriting (va bundle ID `com.eduplanner.app` ekanini tekshiring).
   - Xcode → Runner → Signing & Capabilities → `+ Capability` → **App Attest** qo'shing.
   - Firebase Console → App Check → iOS → **App Attest** ni ro'yxatdan o'tkazing.
3. **Web reCAPTCHA v3:**
   - Google reCAPTCHA v3 da domenlar (`eduplannerai-97365.web.app`, `eduplannerai-97365.firebaseapp.com`) uchun kalit yarating.
   - Firebase Console → App Check → Web → **reCAPTCHA v3** ga Secret Key kiriting.
   - Deploy build: `flutter build web --release --dart-define=RECAPTCHA_SITE_KEY=<SITE_KEY>`.
4. **Enforcement yoqish (faqat hamma metrika `VALID` bo'lgach!):**
   - Cloud Functions: `functions/index.js` da `enforceAppCheck: true` qo'shib deploy qilish.
   - Firestore / RTDB / Storage: Firebase Console → App Check → APIs da **Enforce** bosish.
