import 'dart:convert';
import 'dart:io';
import 'uzbek_nlp.dart';

/// Ilovaning ma'lumotlar saqlanadigan standart yo'lini aniqlash (Pure Dart)
Future<String> getAppStoragePath(String filename) async {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
    final dir = Directory('$appData/BusinessEcosystem');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return '${dir.path}/$filename';
  } else if (Platform.isAndroid) {
    try {
      final dir = Directory('${Directory.systemTemp.parent.path}/app_flutter');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return '${dir.path}/$filename';
    } catch (_) {
      return '${Directory.systemTemp.path}/$filename';
    }
  } else if (Platform.isLinux || Platform.isMacOS) {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final dir = Directory('$home/.bizeco');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return '${dir.path}/$filename';
  }
  return '${Directory.current.path}/$filename';
}

/// Yagona formatdagi Entity modeli
class Entity {
  Entity({
    required this.id,
    required this.name,
    this.status = 'active',
    String? createdAt,
    String? updatedAt,
    Map<String, dynamic>? meta,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String(),
        meta = meta ?? {};

  final int id;
  String name;
  String status;
  final String createdAt;
  String updatedAt;
  final Map<String, dynamic> meta;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'meta': meta,
      };

  factory Entity.fromJson(Map<String, dynamic> json) => Entity(
        id: json['id'] as int,
        name: json['name'] as String,
        status: (json['status'] as String?) ?? 'active',
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
        meta: (json['meta'] as Map?)?.map((k, v) => MapEntry('$k', v)) ?? {},
      );
}

/// Standart reaktiv va xavfsiz JSON ombori (Pure Dart)
class StandardStore {
  StandardStore._(this._file, this._items);

  final File _file;
  final List<Entity> _items;
  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void notifyListeners() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  static Future<StandardStore> open(String filePath) async {
    final file = File(filePath);
    final items = <Entity>[];
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final raw = jsonDecode(content) as List;
          for (final item in raw) {
            items.add(Entity.fromJson(Map<String, dynamic>.from(item as Map)));
          }
        }
      } catch (e) {
        stderr.writeln('Store yuklashda ogohlantirish ($filePath): $e');
      }
    }
    return StandardStore._(file, items);
  }

  List<Entity> get all => List.unmodifiable(_items);

  /// ID yoki nom (O'zbek tili stemmeri va so'z chegarasi orqali) bo'yicha qidirish
  Entity? find(Object? key) {
    if (key == null) return null;

    final keyStr = '$key'.trim();
    if (keyStr.isEmpty) return null;

    // 1. Agar raqam bo'lsa, ID bo'yicha
    final id = int.tryParse(keyStr);
    if (id != null) {
      final byId = _items.where((e) => e.id == id).firstOrNull;
      if (byId != null) return byId;
    }

    // 2. Aniq nom bo'yicha (katta-kichik harf farqsiz)
    final lower = keyStr.toLowerCase();
    final exact = _items.where((e) => e.name.toLowerCase() == lower).firstOrNull;
    if (exact != null) return exact;

    // 3. O'zbek tili stemmeri bo'yicha to'liq tenglik (masalan: "Valining" -> "vali" == "vali")
    final keyStem = UzbekNlp.stem(keyStr);
    final stemmedExact = _items.where((e) => UzbekNlp.stem(e.name) == keyStem).firstOrNull;
    if (stemmedExact != null) return stemmedExact;

    // 4. Tokenlar (so'zlar) bo'yicha butun so'z mosligi (Ali va Valini adashtirmaydi)
    final keyTokens = lower
        .replaceAll(RegExp(r'[^\w\s\d]'), ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .map(UzbekNlp.stem)
        .toSet();

    for (final item in _items) {
      final itemTokens = item.name
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s\d]'), ' ')
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .map(UzbekNlp.stem)
          .toSet();

      // Agar kalit so'zlari ob'ekt nomida to'liq bo'lsa ("Sardor" -> "Sardor hisoboti")
      if (keyTokens.isNotEmpty && keyTokens.every((k) => itemTokens.contains(k))) {
        return item;
      }

      // Agar ob'ekt so'zlari kalit so'zida bo'lsa
      if (itemTokens.isNotEmpty && itemTokens.every((it) => keyTokens.contains(it))) {
        return item;
      }

      // Meta ichidagi 'person' bo'yicha tekshirish (masalan Qarz: Botir -> meta['person'] = Botir)
      final person = item.meta['person']?.toString();
      if (person != null) {
        final personStem = UzbekNlp.stem(person);
        if (personStem == keyStem || keyTokens.contains(personStem)) {
          return item;
        }
      }
    }

    return null;
  }

  /// Yangi yozuv qo'shish
  Entity insert({
    required String name,
    String status = 'active',
    Map<String, dynamic>? meta,
  }) {
    final nextId = _items.isEmpty ? 1 : (_items.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1);
    final entity = Entity(
      id: nextId,
      name: name.trim(),
      status: status,
      meta: meta ?? {},
    );
    _items.add(entity);
    _save();
    return entity;
  }

  /// Yangilash
  Entity update(
    Object? key, {
    String? name,
    String? status,
    Map<String, dynamic>? metaPatch,
  }) {
    final entity = find(key);
    if (entity == null) {
      throw Exception("'$key' bo'yicha ma'lumot topilmadi.");
    }

    if (name != null && name.trim().isNotEmpty) {
      entity.name = name.trim();
    }
    if (status != null) {
      entity.status = status;
    }
    if (metaPatch != null) {
      entity.meta.addAll(metaPatch);
    }
    entity.updatedAt = DateTime.now().toIso8601String();

    _save();
    return entity;
  }

  /// Qiymatni oshirish (masalan actual yoki amount)
  Entity increment(Object? key, String field, num delta) {
    final entity = find(key);
    if (entity == null) {
      throw Exception("'$key' bo'yicha ma'lumot topilmadi.");
    }
    final current = UzbekNlp.parseNumber(entity.meta[field]);
    entity.meta[field] = current + delta;
    entity.updatedAt = DateTime.now().toIso8601String();

    _save();
    return entity;
  }

  /// O'chirish
  Entity delete(Object? key) {
    final entity = find(key);
    if (entity == null) {
      throw Exception("'$key' topilmadi, o'chirib bo'lmadi.");
    }
    _items.remove(entity);
    _save();
    return entity;
  }

  /// Holat yoki parametr bo'yicha filtrlash
  List<Entity> filter({String? status, bool Function(Entity)? predicate}) {
    return _items.where((e) {
      if (status != null && e.status != status) return false;
      if (predicate != null && !predicate(e)) return false;
      return true;
    }).toList();
  }

  void _save() {
    try {
      if (!_file.parent.existsSync()) {
        _file.parent.createSync(recursive: true);
      }
      final jsonStr = jsonEncode(_items.map((e) => e.toJson()).toList());
      _file.writeAsStringSync(jsonStr, flush: true);
    } catch (e) {
      stderr.writeln('Store saqlashda xato: $e');
    } finally {
      notifyListeners();
    }
  }
}
