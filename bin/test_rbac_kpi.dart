// ignore_for_file: avoid_print
import 'dart:io';
import 'package:be_core/be_core.dart';
import 'package:kpi_app/kpi_service.dart';

void main() async {
  print('================================================================');
  print('   KPI & VAZIFALAR: RBAC VA WORKFLOW TEST SUITE');
  print('================================================================\n');

  final tempPath = '${Directory.systemTemp.path}/test_kpi_rbac_${DateTime.now().millisecondsSinceEpoch}.json';
  final service = await KpiService.init(tempPath);
  final security = SecurityManager();

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

  final director = SecurityManager.defaultAccounts.firstWhere((a) => a.role == UserRole.director);
  final ali = SecurityManager.defaultAccounts.firstWhere((a) => a.name.contains('Ali'));

  // 1. Direktor vazifa biriktira oladimi?
  assertTest("Direktor vazifa biriktirish huquqiga ega", security.canAssignTask(director));
  assertTest("Oddiy xodim (Ali) vazifa biriktira olmaydi", !security.canAssignTask(ali));

  // 2. Vazifa yaratish (Direktor -> Ali)
  final addTool = service.schema.tools.firstWhere((t) => t.name == 'kpi_add');
  final addRes = await addTool.handler({
    'name': 'Mobil ilovani yangilash',
    'assigned_to': 'Ali',
    'assigned_by': 'Direktor',
    'deadline': '3 kundan keyin',
    'bonus_amount': 500000,
    'checkpoints': ['UI dizayn', 'API ulanish', 'Testlash'],
  });

  assertTest("Vazifa muvaffaqiyatli yaratildi", addRes.success);
  final task = service.store.all.first;
  assertTest("Vazifa nomi va xodim to'g'ri biriktirildi", task.meta['assigned_to'] == 'Ali');
  assertTest("Vazifa boshlang'ich holati 'active'", task.status == 'active');

  // 3. Ko'rish huquqi (Ali faqat o'zinikini ko'ra oladimi?)
  assertTest("Ali o'ziga biriktirilgan vazifani ko'ra oladi", security.canViewTask(ali, task));

  // 4. Ali o'zining vazifasini o'zi tasdiqlab bonus ola olmasligi (Self-approval taqiqlangan)
  assertTest("Xodim (Ali) o'z vazifasini o'zi TASDIQLAY OLMAYDI (Self-approval taqiqlangan)", !security.canApproveTask(ali, task));
  assertTest("Xodim (Ali) vazifani o'chira OLMAYDI", !security.canDeleteTask(ali));

  // 5. Nazorat punkti (Checkpoint) sinovi
  final cpTool = service.schema.tools.firstWhere((t) => t.name == 'kpi_checkpoint');
  await cpTool.handler({'name': task.name, 'index': 0, 'done': true});
  final taskAfterCp1 = service.store.find(task.id)!;
  assertTest("Birinchi bosqich belgilangach foiz 33% bo'ldi", taskAfterCp1.meta['pct'] == 33);

  // 6. Xodim topshirishi (Submit for review)
  assertTest("Ali o'z vazifasini topshirish huquqiga ega", security.canSubmitTask(ali, taskAfterCp1));
  final submitTool = service.schema.tools.firstWhere((t) => t.name == 'kpi_submit');
  final subRes = await submitTool.handler({
    'name': task.id,
    'note': "Barcha modullar tayyorlandi va sinovdan o'tkazildi.",
  });

  assertTest("Xodim vazifani topshirdi", subRes.success);
  final submittedTask = service.store.find(task.id)!;
  assertTest("Vazifa holati 'submitted' (tasdiq kutilmoqda) ga o'tdi", submittedTask.status == 'submitted');

  // 7. Rahbar tomonidan tasdiqlash (Approve)
  assertTest("Direktor vazifani tasdiqlash huquqiga ega", security.canApproveTask(director, submittedTask));
  final approveTool = service.schema.tools.firstWhere((t) => t.name == 'kpi_approve');
  final appRes = await approveTool.handler({
    'name': task.id,
    'approved_by': 'Direktor',
  });

  assertTest("Direktor vazifani muvaffaqiyatli tasdiqladi", appRes.success);
  final doneTask = service.store.find(task.id)!;
  assertTest("Vazifa yakuniy holati 'done' bo'ldi", doneTask.status == 'done');
  assertTest("Tasdiqlagan rahbar qayd etildi", doneTask.meta['approved_by'] == 'Direktor');

  // 8. Qaytarish (Reject/Rework) sinovi
  await addTool.handler({
    'name': 'Hisobot tayyorlash',
    'assigned_to': 'Vali',
    'assigned_by': 'Direktor',
  });
  final task2 = service.store.all.last;
  await submitTool.handler({'name': task2.id, 'note': 'Xomaki hisobot'});
  final rejectTool = service.schema.tools.firstWhere((t) => t.name == 'kpi_reject');
  final rejRes = await rejectTool.handler({
    'name': task2.id,
    'reason': 'Hisob-kitoblar to\'liq emas, qayta ishlang.',
  });

  assertTest("Rahbar qoniqarsiz vazifani qaytardi", rejRes.success);
  final reworkedTask = service.store.find(task2.id)!;
  assertTest("Qaytarilgan vazifa yana 'active' holatga o'tdi", reworkedTask.status == 'active');
  assertTest("Qaytarilgan vazifa ustuvorligi 'urgent' (shoshilinch) qilindi", reworkedTask.meta['priority'] == 'urgent');

  // Test faylini tozalash
  try {
    final f = File(tempPath);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}

  print('\n----------------------------------------------------------------');
  print('  NATIJA: Jami $passed ta testdan $passed tasi MUVAFFAQITYATLI O\'TDI (Xatolar: $failed)');
  print('================================================================\n');

  if (failed > 0) exit(1);
}
