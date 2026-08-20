# EduPlanner AI — Android Studio ichidagi Gemini agent uchun ko'rsatma

Bu faylni Android Studio'dagi Gemini/AI yordamchisiga **shu loyihada har qanday
ish boshlashdan oldin** o'qitib bering (masalan: "GEMINI_CONTEXT.md faylini
o'qi va shunga rioya qil" deb prompt yozing). Bu loyihada bir vaqtda ikkita AI
(Claude Code va siz) ishlayapti, va oldin bir necha marta bitta muammo
takrorlangan — shu faylning maqsadi shuni oldini olish.

## Nima bo'lgan edi (takrorlanmasin)

`lib/core/theme/app_colors.dart` va `lib/core/theme/app_theme.dart` fayllari
bir necha marta **AGENTS.md faylining eski (indigo/binafsha) dizayn
tokenlaridan** qayta generatsiya qilingan yoki "tozalangan" (ishlatilmayotgan
deb o'ylab, aslida ishlatilayotgan konstantalar o'chirilgan). Natijada:

1. Butun ilova binafsha rangga qaytib qolgan — bugungi (2026-08-19) yashil-neon
   qayta dizayn ishi bekor bo'lgan.
2. `AppColors.cyan`, `AppColors.amber`, `AppColors.subjectMath`,
   `AppColors.accentText`, `AppColors.avatarGradient` va shunga o'xshash
   ~20-40 ta konstanta/getter o'chirilib, ~13 fayl kompilyatsiya xatosi bergan.

**Sabab:** `AGENTS.md`dagi "Design tokens" bo'limi eski qiymatlarni ko'rsatib
turgan edi (endi bu tuzatildi — pastga qarang), va regenerator/tozalovchi shu
eski hujjatni "haqiqat manbai" deb qabul qilgan, `app_colors.dart`ning o'zidagi
haqiqiy qiymatlarni va uni ishlatuvchi fayllarni tekshirmagan.

## Qat'iy qoidalar

1. **`lib/core/theme/app_colors.dart` — yagona haqiqat manbai.** Agar
   `AGENTS.md` yoki boshqa hujjat shu fayl bilan ziddiyatda bo'lsa, **fayl
   g'olib chiqadi**, hujjat emas. Hech qachon bu faylni boshqa hujjat asosida
   "qayta generatsiya" qilmang.

2. **`AppColors`dagi hech bir statik maydon/konstanta/getterni o'chirmang**,
   hatto u "ishlatilmayapti" deb ko'ringan taqdirda ham — avval albatta shu
   buyruqni ishga tushiring:
   ```
   grep -rn "AppColors\.<nom>" lib/
   ```
   Agar natija bo'lsa (deyarli har doim bo'ladi — bu fayl 40+ fayl tomonidan
   ishlatiladi), o'chirmang. Faqat haqiqatan hech qayerda ishlatilmagan token
   qo'shilishi mumkin (masalan yangi funksiya uchun).

3. **Rang tizimi = Green Neon.** Asosiy brend rangi
   `primary = Color(0xFF06D6A0)` (yashil), **binafsha/indigo emas**
   (`0xFF4F46E5`, `0xFF7C3AED`, `0xFFA855F7` kabi qiymatlarni **hech qachon**
   qaytarmang — bular ataylab olib tashlangan "AI-generated app" ko'rinishi
   edi, foydalanuvchi buni aniq talab qilib o'zgartirgan).

4. **Dark/Light ikkalasi ham real ishlatiladi.** `AppColors`dagi mutable
   static maydonlar (`background`, `textPrimary` va h.k.) `applyBrightness()`
   orqali qayta tayinlanadi — bu ataylab qilingan arxitektura (370+ chaqiruv
   joyini `Theme.of(context)`ga o'tkazish o'rniga). Buni "soddalashtirish"
   uchun `Theme.of(context)`ga o'tkazmang.

5. **Hero panellarda (gradient fon ustidagi) matn rangi doim
   `AppColors.textOnHero` yoki teng ma'noli theme-aware token bo'lishi kerak**
   — hech qachon `Colors.white`ni to'g'ridan-to'g'ri yozmang. Sabab: light
   rejimda hero fonlar och (deyarli oq) rangda, shuning uchun oq matn
   ko'rinmay qoladi. Bu bug bir necha marta topilib tuzatilgan edi.

6. **Har qanday `app_colors.dart`/`app_theme.dart` o'zgarishidan keyin
   albatta ishga tushiring:**
   ```
   flutter analyze
   flutter test
   ```
   Ikkalasi ham toza/o'tgan bo'lishi shart, aks holda o'zgarish qaytarilsin.

## Agar rostdan ham tozalash/soddalashtirish kerak bo'lsa

Yaxshi niyat bilan fayl uzun/murakkab ko'rinsa ham, uni **Claude Code bilan
muvofiqlashtirmasdan** o'zgartirmang — buni foydalanuvchidan so'rang: "bu
fayl X, Y, Z konstantalarini olib tashlashni xohlaysizmi, avval boshqa AI
sessiyasi bilan kelishib olaylikmi?" Ikkala AI bir vaqtda shu fayllarga
tegsa, natija — foydalanuvchi ikki marta ko'rgan build xatolari (2026-08-19
kuni ikki marta sodir bo'ldi).

## Joriy holat (2026-08-19 kuni tugagan)

- To'liq yashil-neon qayta dizayn: Home, Schedule, Tasks, AI, Settings,
  Login/Signup, Landing, Onboarding ekranlari.
- Light/dark rejim bug'i tuzatilgan (`app_theme.dart`da ikkala tema getter
  ham har doim baholanib, oxirgisi ranglarni qayta yozib qo'yayotgan edi).
- `AGENTS.md`ning "Design tokens" bo'limi yangilangan — endi joriy yashil
  qiymatlarni ko'rsatadi va yuqoridagi ogohlantirishni o'z ichiga oladi.
