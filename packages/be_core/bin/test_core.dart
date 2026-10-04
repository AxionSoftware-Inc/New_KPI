import 'dart:io';
import 'package:be_core/be_core.dart';

void main() async {
  print('================================================================');
  print('   BUSINESS ECOSYSTEM CORE: PROFIL VA PLAGIN TEST SINOVI');
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
  test('1.4. Menejer Vali profili mavjud', profiles.any((p) => p.role == UserRole.salesManager));
  test('1.5. Xodim Ali profili mavjud', profiles.any((p) => p.role == UserRole.employee));

  // 2. ProfileManager Store va almashtirish
  final tempProfilePath = '${Directory.systemTemp.path}/core_test_profile_${DateTime.now().millisecondsSinceEpoch}.json';
  final profileStore = await StandardStore.open(tempProfilePath);
  final profManager = ProfileManager(store: profileStore);
  await profManager.init();

  test('2.1. Boshlang\'ich profil direktor', profManager.current.role == UserRole.director);

  final ali = UserProfile.defaultProfiles.firstWhere((p) => p.name.contains('Ali'));
  await profManager.switchProfile(ali);
  test('2.2. Profil Ali (Xodim)ga almashtirildi', profManager.current.name.contains('Ali') && profManager.current.role == UserRole.employee);

  // Qaytadan yuklash (persistence)
  final profManager2 = ProfileManager(store: await StandardStore.open(tempProfilePath));
  await profManager2.init();
  test('2.3. Profil diskdan saqlangan holda qayta yuklandi', profManager2.current.name.contains('Ali'));

  // 3. Plagin Menejeri (Microkernel Plugin Engine)
  final tempPluginPath = '${Directory.systemTemp.path}/core_test_plugins_${DateTime.now().millisecondsSinceEpoch}.json';
  final pluginStore = await StandardStore.open(tempPluginPath);
  final pluginManager = PluginManager(store: pluginStore);
  await pluginManager.init();

  final allPlugins = pluginManager.getAllPlugins();
  test('3.1. Standart 5 ta plagin ro\'yxatdan o\'tdi', allPlugins.length == 5);

  final finPlugins = pluginManager.getActivePluginsForApp('finance');
  test('3.2. Moliya uchun Nasiya plagini mavjud', finPlugins.any((p) => p.id == 'plugin_debt_ledger'));
  test('3.3. CRM Funnel plagini moliyaga aralashmaydi', !finPlugins.any((p) => p.id == 'plugin_crm_funnel'));

  final crmPlugins = pluginManager.getActivePluginsForApp('crm');
  test('3.4. CRM uchun Funnel plagini mavjud', crmPlugins.any((p) => p.id == 'plugin_crm_funnel'));

  // Plaginni o'chirish/yoqish
  await pluginManager.togglePlugin('plugin_debt_ledger', false);
  test('3.5. Nasiya plagini o\'chirildi', !pluginManager.isPluginActive('plugin_debt_ledger'));
  test('3.6. Faol moliya plaginlari ro\'yxatidan chiqarildi', !pluginManager.getActivePluginsForApp('finance').any((p) => p.id == 'plugin_debt_ledger'));

  await pluginManager.togglePlugin('plugin_debt_ledger', true);
  test('3.7. Nasiya plagini qayta yoqildi', pluginManager.isPluginActive('plugin_debt_ledger'));

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
