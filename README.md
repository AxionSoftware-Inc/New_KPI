# 🎯 New_KPI: Minimalist KPI, Vazifalar va AI Ekosistema Ilovasi

> **Business Ecosystem** loyihasining vazifalar boshqaruvi, xodimlar samaradorligi (KPI) va AI integratsiyasi ilovasi.
> GitHub Repozitoriy: [https://github.com/AxionSoftware-Inc/New_KPI.git](https://github.com/AxionSoftware-Inc/New_KPI.git)

---

## 🏛 Arxitektura va Dizayn

Dastur **Mikroyadro (Microkernel)** va **Qat'iy 3-Tab Minimalist** standartida qurilgan:

```
┌─────────────────────────────────────────────────────────────┐
│  APPBAR: [✓ KPI & Vazifalar]   [👤 Ali (Xodim)]   [✨ AI]   [:8081] │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [Tab 0: Vazifalar]      [Tab 1: Yangi Vazifa]  [Tab 2: Profil]│
│  ─────────────────      ────────────────────   ───────────────│
│  • Qidiruv & Filtrlar   • AI Tezkor Buyruq     • Xodim Profili│
│  • Bosqichlar (Steps)   • Tayyor namunalar     • Rol Sinash   │
│  • Topshirish           • Xodim & Bonus        • Server Porti │
│  • Tasdiqlash / Qaytar  • Nazorat punktlari    • Plaginlar    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Plaginlar Tizimi (Microkernel Extensions)

Ilova ichida ortiqcha kod yo'q. Qo'shimcha barcha funksiyalar plagin sifatida ishlaydi:

1. **O'zbekcha AI Ekosistema Assistent (`plugin_uzbek_ai`):**
   - Tabiiy tildagi buyruqlarni qabul qiladi: *"Ali ga saytni bitirish vazifasini topshir va bitirsa oyligiga 10% qo'sh"*.
   - Alining oyligidan 10% bonusni (**500 000 so'm**) avtomatik hisoblaydi.
   - **Chegara (Guardrail):** Maksimal bonus 2 000 000 so'mdan oshib ketsa, uni avtomatik chegaraga tushiradi va ogohlantiradi.
2. **Ekotizim Integratsiyasi (`plugin_ecosystem_bridge`):**
   - Vazifa rahbar tomonidan tasdiqlanganda (`approve`), ushbu hodisa **Moliya ilovasiga (:8083)** avtomatik kassa chiqimi sifatida yuboriladi.

---

## 🔐 Rollar va RBAC Xavfsizlik Matritsasi

| Harakat | Oddiy Xodim (Ali) | Jamoa Rahbari | Direktor (Boshqaruv) |
| :--- | :---: | :---: | :---: |
| Vazifani ko'rish | Faqat o'zinikini | O'z bo'liminikini | Barchasini |
| Vazifani topshirish (`submit`) | ✅ | ✅ | ✅ |
| O'z vazifasini tasdiqlash | ❌ (Taqiqlangan) | ❌ (Taqiqlangan) | ✅ |
| Xodim vazifasini tasdiqlash (`approve`)| ❌ | ✅ | ✅ |
| Vazifani o'chirish | ❌ | ❌ | ✅ |

---

## 🌐 Microservice HTTP API (:8081)

KPI ilovasi fon rejimida lokal server sifatida ishlay oladi:

- `GET http://localhost:8081/health` - Server va vazifalar soni holati.
- `GET http://localhost:8081/schema` - Barcha mavjud tool va parametrlar.
- `GET http://localhost:8081/export` - Barcha ma'lumotlar JSON eksporti.
- `POST http://localhost:8081/execute` - Funksiya bajarish:
  ```json
  {
    "action": "kpi_add",
    "params": {
      "name": "Yangi modul ishlab chiqish",
      "assigned_to": "Ali",
      "bonus_amount": 500000,
      "deadline": "3 kunda"
    }
  }
  ```

---

## 🚀 O'rnatish va Ishga Tushirish (Mustaqil / Standalone)

Ilova to'liq mustaqil (o'z ichida `packages/be_core` mavjud):

```bash
# 1. Bog'liqliklarni yuklab olish
flutter pub get

# 2. Ilovani ishga tushirish (Windows / Chrome / Android)
flutter run -d windows

# 3. Testlarni tekshirish (43 ta test)
dart run bin/test_rbac_kpi.dart
dart run bin/test_ai_edge_cases.dart
```
