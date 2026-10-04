import 'store.dart';

/// Ekotizim plaginlari uchun standart manifest va interfeys
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
  final Map<String, dynamic> metadata;

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

/// Plaginlarni ro'yxatga olish, yoqish/o'chirish va boshqarish menejeri (Plugin Registry)
class PluginManager {
  PluginManager({StandardStore? store}) : _store = store;

  StandardStore? _store;
  final Map<String, EcosystemPlugin> _registeredPlugins = {};

  /// Barcha standart plaginlar ro'yxati
  static List<EcosystemPlugin> get builtInPlugins => [
        EcosystemPlugin(
          id: 'plugin_uzbek_ai',
          name: 'O\'zbekcha AI Assistent',
          description: 'Tabiiy tildagi ovozli va matnli buyruqlarni tushunuvchi aqlli yordamchi.',
          version: '1.2.0',
          targetApps: ['kpi', 'crm', 'finance'],
          iconName: 'smart_toy',
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

  /// Plaginlar ro'yxatini yuklash
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
    }
  }

  /// Yangi plaginni ro'yxatdan o'tkazish
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

  /// Plaginni yoqish yoki o'chirish
  Future<void> togglePlugin(String id, bool enabled) async {
    final existing = _registeredPlugins[id];
    if (existing != null) {
      existing.isEnabled = enabled;
      await registerPlugin(existing);
    }
  }

  /// Ro'yxatdan o'tgan barcha plaginlar
  List<EcosystemPlugin> getAllPlugins() {
    return _registeredPlugins.values.toList();
  }

  /// Muayyan dastur uchun mo'ljallangan faol plaginlar
  List<EcosystemPlugin> getActivePluginsForApp(String appName) {
    return _registeredPlugins.values.where((p) {
      if (!p.isEnabled) return false;
      return p.targetApps.contains('all') || p.targetApps.contains(appName.toLowerCase());
    }).toList();
  }

  /// Muayyan plagin faolmi?
  bool isPluginActive(String id) {
    return _registeredPlugins[id]?.isEnabled ?? false;
  }
}
