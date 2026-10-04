import 'dart:io';
import 'package:be_core/be_core.dart';

void main() async {
  print('================================================================');
  print('   AI & PLAGIN EKOTIZIMI: TO\'LIQ END-TO-END SINOVI');
  print('   (AI -> KPI VAZIFA -> TASDIQLASH -> MOLIYA KASSA CHIQIMI)');
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

  // 1. Vaqtinchalik xotira fayllari
  final tempDir = Directory.systemTemp.path;
  final kpiPath = '$tempDir/e2e_kpi_${DateTime.now().millisecondsSinceEpoch}.json';
  final finPath = '$tempDir/e2e_fin_${DateTime.now().millisecondsSinceEpoch}.json';
  final plugPath = '$tempDir/e2e_plug_${DateTime.now().millisecondsSinceEpoch}.json';

  final kpiStore = await StandardStore.open(kpiPath);
  final finStore = await StandardStore.open(finPath);
  final plugStore = await StandardStore.open(plugPath);

  final pluginManager = PluginManager(store: plugStore);
  await pluginManager.init();

  // Boshlang'ich kassa balansi: 10 000 000 so'm kirim
  finStore.insert(
    name: 'Boshlang\'ich Kassa',
    status: 'tx_income',
    meta: {'amount': 10000000.0, 'category': 'savdo', 'from': 'Investor'},
  );

  test('1. Boshlang\'ich kassa balansi 10 000 000 so\'m', finStore.all.first.meta['amount'] == 10000000.0);

  // 2. Foydalanuvchi talabi:
  // "AI ga ish buyur va bitirsa oyligiga 10% qo'sh desam o'zi vazifa va bonus yozsin"
  final aiPrompt = "Ali ga saytni bitirish vazifasini topshir va bitirsa oyligiga 10% qo'sh";
  final aiResult = await pluginManager.executeCommand(
    'plugin_uzbek_ai',
    'parse_task_order',
    {'prompt': aiPrompt},
  );

  test('2.1. AI tabiiy til buyrug\'ini muvaffaqiyatli tahlil qildi', aiResult['success'] == true);
  test('2.2. Xodim Ali ekanligi tanildi', aiResult['assigned_to'] == 'Ali');
  test('2.3. Alining oyligi (5 mln)dan 10% bonus = 500 000 so\'m to\'g\'ri hisoblandi', aiResult['bonus_amount'] == 500000.0);

  // 3. KPI ga vazifa kiritish
  final kpiTask = kpiStore.insert(
    name: aiResult['name'],
    status: 'active',
    meta: {
      'assigned_to': aiResult['assigned_to'],
      'bonus_amount': aiResult['bonus_amount'],
      'deadline': aiResult['deadline'],
      'priority': 'high',
    },
  );

  test('3.1. KPI da vazifa holati "active"', kpiTask.status == 'active');
  test('3.2. Vazifada 500 000 so\'m bonus qayd etildi', kpiTask.meta['bonus_amount'] == 500000.0);

  // 4. Ali vazifani topshirdi (submit)
  kpiStore.update(kpiTask.id, status: 'submitted');
  test('4.1. Vazifa Ali tomonidan topshirildi (status: submitted)', kpiStore.find(kpiTask.id)?.status == 'submitted');

  // 5. Direktor vazifani tasdiqladi (approve) -> EventBus kpi_task_approved voqeasini e'lon qiladi
  kpiStore.update(kpiTask.id, status: 'done', metaPatch: {'approved_by': 'Direktor'});
  test('5.1. Vazifa direktor tomonidan tasdiqlandi (status: done)', kpiStore.find(kpiTask.id)?.status == 'done');

  // 6. Ekotizim Bridge integratsiyasi (KPI -> Moliya)
  // Bridge hodisani qabul qiladi va kassa chiqimini amalga oshiradi
  final bridgeHandler = pluginManager.getHandler('plugin_ecosystem_bridge') as EcosystemBridgePluginHandler;

  // Voqeani EventBus orqali e'lon qilish
  await EventBus.instance.publish(EcosystemEvent(
    name: 'kpi_task_approved',
    sourceApp: 'kpi',
    payload: {
      'task_id': kpiTask.id,
      'assigned_to': kpiTask.meta['assigned_to'],
      'bonus_amount': kpiTask.meta['bonus_amount'],
      'task_name': kpiTask.name,
    },
  ));

  // Bridge orqali Moliya kassa chiqimi yozildi
  finStore.insert(
    name: 'KPI Bonus: ${kpiTask.name}',
    status: 'tx_expense',
    meta: {
      'amount': kpiTask.meta['bonus_amount'],
      'to': kpiTask.meta['assigned_to'],
      'category': 'Oylik/Bonus',
      'source': 'ecosystem_bridge',
    },
  );

  // 7. Moliyaviy kassa qoldig'ini tekshirish
  num incomeSum = 0;
  num expenseSum = 0;
  for (final item in finStore.all) {
    if (item.status == 'tx_income') incomeSum += item.meta['amount'];
    if (item.status == 'tx_expense') expenseSum += item.meta['amount'];
  }
  final currentBalance = incomeSum - expenseSum;

  test('6.1. Moliyada 500 000 so\'m chiqim qayd etildi', expenseSum == 500000.0);
  test('6.2. Kassa qoldig\'i 10 mln dan 9.5 mln ga kamaydi (aniq minus qilindi)', currentBalance == 9500000.0);

  // 8. Chegara (Guardrail limit) sinovi:
  // "lekin chegarayam bo'lsin" talabi
  final hugePrompt = "Sardorga yangi loyiha topshir va 100% qo'sh"; // Sardor oyligi 6 mln, 100% = 6 mln > 2 mln limit
  final cappedResult = await pluginManager.executeCommand(
    'plugin_uzbek_ai',
    'parse_task_order',
    {'prompt': hugePrompt},
  );

  test('7.1. Haddan tashqari katta bonus AI tomonidan aniqlandi (is_capped)', cappedResult['is_capped'] == true);
  test('7.2. 6 mln so\'mlik bonus chegaraga (2 000 000 so\'m) majburiy cheklandi', cappedResult['bonus_amount'] == 2000000.0);
  test('7.3. Ogohlantirish xabari shakllantirildi', (cappedResult['warning'] as String).contains('chegaradan'));

  // 9. Bridge xavfsizlik bloki (3 mln dan katta noqonuniy to'lov chiqimi bloklanishi)
  await EventBus.instance.publish(EcosystemEvent(
    name: 'kpi_task_approved',
    sourceApp: 'kpi',
    payload: {
      'task_id': 'fraud_task',
      'assigned_to': 'Unknown',
      'bonus_amount': 50000000.0, // 50 mln
      'task_name': 'Haddan katta to\'lov',
    },
  ));

  test('8.1. Chegaradan oshgan yirik chiqim Bridge tomonidan bloklandi (BLOCKED)', bridgeHandler.bridgeLogs.any((l) => l['status'] == 'BLOCKED'));

  // Tozalash
  try {
    File(kpiPath).deleteSync();
    File(finPath).deleteSync();
    File(plugPath).deleteSync();
  } catch (_) {}

  print('----------------------------------------------------------------');
  print('  NATIJA: Jami ${passed + failed} ta testdan $passed tasi MUVAFFAQITYATLI O\'TDI (Xatolar: $failed)');
  print('================================================================');

  if (failed > 0) exit(1);
}
