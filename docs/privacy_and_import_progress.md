# EduPlanner AI: Maxfiylik (Privacy Masking) va Dars Jadvalini Import Qilish (Timetable Import) Tizimi

Ushbu hujjat loyihada amalga oshirilgan maxfiylikni himoyalash, server-side masking, maktab siyosati (School Policy) va dars jadvalini import qilish arxitekturasi bo'yicha to'liq qo'llanma va hisobotdir. Keyingi barcha ishlab chiqish sessiyalari shu hujjatdagi prinsiplar va spetsifikatsiyalarga tayanadi.

---

## 1. Asosiy Arxitektura Qarorlari

1. **Server-Side Masking (Yagona Haqiqat Manbai):**
   - Barcha talaba va o'qituvchi ismlari, identifikatorlari va maxfiy ma'lumotlar AI (Gemini) ga yuborilishidan oldin **Cloud Functions serverida** to'liq maskalanadi.
   - Klient (Flutter ilovasi) ga hech qachon barcha maktab a'zolarining ismlari yoki maxfiy token-ism xaritalari (token map) yuborilmaydi.
   - `firestore.rules` mutlaqo o'zgarmaydi — talaba va o'qituvchilar faqat o'zlariga tegishli Firestore hujjatlarini ko'ra oladilar.

2. **`callGeminiSafely` — Yagona Chiqish Darvozasi (Single Exit Gateway):**
   - Backend'dagi barcha Gemini chaqiruvlari (`chatWithTutor`, `analyzeWeakArea`, `generateQuiz`, `analyzeAssignmentSubmission`, `previewTimetableImport` (AI fallback)) faqat va faqat `callGeminiSafely` orqali o'tadi.
   - Prompt matni yuborilishidan oldin ro'yxatdagi ismlar tokenlarga almashtiriladi (`[STUDENT_1]`, `[TEACHER_1]`). Gemini javob bergach, faqat serverda tokenlar qayta ochilib, foydalanuvchiga yuboriladi.

