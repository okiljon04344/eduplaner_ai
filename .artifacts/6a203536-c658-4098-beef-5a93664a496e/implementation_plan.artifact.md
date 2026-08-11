# Mavzular Almashinuvi va Vizual Barqarorlikni Tuzatish Rejasi

Ushbu reja ilovadagi Light va Dark mode rejimlari o'rtasidagi ziddiyatlarni (ranglar almashib qolishi, miltillash) bartaraf etish hamda dizaynni professional (Senior) darajaga olib chiqishni maqsad qilgan.

## Muammo Tahlili
Hozirgi vaqtda `AppColors` klassidagi ranglar global statik o'zgaruvchilar sifatida saqlangan. Foydalanuvchi rejimi o'zgartirganda, bu o'zgaruvchilar qiymati yangilanadi. Biroq, `MaterialApp` bir vaqtning o'zida ikkala mavzuni (Light va Dark) qurishga harakat qilganda, ular bir-birining ranglarini "o'g'irlab" qo'ymoqda. Bu esa vizual chalkashliklarga olib keladi.

## Foydalanuvchi Tasdig'i Kerak
> [!IMPORTANT]
> Dizayn o'zgarmaydi, faqat Dark mode-da sarlavha (header) qop-qora bo'lib qolmasligi uchun unga chiroyli binafsha gradient beriladi. Shuningdek, tizim paneli (status bar) ranglari avtomatlashtiriladi.

## Taklif etilayotgan O'zgarishlar

### 1. Core Architecture (Mavzu Mantiqi)

#### [MODIFY] [app_colors.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/core/theme/app_colors.dart)
- Ranglarni tanlash mantiqini statik o'zgaruvchilardan metodlarga o'tkazish. `AppColors.background(brightness)` ko'rinishida har bir rejim uchun aniq rang qaytariladi.
- `_darkHeroHomeGradient` ni qora rangdan binafsha neon gradientga o'zgartirish.

#### [MODIFY] [app_theme.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/core/theme/app_theme.dart)
- `ThemeData` qurilayotganda global holatga qaram bo'lmasligi uchun ranglarni to'g'ridan-to'g'ri `Brightness` orqali olish.
- `AppBarTheme` ichida `systemOverlayStyle` ni sozlash, shunda batareya va soat belgilari avtomatik ravishda (oq yoki qora) o'zgaradi.

### 2. Feature Widgets (Interfeys)

#### [MODIFY] [greeting_header.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/features/home/widgets/greeting_header.dart)
- "Salom, admin" matni va pastki yozuvlar uchun ranglar mantig'ini (ternary operator) to'g'irlash.

#### [MODIFY] [home_screen.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/features/home/screens/home_screen.dart)
- `_HeroHeader` vidjetida yumaloq burchaklar va gradientlarni ikkala rejim uchun ham chiroyli qilish.

#### [MODIFY] [main.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/main.dart)
- `SystemChrome` orqali qattiq yozilgan ranglarni olib tashlash (mavzu tizimi buni o'zi eplaydi).

## Tekshirish Rejasi

### Qo'lda Tekshirish
1. **Rejimlar almashinuvi**: Sozlamalardan Light va Dark mode'ga o'tib, fon va sarlavha ranglarini tekshirish.
2. **Status Bar**: Tepa panel ranglari fon oq bo'lganda qora, qora bo'lganda oq chiqayotganini ko'rish.
3. **Sarlavha (Header)**: Dark mode'da sarlavha qora fon bilan qo'shilib ketmayotganini (gradient borligini) tekshirish.

Ushbu rejani ma'qullasangiz, amalga oshirishga kirishaman.
