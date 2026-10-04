import 'dart:io';
import 'package:be_core/be_core.dart';

/// KPI va Vazifalar servisi: Mukammal vazifalar boshqaruvi, muddat, xodimga topshirish,
/// topshirish-tasdiqlash sikli (Workflow) va nazorat punktlari (Checkpoints).
class KpiService {
  KpiService(this.store);
  final StandardStore store;

  static const port = 8081;

  static Future<KpiService> init([String? customPath]) async {
    final path = customPath ?? '${Directory.current.path}/kpi_data.json';
    final store = await StandardStore.open(path);
    return KpiService(store);
  }

  AppSchema get schema => AppSchema(
        app: 'kpi',
        version: '1.1.0',
        description: 'Vazifalar, xodimlar delegatsiyasi, muddatlar va KPI nazorati',
        port: port,
        tools: [
          // 1. Yangi KPI yoki vazifa qo'shish / topshirish
          ToolDef(
            name: 'kpi_add',
            description: "Yangi vazifa yaratish yoki xodimga yuklatish",
            params: {
              'name': const ParamDef(type: 'string', description: 'Vazifa nomi'),
              'assigned_to': const ParamDef(type: 'string', description: 'Biriktirilgan xodim (masalan: Ali)', required: false),
              'assigned_by': const ParamDef(type: 'string', description: 'Topshirgan rahbar (masalan: Direktor)', required: false),
              'target': const ParamDef(type: 'number', description: 'Reja miqdori (son)', defaultValue: 100),
              'unit': const ParamDef(type: 'string', description: "O'lchov birligi", defaultValue: 'ta'),
              'deadline': const ParamDef(type: 'string', description: 'Tugash muddati (sana yoki kun)', required: false),
              'bonus_amount': const ParamDef(type: 'number', description: 'Belgilangan bonus summasi', required: false),
              'bonus_percent': const ParamDef(type: 'number', description: 'Oylikka nisbatan bonus foizi', required: false),
              'priority': const ParamDef(type: 'string', description: 'Ustuvorlik: normal, urgent, high', defaultValue: 'normal'),
              'checkpoints': const ParamDef(type: 'array', description: 'Nazorat punktlari ro\'yxati (subtasks)', required: false),
            },
            handler: (p) async {
              final rawName = '${p['name']}'.trim();
              if (rawName.isEmpty) return ToolResult.err(error: "Vazifa nomi kiritilmadi.");

              final assignedTo = p['assigned_to']?.toString().trim();
              final assignedBy = p['assigned_by']?.toString().trim() ?? 'Rahbar';
              final target = UzbekNlp.parseNumber(p['target'] ?? 100);
              final unit = '${p['unit'] ?? 'ta'}';
              final deadline = p['deadline'] != null ? UzbekNlp.parseDate(p['deadline']) : null;
              final priority = '${p['priority'] ?? 'normal'}';

              num bonusAmount = UzbekNlp.parseNumber(p['bonus_amount']);
              final bonusPercent = UzbekNlp.parseNumber(p['bonus_percent']);
              const maxBonusLimit = 2000000; // Xavfsizlik chegarasi (2 mln so'm)

              if (bonusPercent > 0 && bonusAmount == 0) {
                bonusAmount = (5000000 * (bonusPercent / 100)).round();
              }
              bool isCapped = false;
              if (bonusAmount > maxBonusLimit) {
                bonusAmount = maxBonusLimit;
                isCapped = true;
              }

              // Checkpoints / Nazorat punktlari
              List<Map<String, dynamic>> checkList = [];
              if (p['checkpoints'] is List) {
                for (final item in (p['checkpoints'] as List)) {
                  checkList.add({'title': '$item'.trim(), 'done': false});
                }
              }

              final displayName = assignedTo != null && assignedTo.isNotEmpty
                  ? (rawName.contains(':') ? rawName : '$assignedTo: $rawName')
                  : rawName;

              final meta = <String, dynamic>{
                'target': target > 0 ? target : 100,
                'actual': 0,
                'unit': unit,
                'pct': 0,
                'priority': priority,
                'assigned_to': assignedTo,
                'assigned_by': assignedBy,
                'bonus_amount': bonusAmount,
                'bonus_percent': bonusPercent > 0 ? bonusPercent : null,
                'bonus_paid': false,
                'is_capped': isCapped,
                'checkpoints': checkList,
                'created_at': DateTime.now().toIso8601String(),
              };
              if (deadline != null) meta['deadline'] = deadline;

              final entity = store.insert(
                name: displayName,
                status: 'active',
                meta: meta,
              );

              final bonusMsg = bonusAmount > 0 ? " (Bonus: ${bonusAmount.toInt()} so'm)" : "";
              return ToolResult.ok(
                action: 'kpi_add',
                data: entity.toJson(),
                message: "'$displayName' vazifasi yaratildi$bonusMsg.",
              );
            },
          ),

          // 2. Xodim tomonidan vazifani topshirish (Submit for approval)
          ToolDef(
            name: 'kpi_submit',
            description: "Xodim ishni tugatib rahbar tasdig'iga topshirishi",
            params: {
              'name': const ParamDef(type: 'string', description: 'Vazifa nomi yoki ID'),
              'note': const ParamDef(type: 'string', description: 'Bajarilgan ish hisoboti / izoh', required: false),
            },
            handler: (p) async {
              final targetKey = p['id'] ?? p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' vazifasi topilmadi.");

              final note = p['note']?.toString() ?? "Ish yakunlandi, tasdiqlash uchun topshirildi.";
              final target = UzbekNlp.parseNumber(existing.meta['target'] ?? 100);

              final updated = store.update(
                existing.id,
                status: 'submitted', // Tasdiqlash kutilmoqda
                metaPatch: {
                  'actual': target,
                  'pct': 100,
                  'submission_note': note,
                  'submitted_at': DateTime.now().toIso8601String(),
                },
              );

              return ToolResult.ok(
                action: 'kpi_submit',
                data: updated.toJson(),
                message: "'${updated.name}' topshirildi va rahbar tasdig'iga yuborildi.",
              );
            },
          ),

          // 3. Rahbar tomonidan tasdiqlash (Approve -> Done)
          ToolDef(
            name: 'kpi_approve',
            description: "Rahbar vazifani tekshirib tasdiqlashi (bajarildi deb qabul qilish)",
            params: {
              'name': const ParamDef(type: 'string', description: 'Vazifa nomi yoki ID'),
              'approved_by': const ParamDef(type: 'string', description: 'Tasdiqlagan rahbar', required: false),
            },
            handler: (p) async {
              final targetKey = p['id'] ?? p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' topilmadi.");

              final approver = p['approved_by']?.toString() ?? 'Direktor';
              final bonusAmount = UzbekNlp.parseNumber(existing.meta['bonus_amount']);

              final updated = store.update(
                existing.id,
                status: 'done',
                metaPatch: {
                  'approved_by': approver,
                  'approved_at': DateTime.now().toIso8601String(),
                },
              );

              final bonusMsg = bonusAmount > 0
                  ? " Belgilangan ${bonusAmount.toInt()} so'm bonus to'loviga ruxsat berildi."
                  : "";

              return ToolResult.ok(
                action: 'kpi_approve',
                data: updated.toJson(),
                message: "'${updated.name}' rahbar ($approver) tomonidan tasdiqlandi!$bonusMsg",
              );
            },
          ),

          // 4. Rahbar tomonidan qayta ishlashga qaytarish (Reject / Rework)
          ToolDef(
            name: 'kpi_reject',
            description: "Rahbar vazifani qoniqarsiz deb qayta ishlashga qaytarishi",
            params: {
              'name': const ParamDef(type: 'string', description: 'Vazifa nomi yoki ID'),
              'reason': const ParamDef(type: 'string', description: 'Qaytarish sababi / ko\'rsatma'),
            },
            handler: (p) async {
              final targetKey = p['id'] ?? p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' topilmadi.");

              final reason = p['reason']?.toString() ?? "Kamchiliklar mavjud, qayta ishlang.";

              final updated = store.update(
                existing.id,
                status: 'active', // Yana faol holatga qaytadi
                metaPatch: {
                  'rejection_reason': reason,
                  'rejected_at': DateTime.now().toIso8601String(),
                  'priority': 'urgent', // Qaytarilgan ish shoshilinch bo'ladi
                },
              );

              return ToolResult.ok(
                action: 'kpi_reject',
                data: updated.toJson(),
                message: "'${updated.name}' qayta ishlashga qaytarildi. Sabab: $reason",
              );
            },
          ),

          // 5. Nazorat punktini (checkpoint) bajarildi deb belgilash
          ToolDef(
            name: 'kpi_checkpoint',
            description: "Vazifaning biror bosqichi (nazorat punkti)ni belgilash",
            params: {
              'name': const ParamDef(type: 'string', description: 'Vazifa nomi yoki ID'),
              'index': const ParamDef(type: 'number', description: 'Punkt indeksi (0 dan boshlab)'),
              'done': const ParamDef(type: 'boolean', description: 'Bajarildimi (true/false)'),
            },
            handler: (p) async {
              final targetKey = p['id'] ?? p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' topilmadi.");

              final idx = UzbekNlp.parseNumber(p['index']).toInt();
              final isDone = p['done'] == true || '${p['done']}'.toLowerCase() == 'true';

              final rawList = existing.meta['checkpoints'];
              if (rawList is! List || idx < 0 || idx >= rawList.length) {
                return ToolResult.err(error: "Nazorat punkti topilmadi.");
              }

              final updatedList = List<Map<String, dynamic>>.from(
                rawList.map((e) => Map<String, dynamic>.from(e as Map)),
              );
              updatedList[idx]['done'] = isDone;

              final total = updatedList.length;
              final completed = updatedList.where((c) => c['done'] == true).length;
              final newPct = total > 0 ? ((completed / total) * 100).round() : 0;

              final updated = store.update(
                existing.id,
                metaPatch: {
                  'checkpoints': updatedList,
                  'pct': newPct,
                },
                status: newPct >= 100 ? 'submitted' : existing.status,
              );

              return ToolResult.ok(
                action: 'kpi_checkpoint',
                data: updated.toJson(),
                message: "'${updated.name}' bosqichi belgilandi ($completed/$total - $newPct%).",
              );
            },
          ),

          // 6. Muddat (deadline) belgilash
          ToolDef(
            name: 'kpi_deadline',
            description: "Vazifa tugash muddatini belgilash",
            params: {
              'name': const ParamDef(type: 'string', description: 'Vazifa nomi yoki ID'),
              'deadline': const ParamDef(type: 'string', description: 'Sana yoki kun (masalan: 3 kundan keyin)'),
            },
            handler: (p) async {
              final targetKey = p['id'] ?? p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' topilmadi.");

              final date = UzbekNlp.parseDate(p['deadline']);
              final updated = store.update(
                existing.id,
                metaPatch: {'deadline': date},
              );

              return ToolResult.ok(
                action: 'kpi_deadline',
                data: updated.toJson(),
                message: "'${updated.name}' muddati $date ga belgilandi.",
              );
            },
          ),

          // 7. Shoshilinch qilish
          ToolDef(
            name: 'kpi_urge',
            description: "Vazifani shoshilinch deb belgilash",
            params: {
              'name': const ParamDef(type: 'string', description: 'Vazifa yoki xodim nomi'),
              'note': const ParamDef(type: 'string', description: 'Ko\'rsatma', defaultValue: 'Tezroq yakunlansin'),
            },
            handler: (p) async {
              final targetKey = p['id'] ?? p['name'];
              final existing = store.find(targetKey);
              if (existing == null) return ToolResult.err(error: "'$targetKey' topilmadi.");

              final note = '${p['note'] ?? 'Tezroq yakunlansin'}';
              final updated = store.update(
                existing.id,
                metaPatch: {'priority': 'urgent', 'note': note},
              );

              return ToolResult.ok(
                action: 'kpi_urge',
                data: updated.toJson(),
                message: "'${updated.name}' ustuvorligi OSHIRILDI: $note",
              );
            },
          ),

          // 8. Ro'yxatni ko'rish (xodim yoki holat bo'yicha filtr)
          ToolDef(
            name: 'kpi_list',
            description: "Vazifalar ro'yxati (xodim, faol, topshirilgan yoki bajarilgan)",
            params: {
              'status': const ParamDef(type: 'string', description: 'active, submitted, done bo\'yicha filtr', required: false),
              'employee': const ParamDef(type: 'string', description: 'Xodim ismi bo\'yicha filtr', required: false),
            },
            handler: (p) async {
              final filterStatus = p['status'] as String?;
              final employee = p['employee']?.toString().toLowerCase().trim();

              var list = store.filter(status: filterStatus);
              if (employee != null && employee.isNotEmpty) {
                list = list.where((e) {
                  final assigned = '${e.meta['assigned_to'] ?? e.name}'.toLowerCase();
                  return assigned.contains(employee);
                }).toList();
              }

              return ToolResult.ok(
                action: 'kpi_list',
                data: list.map((e) => e.toJson()).toList(),
                message: "Jami ${list.length} ta vazifa topildi.",
              );
            },
          ),

          // 9. Muddati o'tgan (overdue) vazifalar
          ToolDef(
            name: 'kpi_overdue',
            description: "Muddati o'tib ketgan kechikayotgan vazifalar",
            params: {},
            handler: (p) async {
              final now = DateTime.now();
              final all = store.filter(status: 'active');
              final overdue = all.where((e) {
                final dl = e.meta['deadline']?.toString();
                if (dl == null || dl.isEmpty) return false;
                try {
                  final dt = DateTime.parse(dl.split(' ').first);
                  return dt.isBefore(DateTime(now.year, now.month, now.day));
                } catch (_) {
                  return false;
                }
              }).toList();

              return ToolResult.ok(
                action: 'kpi_overdue',
                data: overdue.map((e) => e.toJson()).toList(),
                message: "Muddati o'tgan ${overdue.length} ta vazifa mavjud.",
              );
            },
          ),

          // 10. Analitik hisobot
          ToolDef(
            name: 'kpi_report',
            description: "Xodimlar va umumiy KPI ijro hisoboti",
            params: {},
            handler: (p) async {
              final all = store.all;
              if (all.isEmpty) {
                return ToolResult.ok(
                  action: 'kpi_report',
                  data: {'count': 0, 'avg_pct': 0, 'done': [], 'submitted': []},
                  message: "Hozircha hech qanday vazifa mavjud emas.",
                );
              }

              final pcts = all.map((e) => UzbekNlp.parseNumber(e.meta['pct'])).toList();
              final avg = (pcts.reduce((a, b) => a + b) / pcts.length).round();
              final done = all.where((e) => e.status == 'done').length;
              final submitted = all.where((e) => e.status == 'submitted').length;
              final active = all.where((e) => e.status == 'active').length;

              return ToolResult.ok(
                action: 'kpi_report',
                data: {
                  'total': all.length,
                  'avg_pct': avg,
                  'active': active,
                  'submitted': submitted,
                  'done': done,
                },
                message: "📊 KPI Hisoboti: Jami ${all.length} ta (Faol: $active, Tasdiqda: $submitted, Bajarilgan: $done). O'rtacha: $avg%.",
              );
            },
          ),
        ],
      );
}
