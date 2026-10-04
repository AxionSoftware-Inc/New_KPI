import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'store.dart';

/// Zaxira nusxa olish va Telegram orqali sinxronizatsiya moduli (Backup & Sync)
class BackupManager {
  BackupManager({
    this.kpiStore,
    this.crmStore,
    this.financeStore,
    this.backupDir,
  });

  final StandardStore? kpiStore;
  final StandardStore? crmStore;
  final StandardStore? financeStore;
  final String? backupDir;

  /// Barcha 3 ta dastur ma'lumotlarini bitta JSON paketga jamlash
  Map<String, dynamic> createSnapshot() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'version': '1.0.0',
      'kpi': kpiStore?.all.map((e) => e.toJson()).toList() ?? [],
      'crm': crmStore?.all.map((e) => e.toJson()).toList() ?? [],
      'finance': financeStore?.all.map((e) => e.toJson()).toList() ?? [],
    };
  }

  /// Mahalliy backups papkasiga avtomatik saqlash
  Future<File> saveLocalBackup([String? customDir]) async {
    final dirPath = customDir ?? backupDir ?? '${Directory.current.path}/backups';
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final nowStr = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final file = File('${dir.path}/backup_$nowStr.json');
    final snapshot = createSnapshot();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(snapshot), flush: true);
    return file;
  }

  /// Telegram bot orqali zaxira nusxani rahbarning Telegramiga yuborish
  Future<bool> sendToTelegram({
    required String botToken,
    required String chatId,
    String? caption,
  }) async {
    try {
      final file = await saveLocalBackup();
      final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendDocument');
      final request = http.MultipartRequest('POST', uri)
        ..fields['chat_id'] = chatId
        ..fields['caption'] = caption ?? '📦 Biznes Ekotizimi kunlik zaxira nusxasi (${DateTime.now().toIso8601String().substring(0, 10)})'
        ..files.add(await http.MultipartFile.fromPath('document', file.path));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamedResponse);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
