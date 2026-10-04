import 'dart:convert';
import 'package:http/http.dart' as http;
import 'store.dart';
import 'uzbek_nlp.dart';

/// Ekotizim plaginlari uchun standart manifest
class EcosystemPlugin {
  EcosystemPlugin({
    required this.id,
    required this.name,
    required this.description,
    this.version = '1.0.0',
    this.author = 'Business Ecosystem',
    this.isEnabled = true,
    this.targetApps = const ['all'],
    this.iconName = 'extension',
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  bool isEnabled;
  final List<String> targetApps; // ['kpi', 'crm', 'finance'] yoki ['all']
  final String iconName;
  Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'version': version,
        'author': author,
        'is_enabled': isEnabled,
        'target_apps': targetApps,
        'icon_name': iconName,
        'metadata': metadata,
      };

  factory EcosystemPlugin.fromJson(Map<String, dynamic> json) =>
      EcosystemPlugin(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        version: json['version'] as String? ?? '1.0.0',
        author: json['author'] as String? ?? 'Business Ecosystem',
        isEnabled: json['is_enabled'] as bool? ?? true,
        targetApps: (json['target_apps'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const ['all'],
        iconName: json['icon_name'] as String? ?? 'extension',
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      );

  EcosystemPlugin copyWith({
    String? id,
    String? name,
    String? description,
    String? version,
    String? author,
    bool? isEnabled,
    List<String>? targetApps,
    String? iconName,
    Map<String, dynamic>? metadata,
  }) {
    return EcosystemPlugin(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      author: author ?? this.author,
      isEnabled: isEnabled ?? this.isEnabled,
      targetApps: targetApps ?? this.targetApps,
      iconName: iconName ?? this.iconName,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Ekotizim bo'ylab aylanuvchi voqea (Event)
class EcosystemEvent {
  EcosystemEvent({
    required this.name,
    required this.sourceApp,
    Map<String, dynamic>? payload,
    DateTime? timestamp,
  })  : payload = payload ?? {},
        timestamp = timestamp ?? DateTime.now();

  final String name; // 'kpi_task_approved', 'crm_deal_won', 'finance_expense', etc.
  final String sourceApp; // 'kpi', 'crm', 'finance', 'ai'
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'name': name,
        'source_app': sourceApp,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
      };

  factory EcosystemEvent.fromJson(Map<String, dynamic> json) => EcosystemEvent(
        name: json['name'] as String,
        sourceApp: json['source_app'] as String,
        payload: (json['payload'] as Map<String, dynamic>?) ?? {},
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      );
}

/// Ekotizim Voqealar Shinası (Event Bus)
class EventBus {
  EventBus._();
  static final EventBus instance = EventBus._();

  final Map<String, List<Future<void> Function(EcosystemEvent)>> _subscribers = {};
  final List<Future<void> Function(EcosystemEvent)> _allSubscribers = [];
  final List<EcosystemEvent> _history = [];

  List<EcosystemEvent> get history => List.unmodifiable(_history);

  void subscribe(String eventName, Future<void> Function(EcosystemEvent) handler) {
    _subscribers.putIfAbsent(eventName, () => []).add(handler);
  }

  void subscribeAll(Future<void> Function(EcosystemEvent) handler) {
    _allSubscribers.add(handler);
  }

  Future<void> publish(EcosystemEvent event) async {
    _history.add(event);
    if (_history.length > 200) _history.removeAt(0);

    final specific = _subscribers[event.name] ?? [];
    for (final h in specific) {
      try {
        await h(event);
      } catch (e) {
        // Log handler exception
      }
    }
    for (final h in _allSubscribers) {
      try {
        await h(event);
      } catch (e) {
        // Log global handler exception
      }
    }
  }

  void clearHistory() => _history.clear();
}

/// Plaginning ijro etiladigan mantiqiy interfeysi (Plugin Handler)
abstract class PluginHandler {
  String get pluginId;
  Future<void> onInit(PluginManager manager);
  Future<void> onEvent(EcosystemEvent event);
  Future<Map<String, dynamic>> executeCommand(String command, Map<String, dynamic> params);
}

// ============================================================================
// PLAGIN 1: O'ZBEKCHA AI EKOTIZIM ASSISTENTI (UZBEK AI PLUGIN)
// ============================================================================
class UzbekAiPluginHandler implements PluginHandler {
  UzbekAiPluginHandler({
    this.maxBonusLimit = 2000000.0,
    Map<String, double>? salaryMap,
  }) : salaries = salaryMap ?? {
          'ali': 5000000.0,
          'sardor': 6000000.0,
          'vali': 4500000.0,
          'malika': 4000000.0,
        };

  @override
  String get pluginId => 'plugin_uzbek_ai';

  double maxBonusLimit;
  final Map<String, double> salaries;

  @override
  Future<void> onInit(PluginManager manager) async {
    final meta = manager.getPlugin(pluginId)?.metadata;
    if (meta != null && meta.containsKey('max_bonus_limit')) {
      maxBonusLimit = (meta['max_bonus_limit'] as num).toDouble();
    }
  }

  @override
  Future<void> onEvent(EcosystemEvent event) async {}

  @override
  Future<Map<String, dynamic>> executeCommand(String command, Map<String, dynamic> params) async {
    if (command == 'parse_task_order') {
      final prompt = (params['prompt'] ?? '').toString();
      return parseTaskOrder(prompt);
    }
    if (command == 'update_limit') {
      final newLimit = (params['limit'] as num?)?.toDouble();
      if (newLimit != null && newLimit > 0) {
        maxBonusLimit = newLimit;
        return {'success': true, 'max_bonus_limit': maxBonusLimit};
      }
      return {'success': false, 'error': 'Noto\'g\'ri chegara summasi'};
    }
    return {'success': false, 'error': 'Noma\'lum buyruq: $command'};
  }

  /// AI buyrug'ini tahlil qilish (Natural Language Command Parser)
  /// Masalan: "Ali ga saytni bitirish vazifasini topshir va bitirsa oyligiga 10% qo'sh"
  Map<String, dynamic> parseTaskOrder(String prompt) {
    final lower = prompt.toLowerCase();

    // 1. Xodimni aniqlash
    String assignedTo = 'Ali';
    for (final name in salaries.keys) {
      if (lower.contains(name)) {
        assignedTo = name[0].toUpperCase() + name.substring(1);
        break;
      }
    }

    // 2. Bonus hisoblash (Foiz yoki to'g'ridan-to'g'ri summa)
    double calculatedBonus = 0.0;
    bool isPercent = false;
    double percentVal = 0.0;

    final percentMatch = RegExp(r'(\d+)\s*%').firstMatch(lower);
    if (percentMatch != null) {
      isPercent = true;
      percentVal = double.tryParse(percentMatch.group(1) ?? '0') ?? 0.0;
      final baseSalary = salaries[assignedTo.toLowerCase()] ?? 4000000.0;
      calculatedBonus = (baseSalary * percentVal) / 100.0;
    } else {
      calculatedBonus = UzbekNlp.parseNumber(prompt).toDouble();
      if (calculatedBonus == 0.0 && lower.contains('bonus')) {
        calculatedBonus = 500000.0; // Standart bonus
      }
    }

    // 3. Xavfsizlik chegarasi (Guardrail limit)
    bool isCapped = false;
    String warning = '';
    if (calculatedBonus > maxBonusLimit) {
      isCapped = true;
      warning = 'Diqqat: So\'ralgan bonus (${calculatedBonus.toInt()} so\'m) ruxsat etilgan chegaradan (${maxBonusLimit.toInt()} so\'m) oshdi. Chegaraga moslab belgilandi.';
      calculatedBonus = maxBonusLimit;
    }

    // 4. Muddatni aniqlash
    String deadline = '3 kunda';
    final dayMatch = RegExp(r'(\d+)\s*(kun|soat|oy)').firstMatch(lower);
    if (dayMatch != null) {
      deadline = '${dayMatch.group(1)} ${dayMatch.group(2)}da';
    }

    // 5. Vazifa nomini tozalab olish
    String taskName = prompt
        .replaceAll(RegExp(r'(\d+)\s*%', caseSensitive: false), '')
        .replaceAll(RegExp(r"vazifasini topshir|ish buyur|oyligiga|qo'sh|bonus yoz|agar bitirsa|bitirsa", caseSensitive: false), '')
        .replaceAll(RegExp(assignedTo, caseSensitive: false), '')
        .trim();
    if (taskName.isEmpty || taskName.length < 4) {
      taskName = "AI topshirig'i: ${prompt.length > 30 ? prompt.substring(0, 30) : prompt}";
    }

    return {
      'success': true,
      'name': taskName,
      'assigned_to': assignedTo,
      'bonus_amount': calculatedBonus,
      'deadline': deadline,
      'is_percent': isPercent,
      'percent_value': percentVal,
      'is_capped': isCapped,
      'warning': warning,
      'priority': 'high',
    };
  }
}

// ============================================================================
// PLAGIN 2: EKOTIZIM BOG'LOVCHI VA INTEGRATSIYA (ECOSYSTEM BRIDGE)
// ============================================================================
class EcosystemBridgePluginHandler implements PluginHandler {
  EcosystemBridgePluginHandler({
    this.financePort = 8083,
    this.crmPort = 8082,
    this.kpiPort = 8081,
    this.maxPayoutLimit = 3000000.0,
  });

  @override
  String get pluginId => 'plugin_ecosystem_bridge';

  final int financePort;
  final int crmPort;
  final int kpiPort;
  double maxPayoutLimit;
  final List<Map<String, dynamic>> bridgeLogs = [];

  @override
  Future<void> onInit(PluginManager manager) async {
    // Ekotizim voqealariga obuna bo'lish
    EventBus.instance.subscribe('kpi_task_approved', (event) async {
      if (manager.isPluginActive(pluginId)) {
        await _handleKpiApproved(event);
      }
    });

    EventBus.instance.subscribe('crm_lead_won', (event) async {
      if (manager.isPluginActive(pluginId)) {
        await _handleCrmLeadWon(event);
      }
    });
  }

  @override
  Future<void> onEvent(EcosystemEvent event) async {
    if (event.name == 'kpi_task_approved') {
      await _handleKpiApproved(event);
    } else if (event.name == 'crm_lead_won') {
      await _handleCrmLeadWon(event);
    }
  }

  Future<void> _handleKpiApproved(EcosystemEvent event) async {
    final payload = event.payload;
    final bonus = (payload['bonus_amount'] as num?)?.toDouble() ?? 0.0;
    final assignedTo = payload['assigned_to'] ?? 'Xodim';
    final taskName = payload['task_name'] ?? 'KPI Vazifasi';

    if (bonus <= 0) return;

    if (bonus > maxPayoutLimit) {
      bridgeLogs.add({
        'status': 'BLOCKED',
        'reason': 'Bonus summasi ($bonus) chegara ($maxPayoutLimit)dan oshdi.',
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }

    // Moliya serveriga chiqim yuborish
    try {
      final url = Uri.parse('http://127.0.0.1:$financePort/execute');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'finance_expense',
          'params': {
            'amount': bonus,
            'to': assignedTo,
            'category': 'Oylik/Bonus',
            'note': "KPI bonus to'lovi: $taskName ($assignedTo)",
            'authorized_by': 'Ecosystem Bridge',
          },
        }),
      ).timeout(const Duration(seconds: 2));

      bridgeLogs.add({
        'status': 'SUCCESS',
        'action': 'kpi_bonus_deducted',
        'amount': bonus,
        'recipient': assignedTo,
        'http_status': res.statusCode,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      bridgeLogs.add({
        'status': 'LOCAL_PROCESSED',
        'action': 'kpi_bonus_recorded',
        'amount': bonus,
        'recipient': assignedTo,
        'note': 'Moliya serveri oflayn, mahalliy hodisa sifatida qayd etildi',
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> _handleCrmLeadWon(EcosystemEvent event) async {
    final payload = event.payload;
    final budget = (payload['budget'] as num?)?.toDouble() ?? 0.0;
    final leadName = payload['lead_name'] ?? 'Mijoz';
    final product = payload['product'] ?? 'Xizmat/Mahsulot';

    if (budget <= 0) return;

    // Moliya serveriga kirim yuborish
    try {
      final url = Uri.parse('http://127.0.0.1:$financePort/execute');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'finance_income',
          'params': {
            'amount': budget,
            'from': leadName,
            'category': 'savdo',
            'note': "CRM muvaffaqiyatli bitim: $product ($leadName)",
            'cashier': 'Ecosystem Bridge',
          },
        }),
      ).timeout(const Duration(seconds: 2));

      bridgeLogs.add({
        'status': 'SUCCESS',
        'action': 'crm_income_recorded',
        'amount': budget,
        'payer': leadName,
        'http_status': res.statusCode,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      bridgeLogs.add({
        'status': 'LOCAL_PROCESSED',
        'action': 'crm_income_recorded',
        'amount': budget,
        'payer': leadName,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  @override
  Future<Map<String, dynamic>> executeCommand(String command, Map<String, dynamic> params) async {
    if (command == 'get_logs') {
      return {'success': true, 'logs': bridgeLogs};
    }
    return {'success': false, 'error': 'Noma\'lum buyruq'};
  }
}

// ============================================================================
// PLAGIN MENEJERI (MICROKERNEL PLUGIN MANAGER)
// ============================================================================
class PluginManager {
  PluginManager({StandardStore? store}) : _store = store;

  StandardStore? _store;
  final Map<String, EcosystemPlugin> _registeredPlugins = {};
  final Map<String, PluginHandler> _handlers = {};

  /// Barcha standart plaginlar ro'yxati
  static List<EcosystemPlugin> get builtInPlugins => [
        EcosystemPlugin(
          id: 'plugin_uzbek_ai',
          name: 'O\'zbekcha AI Assistent',
          description: 'Tabiiy tildagi ovozli va matnli buyruqlarni tushunuvchi aqlli yordamchi.',
          version: '1.2.0',
          targetApps: ['kpi', 'crm', 'finance'],
          iconName: 'smart_toy',
          metadata: {'max_bonus_limit': 2000000},
        ),
        EcosystemPlugin(
          id: 'plugin_ecosystem_bridge',
          name: 'Ekotizim Integratsiyasi (Bridge)',
          description: 'KPI vazifalar bonusi va CRM bitimlarini Moliya kassa hisobiga avtomatik ulash.',
          version: '1.0.0',
          targetApps: ['all'],
          iconName: 'sync_alt',
          metadata: {'max_payout_limit': 3000000},
        ),
        EcosystemPlugin(
          id: 'plugin_debt_ledger',
          name: 'Nasiya va Qarzlar Daftari',
          description: 'Mijozlar va ta\'minotchilar bilan qarz/nasiya hisob-kitobini yuritish.',
          version: '1.0.0',
          targetApps: ['finance'],
          iconName: 'handshake',
        ),
        EcosystemPlugin(
          id: 'plugin_pnl_analytics',
          name: 'P&L Tahlil va Diagrammalar',
          description: 'Daromad va xarajatlar toifalarini grafik va vizual tahlil qilish.',
          version: '1.1.0',
          targetApps: ['finance'],
          iconName: 'pie_chart',
        ),
        EcosystemPlugin(
          id: 'plugin_crm_funnel',
          name: 'Savdo Voronkasi (Funnel)',
          description: 'Lidlarning bosqichma-bosqich o\'tishi va konversiya tahlili.',
          version: '1.0.0',
          targetApps: ['crm'],
          iconName: 'filter_alt',
        ),
        EcosystemPlugin(
          id: 'plugin_telegram_bot',
          name: 'Telegram Bildirishnomalar',
          description: 'Yangi vazifa, bitim yoki moliyaviy chiqimlar haqida Telegram guruhiga xabar yuborish.',
          version: '1.0.0',
          targetApps: ['kpi', 'crm', 'finance'],
          iconName: 'send',
        ),
      ];

  /// Asinxron fabrika metodi
  static Future<PluginManager> create() async {
    final path = await getAppStoragePath('plugins_registry.json');
    final store = await StandardStore.open(path);
    final manager = PluginManager(store: store);
    await manager.init();
    return manager;
  }

  /// Plaginlar ro'yxatini yuklash va handlerlarni faollashtirish
  Future<void> init() async {
    if (_store == null) {
      final path = await getAppStoragePath('plugins_registry.json');
      _store = await StandardStore.open(path);
    }
    final items = _store!.all;
    if (items.isEmpty) {
      for (final p in builtInPlugins) {
        await registerPlugin(p);
      }
    } else {
      for (final item in items) {
        final plugin = EcosystemPlugin.fromJson(item.meta);
        _registeredPlugins[plugin.id] = plugin;
      }
      // Yangi qo'shilgan plaginlar bo'lsa ularni ham ro'yxatga kiritish
      for (final p in builtInPlugins) {
        if (!_registeredPlugins.containsKey(p.id)) {
          await registerPlugin(p);
        }
      }
    }

    // Standart handlerlarni ro'yxatga olish
    registerHandler(UzbekAiPluginHandler());
    registerHandler(EcosystemBridgePluginHandler());
  }

  void registerHandler(PluginHandler handler) {
    _handlers[handler.pluginId] = handler;
    handler.onInit(this);
  }

  PluginHandler? getHandler(String pluginId) => _handlers[pluginId];

  EcosystemPlugin? getPlugin(String pluginId) => _registeredPlugins[pluginId];

  Future<void> registerPlugin(EcosystemPlugin plugin) async {
    _registeredPlugins[plugin.id] = plugin;
    if (_store != null) {
      final existing = _store!.find(plugin.id);
      if (existing != null) {
        _store!.update(existing.id, metaPatch: plugin.toJson());
      } else {
        _store!.insert(name: plugin.id, meta: plugin.toJson());
      }
    }
  }

  Future<void> togglePlugin(String id, bool enabled) async {
    final existing = _registeredPlugins[id];
    if (existing != null) {
      existing.isEnabled = enabled;
      await registerPlugin(existing);
    }
  }

  List<EcosystemPlugin> getAllPlugins() {
    return _registeredPlugins.values.toList();
  }

  List<EcosystemPlugin> getActivePluginsForApp(String appName) {
    return _registeredPlugins.values.where((p) {
      if (!p.isEnabled) return false;
      return p.targetApps.contains('all') || p.targetApps.contains(appName.toLowerCase());
    }).toList();
  }

  bool isPluginActive(String id) {
    return _registeredPlugins[id]?.isEnabled ?? false;
  }

  /// Plagin buyrug'ini bajarish
  Future<Map<String, dynamic>> executeCommand(String pluginId, String command, Map<String, dynamic> params) async {
    if (!isPluginActive(pluginId)) {
      return {'success': false, 'error': '$pluginId plagini faol emas.'};
    }
    final handler = _handlers[pluginId];
    if (handler == null) {
      return {'success': false, 'error': '$pluginId uchun dasturiy handler topilmadi.'};
    }
    return await handler.executeCommand(command, params);
  }
}
