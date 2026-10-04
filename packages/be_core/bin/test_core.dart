import 'dart:io';
import 'package:be_core/be_core.dart';

void main() async {
  print('================================================================');
  print('   BUSINESS ECOSYSTEM CORE: PLAGIN VA EVENT BUS TESTLARI');
  print('================================================================');

  int passed = 0;
  int failed = 0;

  void test(String title, bool condition) {
    if (condition) {
      print('  [PASS] $title');
      passed++;
    } else {
      print('  [FAIL] $title');
      failed++;
    }
  }

  // 1. Standart Profillar
  final profiles = UserProfile.defaultProfiles;
  test('1.1. Standart profillar 5 ta asosiy rolni o\'z ichiga oladi', profiles.length == 5);
  test('1.2. Direktor profili mavjud', profiles.any((p) => p.role == UserRole.director));
  test('1.3. Kassir Malika profili mavjud', profiles.any((p) => p.role == UserRole.cashier));

  // 2. ProfileManager Store va almashtirish
  final tempProfilePath = '${Directory.systemTemp.path}/core_test_profile_${DateTime.now().millisecondsSinceEpoch}.json';
  final profileStore = await StandardStore.open(tempProfilePath);
  final profManager = ProfileManager(store: profileStore);
  await profManager.init();

  test('2.1. Boshlang\'ich profil direktor', profManager.current.role == UserRole.director);

  final ali = UserProfile.defaultProfiles.firstWhere((p) => p.name.contains('Ali'));
  await profManager.switchProfile(ali);
  test('2.2. Profil Ali (Xodim)ga almashtirildi', profManager.current.name.contains('Ali') && profManager.current.role == UserRole.employee);

  // 3. Plagin Menejeri (Microkernel Plugin Engine)
  final tempPluginPath = '${Directory.systemTemp.path}/core_test_plugins_${DateTime.now().millisecondsSinceEpoch}.json';
  final pluginStore = await StandardStore.open(tempPluginPath);
  final pluginManager = PluginManager(store: pluginStore);
  await pluginManager.init();

  final allPlugins = pluginManager.getAllPlugins();
  test('3.1. Standart 6 ta plagin ro\'yxatdan o\'tdi', allPlugins.length == 6);
  test('3.2. Ekotizim Bridge integratsiya plagini mavjud', allPlugins.any((p) => p.id == 'plugin_ecosystem_bridge'));
  test('3.3. O\'zbekcha AI assistent plagini mavjud', allPlugins.any((p) => p.id == 'plugin_uzbek_ai'));

  // 4. Event Bus (Hodisalar shinası)
  bool eventReceived = false;
  String receivedPayloadName = '';

  EventBus.instance.subscribe('test_event', (event) async {
    eventReceived = true;
    receivedPayloadName = event.payload['item_name'] ?? '';
  });

  await EventBus.instance.publish(EcosystemEvent(
    name: 'test_event',
    sourceApp: 'kpi',
    payload: {'item_name': 'Test Vazifa'},
  ));

  test('4.1. EventBus orqali hodisa tarqatildi va qabul qilindi', eventReceived);
  test('4.2. Hodisa yuki (payload) to\'g\'ri uzatildi', receivedPayloadName == 'Test Vazifa');

  // 5. Uzbek AI Plugin: Vazifa buyrug'ini tahlil qilish va oylikdan 10% bonus hisoblash
  final aiResult = await pluginManager.executeCommand(
    'plugin_uzbek_ai',
    'parse_task_order',
    {'prompt': 'Ali ga saytni bitirish vazifasini topshir va bitirsa oyligiga 10% qo\'sh'},
  );

  test('5.1. AI buyrug\'i muvaffaqiyatli tahlil qilindi', aiResult['success'] == true);
  test('5.2. Biriktirilgan xodim Ali ekanligi aniqlandi', aiResult['assigned_to'] == 'Ali');
  test('5.3. 10% oylik bonus 500,000 so\'m deb to\'g\'ri hisoblandi (5 mln oylikdan 10%)', (aiResult['bonus_amount'] as num).toDouble() == 500000.0);
  test('5.4. Vazifa nomi tozalab olindi', (aiResult['name'] as String).isNotEmpty);

  // 6. Uzbek AI Plugin: Xavfsizlik chegarasi (Guardrail limit)
  final aiCappedResult = await pluginManager.executeCommand(
    'plugin_uzbek_ai',
    'parse_task_order',
    {'prompt': 'Ali ga yangi modul yaratishni buyur va 50% qo\'sh'}, // 50% = 2.5 mln > 2 mln limit
  );

  test('6.1. Chegaradan oshgan bonus aniqlandi (is_capped)', aiCappedResult['is_capped'] == true);
  test('6.2. Bonus avtomatik chegara (2 000 000 so\'m)ga tushirildi', (aiCappedResult['bonus_amount'] as num).toDouble() == 2000000.0);
  test('6.3. Foydalanuvchiga ogohlantirish berildi', (aiCappedResult['warning'] as String).contains('chegaradan'));

  // 7. Ecosystem Bridge Plugin: KPI tasdiqlanganda Moliyaga chiqim yo'naltirish
  final bridgeHandler = pluginManager.getHandler('plugin_ecosystem_bridge') as EcosystemBridgePluginHandler;

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

  final logs = bridgeHandler.bridgeLogs;
  test('7.1. Bridge KPI tasdiqlash hodisasini qayd etdi', logs.isNotEmpty);
  test('7.2. Bonus summasi (500 000 so\'m) qayd etildi', logs.last['amount'] == 500000.0);
  test('7.3. Qabul qiluvchi Ali sifatida ko\'rsatildi', logs.last['recipient'] == 'Ali');

  // 8. CRM Bitim yutilganda Moliyaga tushum yo'naltirish
  await EventBus.instance.publish(EcosystemEvent(
    name: 'crm_lead_won',
    sourceApp: 'crm',
    payload: {
      'lead_id': 'lead_501',
      'lead_name': 'Akmal',
      'product': 'ERP Tizimi',
      'budget': 15000000.0,
    },
  ));

  test('8.1. CRM bitimi tushumi Bridge orqali qayd etildi', logs.any((l) => l['payer'] == 'Akmal'));
  test('8.2. Savdo tushumi 15 mln so\'m deb belgilandi', logs.firstWhere((l) => l['payer'] == 'Akmal')['amount'] == 15000000.0);

  // 9. Bridge Payout Limit (Chegaradan oshgan yirik chiqimni to'xtatish)
  await EventBus.instance.publish(EcosystemEvent(
    name: 'kpi_task_approved',
    sourceApp: 'kpi',
    payload: {
      'task_id': 'task_999',
      'assigned_to': 'Sardor',
      'bonus_amount': 10000000.0, // 10 mln > 3 mln limit
      'task_name': 'Haddan tashqari katta bonus',
    },
  ));

  test('9.1. Chegaradan oshgan chiqim xavfsizlik uchun bloklandi (BLOCKED)', logs.any((l) => l['status'] == 'BLOCKED'));

  // Tozalash
  try {
    File(tempProfilePath).deleteSync();
    File(tempPluginPath).deleteSync();
  } catch (_) {}

  print('----------------------------------------------------------------');
  print('  NATIJA: Jami ${passed + failed} ta testdan $passed tasi MUVAFFAQITYATLI O\'TDI (Xatolar: $failed)');
  print('================================================================');

  if (failed > 0) exit(1);
}
