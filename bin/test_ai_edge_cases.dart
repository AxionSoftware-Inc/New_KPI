// ignore_for_file: avoid_print
import 'dart:io';
import 'package:be_core/be_core.dart';
import 'package:kpi_app/kpi_service.dart';

void main() async {
  print('================================================================');
  print('   AI VAZIFA TOPSHIRISH VA CHEKKA HOLATLAR (EDGE CASES) TESTI');
  print('================================================================\n');

  final tempPath = '${Directory.systemTemp.path}/test_kpi_edge_${DateTime.now().millisecondsSinceEpoch}.json';
  final service = await KpiService.init(tempPath);

  int passed = 0;
  int failed = 0;

  void assertTest(String title, bool condition, [String? detail]) {
    if (condition) {
      print('  [PASS] $title');
      passed++;
    } else {
      print('  [FAIL] $title ${detail != null ? '($detail)' : ''}');
      failed++;
    }
  }

  // --- CHEKKA HOLAT 1: Standart buyruq (Ali, 10% bonus) ---
  final p1 = UzbekNlp.parseTaskWithBonus("Ali ga yangi sayt qilishni topshir, bitirsa 10% qo'sh")!;
  assertTest("1.1. Xodim to'g'ri ajratildi (Ali)", p1['employee'] == 'Ali');
  assertTest("1.2. Vazifa nomi to'g'ri olindi", p1['taskName'].contains('Yangi sayt qilish'));
  assertTest("1.3. Bonus foizi to'g'ri olindi (10%)", p1['bonusPercent'] == 10);

  // --- CHEKKA HOLAT 2: Chegaradan oshgan katta bonus (10 million so'm) ---
  final p2 = UzbekNlp.parseTaskWithBonus("Valiga omborni tekshirtir, bitirsa 10 million bonus ber")!;
  assertTest("2.1. Xodim to'g'ri ajratildi (Vali)", p2['employee'] == 'Vali');
  assertTest("2.2. Katta summa olindi (10 mln)", p2['fixedBonus'] == 10000000);

  final addTool = service.schema.tools.firstWhere((t) => t.name == 'kpi_add');
  await addTool.handler({
    'name': p2['taskName'],
    'assigned_to': p2['employee'],
    'bonus_amount': p2['fixedBonus'],
  });
  final task2 = service.store.all.last;
  assertTest("2.3. Xavfsizlik chegarasi (Limit): 10 mln bonus 2 mln ga qisqartirildi", task2.meta['bonus_amount'] == 2000000);
  assertTest("2.4. Chegara belgilangani qayd etildi (is_capped = true)", task2.meta['is_capped'] == true);

  // --- CHEKKA HOLAT 3: Chegaradan oshgan foiz (60% bonus) ---
  final p3 = UzbekNlp.parseTaskWithBonus("Sardorga yangi modulni yukla, bitirsa 60% qo'sh")!;
  assertTest("3.1. Foiz olindi (60%)", p3['bonusPercent'] == 60);
  await addTool.handler({
    'name': p3['taskName'],
    'assigned_to': p3['employee'],
    'bonus_percent': p3['bonusPercent'],
  });
  final task3 = service.store.all.last;
  // 5 mln ning 60% = 3 mln -> Limit 2 mln
  assertTest("3.2. 60% bonus (3 mln) xavfsizlik chegarasi bo'yicha 2 mln ga cheklandi", task3.meta['bonus_amount'] == 2000000);

  // --- CHEKKA HOLAT 4: Himoyalangan ismlar va sheva (Karimga, 300 ming) ---
  final p4 = UzbekNlp.parseTaskWithBonus("Karimga xatoliklarni to'g'rilashni topshir, bitirsa 300 ming qo'sh")!;
  assertTest("4.1. Karim ismi himoyalandi (Kar bo'lib qolmadi)", p4['employee'] == 'Karim');
  assertTest("4.2. 300 ming so'm aniq summa olindi", p4['fixedBonus'] == 300000);

  // --- CHEKKA HOLAT 5: Muddat (Deadline) va Tezkor ustuvorlik ---
  final p5 = UzbekNlp.parseTaskWithBonus("Nodirga 3 kunda serverni sozlashni buyur, tezkor, darhol bajarsin")!;
  assertTest("5.1. Xodim Nodir", p5['employee'] == 'Nodir');
  assertTest("5.2. Ustuvorlik shoshilinch (urgent) deb aniqlandi", p5['priority'] == 'urgent');
  assertTest("5.3. 3 kunlik muddat (deadline) avtomatik hisoblandi", p5['deadline'] != null);

  // --- CHEKKA HOLAT 6: Manfiy bonus himoyasi ---
  final p6 = UzbekNlp.parseTaskWithBonus("Botirga vazifa ber, -500 ming bonus qo'sh")!;
  assertTest("6.1. Manfiy summa filtrlandi, 0 bo'ldi", p6['bonusPercent'] == 0 && p6['fixedBonus'] == 0);

  // --- CHEKKA HOLAT 7: Vazifa nomi aytilmagan umumiy buyruq ---
  final p7 = UzbekNlp.parseTaskWithBonus("Ali ga ish buyur va bitirsa 10% qo'sh")!;
  assertTest("7.1. Bo'sh qolmasdan standart 'Yangi topshiriq' nomi berildi", p7['taskName'] == 'Yangi topshiriq');

  // --- CHEKKA HOLAT 8: Ikki marta tasdiqlashdan himoya (Anti-Double-Payout) ---
  await addTool.handler({
    'name': 'Hujjatlarni tayyorlash',
    'assigned_to': 'Ali',
    'bonus_amount': 400000,
  });
  final task8 = service.store.all.last;
  final approveTool = service.schema.tools.firstWhere((t) => t.name == 'kpi_approve');

  // 1-marta tasdiqlash
  await approveTool.handler({'name': task8.id, 'approved_by': 'Direktor'});
  service.store.update(task8.id, metaPatch: {'bonus_paid': true});
  final task8AfterApprove = service.store.find(task8.id)!;
  assertTest("8.1. Birinchi tasdiqlash muvaffaqiyatli", task8AfterApprove.status == 'done');
  assertTest("8.2. Bonus to'langan deb belgilandi", task8AfterApprove.meta['bonus_paid'] == true);

  // 2-marta tasdiqlashga urinish
  final isAlreadyPaid = task8AfterApprove.meta['bonus_paid'] == true;
  assertTest("8.3. Ikkinchi tasdiqlashda bonus qayta to'lanmaydi (Anti-Double-Payout)", isAlreadyPaid);

  // --- CHEKKA HOLAT 9: Qaytarish (Rework) va Qayta topshirish sikli ---
  await addTool.handler({
    'name': 'Baza audit',
    'assigned_to': 'Sardor',
  });
  final task9 = service.store.all.last;
  final submitTool = service.schema.tools.firstWhere((t) => t.name == 'kpi_submit');
  await submitTool.handler({'name': task9.id, 'note': 'Bajarildi'});

  // Rahbar qaytardi
  final rejectTool = service.schema.tools.firstWhere((t) => t.name == 'kpi_reject');
  await rejectTool.handler({'name': task9.id, 'reason': 'Audit to\'liq emas'});
  final task9Rejected = service.store.find(task9.id)!;
  assertTest("9.1. Qaytarilganda status 'active' ga o'tdi", task9Rejected.status == 'active');
  assertTest("9.2. Qaytarish sababi saqlandi", task9Rejected.meta['rejection_reason'] == 'Audit to\'liq emas');
  assertTest("9.3. Qaytarilgan ish ustuvorligi 'urgent' ga oshirildi", task9Rejected.meta['priority'] == 'urgent');

  // Sardor qayta to'g'rilab topshirdi
  await submitTool.handler({'name': task9.id, 'note': 'Qayta tekshirildi, to\'liq tayyor'});
  final task9Resubmitted = service.store.find(task9.id)!;
  assertTest("9.4. Qayta topshirilganda status 'submitted' ga o'tdi", task9Resubmitted.status == 'submitted');

  // Direktor tasdiqladi
  await approveTool.handler({'name': task9.id, 'approved_by': 'Direktor'});
  final task9Done = service.store.find(task9.id)!;
  assertTest("9.5. Qayta ishlangan vazifa muvaffaqiyatli yakunlandi ('done')", task9Done.status == 'done');

  // Test faylini tozalash
  try {
    final f = File(tempPath);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}

  print('\n----------------------------------------------------------------');
  print('  NATIJA: Jami $passed ta chekka holatdan $passed tasi MUVAFFAQITYATLI O\'TDI (Xatolar: $failed)');
  print('================================================================\n');

  if (failed > 0) exit(1);
}