3. **Fail-Closed (Xavfsiz To'xtash) Prinsipi:**
   - Agar foydalanuvchilar ro'yxatini yuklashda Firestore xatosi yoki timeout yuz bersa, yoki Vision OCR xatoga uchrasa — Gemini chaqirilmaydi. Xato darhol qaytariladi va sarflangan kunlik AI kvotasi to'liq qaytariladi (`refundAiQuota`).
   - Maktabga bog'lanmagan shaxsiy foydalanuvchi xato hisoblanmaydi: uning o'z ismi va o'z dars jadvalidagi o'qituvchi ismlari maskalanadi.

4. **Xavfsiz Tasvir va PDF Qayta Ishlash:**
   - **PDF:** `pdfjs-dist` orqali matn ajratiladi (`isEvalSupported: false`, `disableFontFace: true`, CMap paketi sozlangan). Gemini'ga hech qachon `inlineData` sifatida PDF baytlari ketmaydi, faqat maskalangan matn yuboriladi. Agar sahifada o'rtacha 50 belgidan kam bo'lsa, "skanerlangan PDF" deb rad etiladi (`scanned_pdf`).
   - **Rasm (JPEG/PNG/WEBP):** `sharp` orqali EXIF orientation to'g'rilanadi va 2048px ga cheklanadi. Google Cloud Vision OCR ishlatiladi. Topilgan ismlar, `氏名`/`Name:` yorliqlari va talaba ID'lari qora to'rtburchaklar bilan to'liq yopiladi (redacted). Gemini'ga faqat yopilgan rasm yoki OCR'dan olingan matn yuboriladi. HEIC/HEIF serverda rad etiladi (`unsupported_heic`) — Flutter klientida konvertatsiya qilinishi shart.

5. **School Policy — Faqat Qattiqlashtiruvchi (Additive / Tightening Only):**
   - `schools/{domain}.policy` faqat maktab ma'muri (Admin) tomonidan o'zgartirilishi mumkin.
   - Siyosat faqat qo'shimcha qoidalar qo'shadi (qo'shimcha Regex ID shablonlari, qo'shimcha yopish yorliqlari, `honorificExceptions`). Asosiy tizim xavfsizlik qoidalarini bo'shashtirish (relax) imkonsiz.
   - Xotirada kesh har bir callable so'rovida yangitdan yuklanadi (instansiya kesh ifloslanishiga yo'l qo'yilmaydi).

---

## 2. Bosqichlar 1 – 4a-2 Xulosasi: Nima Qilindi, Qaysi Fayllar va Testlar

### 1-bosqich: Dart Client-Side Privacy Moduli
- **Fayllar:** `lib/core/privacy/` (`masking_session.dart`, `japanese_normalizer.dart`, `pii_detector.dart`).
- **Natija:** Dart testlari orqali 全角→半角 normalizatsiya, uzun ismlarni birinchi almashtirish, unikal tokenlar berish tekshirilgan.
- **Testlar:** `test/core/privacy/masking_session_test.dart`.

### 2-bosqich: Node.js Cloud Functions Privacy Moduli & Callables Refaktoringi
- **Fayllar:**
  - `functions/privacy/masking_session.js`
  - `functions/privacy/japanese_normalizer.js`
  - `functions/privacy/pii_pattern_masker.js`
  - `functions/privacy/safe_gemini.js`
  - `functions/school/sync.js` (`resolveSchoolDomain`)
- **Natija:** Barcha 4 ta AI chaqiruvi (`chatWithTutor`, `analyzeWeakArea`, `generateQuiz`, `analyzeAssignmentSubmission`) `callGeminiSafely` ga ulandi. Loglarda Gemini xatolari, promptlar va ismlar yozilishi to'xtatildi.
- **Testlar:** `functions/test/privacy.test.js`, umumiy `test_fixtures/privacy_cases.json`.

### 3-bosqich: Multimodal Redaction (PDF & Rasm OCR)
- **Fayllar:**
  - `functions/privacy/pdf_extractor.js` (pdfjs-dist CMap, 30 sahifa limiti, CVE-2024-4367 ga qarshi `isEvalSupported: false`).
  - `functions/privacy/image_redactor.js` (`sharp.rotate()`, Vision OCR `DOCUMENT_TEXT_DETECTION`, ismlar/ID'lar/yorliqlarni qora to'rtburchak bilan yopish).
- **Testlar:** `functions/test/multimodal_redaction.test.js` (13 ta test).

### 4a & 4a-2 bosqichlar: School Policy & Ko'p Formatli Dars Jadvali Importi
- **Fayllar:**
  - `functions/school/policy.js` (Policy modeli, ReDoS himoyasi, xavfsiz Regex validatsiyasi, optimistic concurrency).
  - `functions/school/timetable_grid.js` (Vision OCR so'zlaridan va PDF elementlaridan 2D dars katakchalarini qayta tiklash).
  - `functions/school/jp_holidays.js` (Vazirlar Mahkamasi rasmiy bayramlari + 2028 provisional tengkunlik bayramlari).
  - `functions/school/timetable_import.js` (`previewTimetableImport`, `confirmTimetableImport`, `revertTimetableImport`, UTF-8 BOM/no-BOM va Shift_JIS/CP932 auto-detection, `checkShiftJisSupport`).
  - `functions/index.js` (Callable'lar eksporti va xotira/timeout sozlamalari).
- **Testlar:**
  - `functions/test/policy.test.js` (14 ta test)
  - `functions/test/timetable_import.test.js` (23 ta test, 175 ta umumiy functions testlari)
  - `functions/test/rules/firestore_rules.test.js` (11 ta granular Firestore Rules xavfsizlik testlari).

---

## 3. Cloud Functions Callable'lar Inventari

Barcha callable funksiyalar Firebase Callable protokoli orqali ishlaydi (`functions.https.onCall`).

### 1. `previewTimetableImport`
- **Kiruvchi parametrlar (`data`):**
  - `grade` (`number`, 1..3)
  - `course` (`string | null`)
  - `mode` (`'merge' | 'replace'`)
  - `fileName` (`string`)
  - `mimeType` (`string`: `text/csv`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`, `application/pdf`, `image/jpeg`, `image/png`, `image/webp`)
  - `fileBase64` (`string`, maks. 10MB dekodlangan hajm)
  - `dateRange` (`{ start: 'YYYY-MM-DD', end: 'YYYY-MM-DD' }`, maks. 366 kun)
  - `includeNonSchoolDays` (`boolean`, default `false`)
- **Chiquvchi javob (`result`):**
  - `draftId` (`string`, 30 daqiqa yashaydi)
  - `diffSummary` (`{ added: number, updated: number, removed: number, unchanged: number }`)
  - `diffPreview` (`Array<{ dayId, date, weekday, period, changeType: 'added'|'updated'|'removed'|'unchanged', before, after }>`, maks. 200 ta)
  - `changedDaysCount` (`number`)
  - `excludedDates` (`Array<{ date, reason: 'holiday'|'closed_date_range'|'non_school_day'|'manual', label: string, provisional?: boolean }>`)
  - `invalidRows` (`Array<{ rowNumber, rawText, reason }>`, maks. 100 ta)
  - `parseMethod` (`'school_matrix' | 'header_mapper' | 'ocr_grid' | 'ai'`)
  - `usedAi` (`boolean`)
  - `maskedPreviewText` (`string | null`, agar AI ishlatilgan bo'lsa serverda maskalangan dars matni ko'rinishi)
- **Mumkin bo'lgan xato kodlari va `details.reason`:**
  - `unauthenticated`
  - `permission-denied` (`not_authorized`, `import_disabled_by_policy`, `homeroom_mismatch`)
  - `invalid-argument` (`unsupported_format`, `invalid_date_range`, `range_too_large`, `file_too_large`)
  - `failed-precondition`:
    - `reason: 'scanned_pdf'` (PDF skanerlangan, matn belgisi kam)
    - `reason: 'unsupported_heic'` (HEIC rasm, klientda JPG qilinishi kerak)
    - `reason: 'sjis_unsupported_runtime'` (Node muhitida Shift_JIS yo'q)
    - `reason: 'ocr_failed'` (Vision API xatosi)
    - `reason: 'policy_disallows_replace'` (Siyosat replace rejimini taqiqlagan)
  - `resource-exhausted` (`ai_quota_exceeded`)
  - `unavailable` (Gemini yoki Vision vaqtincha ishlamayapti)

### 2. `confirmTimetableImport`
- **Kiruvchi parametrlar (`data`):**
  - `draftId` (`string`)
  - `notifyStudents` (`boolean`)
  - `pushSummary` (`string | null`)
- **Chiquvchi javob (`result`):**
  - `success` (`true`)
  - `importId` (`string`)
  - `updatedDaysCount` (`number`)
  - `undoWindowExpiresAt` (`string` ISO)
- **Mumkin bo'lgan xato kodlari:**
  - `not-found` (`draft_expired_or_not_found`)
  - `aborted` (`reason: 'timetable_changed'` — optimistic concurrency: dars jadvali boshqa o'qituvchi tomonidan o'zgartirilgan)
  - `failed-precondition` (`reason: 'policy_changed'` — qoralama yaratilgandan so'ng maktab siyosati o'zgargan)

### 3. `revertTimetableImport`
- **Kiruvchi parametrlar (`data`):**
  - `importId` (`string`)
- **Chiquvchi javob (`result`):**
  - `success` (`true`)
  - `restoredDaysCount` (`number`)
- **Mumkin bo'lgan xato kodlari:**
  - `not-found` (`history_not_found`)
  - `permission-denied` (`only_author_or_admin`)
  - `failed-precondition` (`undo_window_expired`, `already_reverted`)
  - `aborted` (`reason: 'timetable_changed'` — jadval keyinroq yana o'zgargan)

### 4. `setSchoolPolicy`
- **Kiruvchi parametrlar (`data`):**
  - `policy` (`Partial<SchoolPolicy>`)
  - `expectedRevision` (`number`)
- **Chiquvchi javob (`result`):**
  - `policy` (yangilangan to'liq siyosat)
- **Mumkin bo'lgan xato kodlari:**
  - `permission-denied` (faqat maktab admini)
  - `invalid-argument` (xavfli Regex, noma'lum maydonlar, siyosatni bo'shashtirish urinishlari)
  - `aborted` (`policy_conflict` — concurrency to'qnashuvi)

---

## 4. Qabul Qilingan va Rad Etilgan Texnik Qarorlar

1. **RE2 (Google RE2 regex engine):**
   - **Holati:** Rad etildi / Kechiktirildi (*"RE2 keyinroq ko'rib chiqiladi"*).
   - **Sababi:** Node 22 muhitida `re2` npm paketi GitHub'dan binar fayllarni yuklaydi va deploy jarayonida xatolik chiqarishi mumkin. O'rniga `validateSafeRegexPattern` (ReDoS tekshiruvi: nested quantifiers `(a+)+`, excessive lookaheads, backtracking xavflarini taqiqlash) va 6000 belgilik oyna (`boundedSchoolMatches`) joriy etildi. Har bir pattern < 50ms da yakunlanishi testlandi.
2. **`.json` formati orqali import:**
   - **Holati:** Rad etildi.
   - **Sababi:** Hujum maydonini kamaytirish uchun va maktablar amalda Excel/CSV/PDF/Qog'oz rasm ishlatganligi sababli `.json` qabul qilinmaydi (`invalid-argument`).
3. **ML Kit o'rniga Google Cloud Vision API:**
   - **Holati:** Qabul qilindi.
   - **Sababi:** Barcha maxfiylik va tekshirish serverda bajarilishi shartligi tufayli va klientga ismlar ketmasligi uchun backend'da `@google-cloud/vision` dan foydalanildi.
4. **Shift_JIS / CP932 uchun tashqi kutubxona (`iconv-lite`):**
   - **Holati:** Rad etildi.
   - **Sababi:** Node.js 22 to'liq ICU (v78.2) bilan jihozlangan bo'lib, `new TextDecoder('shift_jis')` WHATWG spetsifikatsiyasi bo'yicha Windows-31J (CP932 maxsus belgilari: ①②, 髙, 﨑) ni mukammal o'qiydi. Qo'shimcha paket kerak emas.

---

## 5. Loyiha Standartlari va Qat'iy Qoidalar

1. **Papka Struktura Qoidasi:**
   - Har bir feature faqat quyidagi papkalarga ega bo'lishi mumkin:
     - `models/`
     - `providers/`
     - `repositories/`
     - `screens/`
     - `widgets/`
   - **Taqiqlangan:** `data/`, `domain/`, `application/`, `presentation/` kabi ortiqcha qatlamlar ochilmaydi.
2. **Providerlar:** Barcha global providerlar `lib/core/providers/app_providers.dart` yoki tegishli `feature/*_providers.dart` ichida Riverpod orqali e'lon qilinadi.
3. **21 Til & Lokalizatsiya:** Ilovadagi matnlar `app_strings.dart` va tegishli l10n manbalarida 21 ta tilda to'liq qo'llab-quvvatlanadi.
4. **Dizayn Tizimi:** "Green Neon" mavzusi (Dark/Neon aksentlar, zamonaviy dars jadvali kartalari).
5. **`firestore.rules`:** Mutlaqo o'zgartirilmaydi! Barcha maxsus huquqlar Cloud Functions darajasida tekshiriladi.
6. **Yangi Paketlar:** Hech qanday yangi Flutter yoki npm paketlari foydalanuvchi ruxsatisiz qo'shilmaydi.

---

## 6. Ochiq Qolgan Ishlar Rejasi

- **4b-bosqich:** Flutter Data, Domain va Riverpod State qatlami.
- **4c-bosqich:** O'qituvchilar uchun dars jadvalini import qilish UI ekrani (Fayl tanlash, Diff ko'rish, Excluded dates, Xavfli o'chirishlarda ikkilamchi tasdiq, Undo tugmasi).
- **4d-bosqich:** Admin uchun School Policy boshqaruv ekrani (Import rejimlarini sozlash, maxsus talaba ID regexlari).
- **5-bosqich:** Qo'lda oxirigacha sinov (E2E emulator yoki haqiqiy qurilmada).
- **AI Multi-Provider (Gemini + Claude) 2-bosqich (Yakunlandi):**
  - `functions/ai/` (`ai_provider.js`, `gemini_provider.js`, `claude_provider.js`, `ai_config.js`, `ai_errors.js`), `@anthropic-ai/sdk@1.10.0`, `functions/privacy/safe_ai.js` (`callAiSafely`).
  - `gemini_client.js` va `safe_gemini.js` shim'lari o'chirildi; ESLint `no-restricted-imports` qoidalari bilan to'g'ridan-to'g'ri SDK importi bloklandi.
  - 5 MB base64 rasm cheklovi (`CLAUDE_MAX_IMAGE_BASE64_BYTES`) va `image_too_large_for_provider` xato sababi qo'shildi.
- **AI Multi-Provider 3-bosqich (Yakunlandi):**
  - **Shared fayllar sinxronligi:** `shared/*.json` yagona manba; `npm run sync-shared` (`functions/scripts/sync_shared.mjs`) + Node (`functions/test/shared_sync.test.js`) va Dart (`test/core/privacy/shared_sync_test.dart`) parity testlari.
  - **`max_tokens` kesilishi & Adaptive Thinking:** Fikrlash tokenlari `max_tokens` ga kirishi sababli `AI_TASK_CONFIG` chegaralari moslashtirildi (`chatWithTutor: 2560`, `generateQuiz:grounding: 3072`, `analyzeAssignmentSubmission: 4096`). JSON vazifalarda kesilganda 1 marta `1.5×` (maks. `8192`) qayta urinadi; matn vazifalarida kesilgan javobni `kind: 'truncated'` logi bilan qaytaradi.
  - **Oylik agregatsiya va Byudjet himoyasi:** `ai_usage_monthly/{yyyymm}/models/{provider_model}` kolleksiyasiga atomik `FieldValue.increment` bilan tokenlar va `webSearchRequests` yoziladi (`functions/ai/ai_budget.js`). `AI_MONTHLY_BUDGET_USD` 80% da bir marta ogohlantiradi, 100% da `claude` ni UTC oy oxirigacha avtomatik `gemini` ga yo'naltiradi. Markaziy narxlar jadvali `AI_PRICING_CONFIG` (`ai_config.js`) da saqlanadi.
  - **Fallback & CLI & Taqqoslash:** `AI_FALLBACK_PROVIDER` faqat vaqtinchalik (`rate_limited`, `overloaded`, `timeout`) xatolarda bir xil maskalangan so'rov bilan zaxira provayderga o'tadi. `functions/scripts/compare_providers.mjs` (`--smoke` va 12 namunali taqqoslash) hamda O'zbek tilidagi `functions/scripts/ai_keys.mjs` (`npm run ai:keys`) yaratildi va unit/shartnoma testlari bilan qoplandi.
- **Flutter 3.50 `material_ui` eskirishi (deprecation):** `flutter analyze` hozir 110 ta `deprecated_member_use` (`package:flutter/material.dart` → `package:material_ui/material_ui.dart`) `info` diagnostikasini bermoqda. Hozircha ataylab tegilmadi — testdan keyin alohida branch'da migratsiya qilinadi.
