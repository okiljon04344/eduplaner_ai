# Senior Level Mahalliylashtirish (i18n) Tizimi

Ilovadagi barcha 21 ta til uchun to'liq va professional darajadagi mahalliylashtirish tizimi yakunlandi. Bu nafaqat matnlarni tarjima qilish, balki dinamik parametrlar va tizimli bildirishnomalarni ham o'z ichiga oladi.

## Senior Developer Yondashuvi bilan Amalga Oshirilgan Ishlar

### 1. Dinamik Parametrlash (Interpolation)
`AppStrings.t` metodi endi `{n}`, `{name}`, `{subject}` kabi parametrlarni qabul qiladi. Bu murakkab gaplarni turli tillar grammatikasiga mos ravishda shakllantirish imkonini beradi.
```dart
AppStrings.t('notif_class_rem_today', {'n': 1, 'subject': 'Math'})
// O'zbekcha: "Bugun 1-dars: Math"
// English: "Period 1: Math is today"
```

### 2. Barcha 21 ta Til Sinxronlashtirildi
Batch processing orqali barcha `.json` fayllari yangi kalitlar bilan boyitildi:
- **Tizim bildirishnomalari**: Har bir tilda dars va vazifa eslatmalari.
- **Forma validatorlari**: Xatolik xabarlari (required, email, length, match).
- **Login/Signup UI**: Barcha bannerlar, tugmalar va yordamchi matnlar.
- **Chat boshqaruvi**: Tarixni tozalash va AI bilan bog'liq interfeys.

### 3. Tizimli Bildirishnomalar (Notification Channels)
Android uchun bildirishnoma kanallari nomlari va tavsiflari ham tanlangan tilga qarab o'zgaradi. Bu Senior darajadagi foydalanuvchi tajribasini (UX) ta'minlaydi.

## Texnik Tafsilotlar

| O'zgartirilgan fayllar | Soni | Holati |
| :--- | :--- | :--- |
| `assets/l10n/*.json` | 21 ta | Yangilandi |
| `lib/core/l10n/app_strings.dart` | 1 ta | Takomillashtirildi |
| `lib/core/services/notification_service.dart` | 1 ta | Tilga bog'landi |
| `lib/core/utils/validators.dart` | 1 ta | Tilga bog'landi |

> [!IMPORTANT]
> Har bir tilda JSON sintaksisi va parametrlar butunligi (integrity) tekshirildi. Hech qanday "raw key" foydalanuvchi ko'ziga ko'rinmaydi.

## Tekshirish
Sozlamalardan istalgan tilni (masalan, **Arab**, **Rus** yoki **Ispan**) tanlang va ilovaning barcha burchaklarini (login, bildirishnomalar, xatoliklar) tekshirib ko'ring. Hamma joy professional darajada tarjima qilingan.
