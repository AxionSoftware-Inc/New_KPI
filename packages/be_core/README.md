# 🧠 Business Ecosystem Core (`be_core`)

> **Business Ecosystem** mikroyadro (Microkernel) va voqealarga asoslangan (Event-Driven) markaziy kutubxonasi.
> Barcha ilovalar (`KPI`, `CRM`, `Moliya`) ushbu yadro ustiga qurilgan va barcha plaginlar shu modul orqali boshqariladi.

---

## 🏛 Arxitektura Falsafasi

`be_core` mikroyadro arxitekturasining oltin qoidalariga asoslangan:
1. **Yadro o'zgarmasligi:** Asosiy yadro faqat eng muhim bazaviy operatsiyalarni (xotira, ruxsatlar, aloqa shinası) bajaradi.
2. **Qat'iy bo'linish (Zero Tight Coupling):** Ilovalar bir-biriga qaram emas. Ular faqat `EventBus` orqali muloqot qiladi.
3. **Plaginlar xavfsizligi:** Har qanday plagin qulab tushsa yoki o'chirilsa ham, yadro ishlashda davom etadi.

---

## 📂 Yadro Modullari Strukturasi

| Modul | Fayl | Tavsifi |
| :--- | :--- | :--- |
| **EventBus** | `lib/src/plugin.dart` | Butun ekotizim bo'yicha hodisalarni tarqatuvchi markaziy voqealar shinası. |
| **PluginManager** | `lib/src/plugin.dart` | Plaginlarni ro'yxatga olish, yoqish/o'chirish va buyruqlarini ijro etish. |
| **StandardStore** | `lib/src/store.dart` | JSON asosidagi tezkor, keshlanuvchi va xavfsiz fayl xotirasi (CRUD). |
| **SecurityManager** | `lib/src/security.dart` | RBAC (Role-Based Access Control) huquqlar matritsasi. |
| **UserProfile** | `lib/src/user_profile.dart` | Standart 5 ta xodim profili va profil almashtirish logikasi. |
| **UzbekNlp** | `lib/src/uzbek_nlp.dart` | O'zbek tili matnlarini tahlil qilish, raqam va muddatlarni ajratish. |
| **StandardAppServer** | `lib/src/server.dart` | Standart HTTP REST API serveri (`/execute`, `/schema`, `/health`, `/export`). |

---

## ⚡ Ekotizim Voqealar Shinası (EventBus Protokollari)

Ilovalar o'rtasida to'g'ridan-to'g'ri bog'liqlik yo'q. Muloqot faqat `EcosystemEvent` orqali amalga oshadi:

```dart
// 1. Voqeani tarqatish (Publish)
await EventBus.instance.publish(EcosystemEvent(
  name: 'kpi_task_approved',
  sourceApp: 'kpi',
  payload: {
    'task_id': 'task_101',
    'assigned_to': 'Ali',
    'bonus_amount': 500000.0,
    'task_name': 'Sayt dizayni',
  },
));

// 2. Voqeaga obuna bo'lish (Subscribe)
EventBus.instance.subscribe('kpi_task_approved', (event) async {
  print('Bonus to\'lanishi kerak: ${event.payload['bonus_amount']} so\'m');
});
```

### 📡 Standart Ekotizim Voqealari:

| Voqea nomi (`name`) | Manba (`sourceApp`) | Payload tarkibi | Maqsadi |
| :--- | :--- | :--- | :--- |
| `kpi_task_approved` | `kpi` | `task_id`, `assigned_to`, `bonus_amount`, `task_name` | Vazifa tasdiqlanganda Moliyaga chiqim yo'llash |
| `crm_lead_won` | `crm` | `lead_id`, `lead_name`, `product`, `budget` | Bitim yutilganda Moliyaga kassa tushumi yozish |
| `finance_expense` | `finance` | `amount`, `to`, `category`, `note` | Kassadan xarajat chiqim qilinganda |
| `finance_income` | `finance` | `amount`, `from`, `category`, `note` | Kassaga tushum kirim qilinganda |

---

## 🛠 Yangi Plagin Yozish Qo'llanmasi (Step-by-Step)

Kelajakda istalgan 100 lab yangi funksiyani quyidagi 3 qadamda qo'shasiz:

### 1-qadam: Plagin Manifestini e'lon qilish
```dart
final myPlugin = EcosystemPlugin(
  id: 'plugin_telegram_bot',
  name: 'Telegram Bildirishnomalar',
  description: 'Barcha voqealar haqida Telegram guruhga xabar yuborish',
  targetApps: ['all'],
  iconName: 'send',
  metadata: {'bot_token': '123456:ABC...', 'chat_id': '-100...'},
);
```

### 2-qadam: `PluginHandler` sinfini yozish
```dart
class TelegramBotPluginHandler implements PluginHandler {
  @override
  String get pluginId => 'plugin_telegram_bot';

  @override
  Future<void> onInit(PluginManager manager) async {
    // Voqealarga quloq solish
    EventBus.instance.subscribeAll((event) async {
      if (manager.isPluginActive(pluginId)) {
        await _sendToTelegram('Yangi voqea: ${event.name}');
      }
    });
  }

  @override
  Future<void> onEvent(EcosystemEvent event) async {}

  @override
  Future<Map<String, dynamic>> executeCommand(String command, Map<String, dynamic> params) async {
    if (command == 'send_test_message') {
      return {'success': true, 'sent_at': DateTime.now().toIso8601String()};
    }
    return {'success': false, 'error': 'Noma\'lum buyruq'};
  }

  Future<void> _sendToTelegram(String text) async {
    // Telegram Bot API ga HTTP POST so'rovi
  }
}
```

### 3-qadam: `PluginManager`ga ro'yxatdan o'tkazish
```dart
pluginManager.registerPlugin(myPlugin);
pluginManager.registerHandler(TelegramBotPluginHandler());
```
Tamom! Plagin ilovaning Profil sahifasidagi **Plaginlar Markazi**da avtomatik paydo bo'ladi va uni switch orqali yoqish/o'chirish mumkin bo'ladi.

---

## 🛡 Xavfsizlik va Chegaralar (Guardrails)

AI va avtomatlashtirishda inson nazoratini ta'minlash uchun qat'iy chegaralar o'rnatilgan:
- `max_bonus_limit`: AI orqali topshiriq berilganda 1 ta vazifa uchun berilishi mumkin bo'lgan maksimal bonus (standart: 2 000 000 so'm).
- `max_payout_limit`: Ekotizim bridge orqali moliyadan avtomatik chiqim qilinishi mumkin bo'lgan maksimal summa (standart: 3 000 000 so'm). Haddan ortiq summalar avtomatik **BLOCKED** statusiga tushadi.

---

## 🧪 Testlarni Ishga Tushirish

```bash
# 1. Barcha plagin va EventBus testlari (23 ta test)
dart run bin/test_core.dart

# 2. End-to-End Ekotizim simulyatsiyasi (14 ta test)
dart run bin/test_plugin_ecosystem_e2e.dart

# 3. Kod tahlili (0 ta ogohlantirish)
dart analyze
```
