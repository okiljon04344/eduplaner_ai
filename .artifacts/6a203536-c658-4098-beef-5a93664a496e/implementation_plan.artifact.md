# EduPlanner AI — To'liq Taxlil va Tuzatish Rejasi (Senior Audit)

Ushbu hujjat loyihaning barcha qismlarini to'liq audit qilish natijasida aniqlangan kamchiliklar va ularni bartaraf etish rejasini o'z ichiga oladi. Maqsad — ilovani "Production-ready" (yakuniy mahsulot) holatiga keltirish.

## Tadqiqot Natijalari va Muammolar

### 1. Mahalliylashtirish (i18n) — *Eng katta muammo*
Ilovada 21 ta til qo'llab-quvvatlanadi, lekin kod ichida yuzlab yaponcha matnlar (hardcoded) qolib ketgan:
- **Xatolik xabarlari**: Barcha repository va notifierlarda xatoliklar faqat yapon tilida.
- **Biznes mantiq**: Dars jadvalidagi kunlar (`月`, `火`...) qattiq yozib qo'yilgan, bu boshqa tillarda "Bugungi darslar" chiqmasligiga sabab bo'ladi.
- **AI Promptlari**: AI ga beriladigan ko'rsatmalar faqat yapon tilida, bu o'zbek yoki ingliz tilidagi foydalanuvchilar uchun AI javob sifati pasayishiga olib keladi.

### 2. UI/UX Barqarorligi
- **Inconsistent Design**: Turli vidjetlarda har xil burchak radiuslari (`borderRadius`) va soyalar (`boxShadow`) ishlatilgan.
- **Manual Theme Checks**: Kodda juda ko'p joyda `AppColors.isDark ? ...` sharti ishlatilgan. Bu Senior darajadagi kodda `Theme.of(context)` yoki `AppColors` dagi abstraksiyalar orqali hal qilinishi kerak.

### 3. Arxitektura va Samaradorlik
- **Auth Stream**: Har safar auth holati o'zgarganda foydalanuvchi hujjatini qayta-qayta yuklaydi (optimization kerak).
- **Error Handling**: Ba'zi xatolar faqat konsolga (`debugPrint`) chiqariladi, foydalanuvchiga tushunarli xabar berilmaydi.

## Tavsiya etilayotgan Tuzatishlar

### Phase 1: To'liq i18n Migratsiyasi (4-6 soat)
- [ ] Barcha `Exception('...')` matnlarini kalit so'zlarga (key) almashtirish.
- [ ] Dars jadvalidagi kun nomlarini raqamlarga yoki tilga bog'liq bo'lmagan konstantalarga o'tkazish.
- [ ] AI promptlarini foydalanuvchi tiliga moslab dinamik qilish.

### Phase 2: UI Standardizatsiyasi (2-3 soat)
- [ ] `AppColors` klassida "Production Tokens" tizimini yaratish (barcha burchak va soyalar uchun).
- [ ] Manual `isDark` tekshiruvlarini markazlashtirish.
- [ ] Divider va Card uslublarini butun ilova bo'ylab bir xil qilish.

### Phase 3: "Senior" Kod Sifati (2 soat)
- [ ] `AuthRepository` dagi streamni keshlashtirish (memoization).
- [ ] `analysis_options.yaml` ga qat'iyroq qoidalar (lints) qo'shish.
- [ ] Foydalanuvchi uchun "Global Error Handler" (toast yoki dialog) tizimini yaxshilash.

## Vaqt Smeta (Estimation)

| Bosqich | Tavsif | Taxminiy vaqt |
| :--- | :--- | :--- |
| **I bosqich** | To'liq mahalliylashtirish va AI promptlar | 5 soat |
| **II bosqich** | UI/UX va Dizayn tizimi barqarorligi | 3 soat |
| **III bosqich** | Arxitektura va samaradorlikni oshirish | 2 soat |
| **Jami** | **Mukammal holatga keltirish** | **~10 soat** |

---

## Ochiq Savollar
- [ ] AI chatida javoblar har doim foydalanuvchi tanlagan tilda bo'lishini qat'iy talab qilamizmi?
- [ ] Shanba va Yakshanba kunlari uchun maxsus "Dam olish kuni" UI-ni qo'shishni xohlaysizmi?

> [!CAUTION]
> Ushbu o'zgarishlar ilovaning deyarli barcha fayllariga ta'sir qiladi. Tizimli yondashuv talab etiladi.

Ushbu taxlil va reja ma'qulmi? Agar rozilik bersangiz, I bosqichdan — eng dolzarb muammo bo'lgan mahalliylashtirishdan boshlayman.
