/// O'zbek tili so'zlashuv va sheva qo'shimchalarini tozalash (Stemmer)
/// hamda raqam va sanalarni tahlil qilish moduli.
class UzbekNlp {
  /// O'zbekcha ot va fe'l qo'shimchalarini qirqib, asosni (stem) ajratish:
  /// Masalan: "Hasanni" -> "Hasan", "Alidan" -> "Ali", "Sardorga" -> "Sardor",
  /// "kelishdik" -> "kelish", "majlisni" -> "majlis"
  static String stem(String word) {
    var w = word.trim();
    if (w.isEmpty) return w;

    // Kichik harfga o'tkazishdan oldin bosh harfli ism bo'lishi mumkinligini hisobga olamiz
    var lower = w.toLowerCase();

    // Maxsus belgilarni tozalash (tirnoqlar, nuqtalar)
    lower = lower.replaceAll(RegExp(r"['`’ʼ]"), '');

    // Qo'shimchalar ketma-ketligi (uzunlaridan boshlab)
    final suffixes = [
      'larning', 'larimiz', 'laringiz', 'lardan', 'larga', 'larni', 'larda', 'lar',
      'ning', 'dan', 'tan', 'ga', 'ka', 'qa', 'ni', 'da', 'ta',
      'im', 'ing', 'imiz', 'ingiz', 'si', 'i',
      'yapti', 'yapmiz', 'yapman', 'moqda', 'gan', 'kan', 'qan', 'dik', 'tik', 'di', 'ti',
      'vor', 'gin', 'chi'
    ];

    // O'zbek ismlari va ildiz so'zlarni himoyalash
    const protectedRoots = {
      'karim', 'salim', 'rahim', 'hakim', 'azim', 'olim', 'muqim',
      'botir', 'sardor', 'vali', 'ali', 'hasan', 'husan', 'nodir', 'jasur',
      'temur', 'bobur', 'bekzod', 'sherzod', 'oybek', 'anvar'
    };

    var changed = true;
    while (changed && lower.length > 2) {
      if (protectedRoots.contains(lower)) break;

      changed = false;
      for (final s in suffixes) {
        // Ali, Vali, Sami kabi qisqa ismlarda 'i' qo'shimcha emas
        if (s == 'i' && lower.length <= 4) continue;
        // Karim, Salim kabi ismlarda 'im' qo'shimcha emas
        if (s == 'im' && (protectedRoots.contains(lower) || lower.length <= 5)) continue;

        if (lower.endsWith(s) && lower.length - s.length >= 3) {
          lower = lower.substring(0, lower.length - s.length);
          changed = true;
          break;
        }
      }
    }

    return lower;
  }

  /// Matn ichidan ism yoki ob'ekt nomini qidiruv bazasi bilan solishtirib topish
  /// Masalan matn: "Hasanni ishini tezroq bitir" -> mavjud nomlar orasidan "Hasan"ni topadi.
  static String? matchEntity(String text, Iterable<String> candidateNames) {
    final cleanWords = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\d]'), ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .map(stem)
        .toSet();

    for (final name in candidateNames) {
      final nameClean = name.toLowerCase().replaceAll(RegExp(r'[^\w\s\d]'), ' ');
      final candidateTokens = nameClean.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).map(stem).toSet();

      // 1. So'zma-so'z to'liq moslik (Ali va Valini mutlaqo adashtirmaydi)
      for (final word in cleanWords) {
        if (candidateTokens.contains(word)) {
          return name;
        }
      }

      // 2. Faqat 5 tadan ko'p harfli uzun so'zlar uchun boshlang'ich ildiz mosligi
      for (final word in cleanWords) {
        for (final cToken in candidateTokens) {
          if (word.length >= 5 && cToken.length >= 5) {
            if (word.startsWith(cToken) || cToken.startsWith(word)) {
              return name;
            }
          }
        }
      }
    }
    return null;
  }

  /// O'zbekcha pul va miqdor so'zlarini songa aylantirish:
  /// "10 mln" -> 10000000
  /// "500 ming" -> 500000
  /// "2.5 mln" -> 2500000
  /// "15 ta" -> 15
  static num parseNumber(Object? raw) {
    if (raw == null) return 0;
    if (raw is num) return raw;

    var s = '$raw'.toLowerCase().trim().replaceAll(' ', '');
    // Vergulni nuqtaga almashtirish: "2,5" -> "2.5"
    s = s.replaceAll(',', '.');

    final mlnMatch = RegExp(r'(-?[\d\.]+)(?:mln|million)').firstMatch(s);
    if (mlnMatch != null) {
      final val = double.tryParse(mlnMatch.group(1)!) ?? 0;
      return (val * 1000000).round();
    }

    final mingMatch = RegExp(r'(-?[\d\.]+)(?:ming|k)').firstMatch(s);
    if (mingMatch != null) {
      final val = double.tryParse(mingMatch.group(1)!) ?? 0;
      return (val * 1000).round();
    }

    final plainMatch = RegExp(r'(-?[\d\.]+)').firstMatch(s);
    if (plainMatch != null) {
      return num.tryParse(plainMatch.group(1)!) ?? 0;
    }

    return 0;
  }

  /// O'zbekcha nisbiy vaqt iboralarini ISO sana va vaqtga o'girish:
  /// "bugun", "kecha", "ertaga", "indinga", "3 kundan keyin", "ertaga soat 10 da"
  static String parseDate(Object? raw, {DateTime? now}) {
    final base = now ?? DateTime.now();
    if (raw == null) return base.toIso8601String().substring(0, 10);

    final s = '$raw'.toLowerCase().trim();

    // 1. Agar to'liq ISO sana va vaqt kelsa: 2026-10-05 15:00 yoki 2026-10-05T15:00
    if (RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}').hasMatch(s)) {
      return s.replaceAll('T', ' ').substring(0, 16);
    }
    // 2. Agar faqat YYYY-MM-DD bo'lsa
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      return s.substring(0, 10);
    }

    var targetDate = base;
    if (s.contains('kecha')) {
      targetDate = base.subtract(const Duration(days: 1));
    } else if (s.contains('indinga')) {
      targetDate = base.add(const Duration(days: 2));
    } else if (s.contains('erta') || s.contains('ertaga')) {
      targetDate = base.add(const Duration(days: 1));
    } else {
      final daysMatch = RegExp(r'(\d+)\s*(?:kun|kundan)').firstMatch(s);
      if (daysMatch != null) {
        final days = int.tryParse(daysMatch.group(1)!) ?? 0;
        targetDate = base.add(Duration(days: days));
      } else {
        final numDays = int.tryParse(s);
        if (numDays != null && numDays <= 30 && !s.contains(':') && !s.contains('soat')) {
          targetDate = base.add(Duration(days: numDays));
        }
      }
    }

    final dateStr = targetDate.toIso8601String().substring(0, 10);

    // Soat vaqtini tekshirish: masalan "10:00" yoki "soat 10"
    if (s.contains('soat') || s.contains(':')) {
      final timeMatch = RegExp(r'(?:soat\s*)?(\d{1,2})(?::(\d{2}))?').firstMatch(s);
      if (timeMatch != null) {
        final hour = int.tryParse(timeMatch.group(1)!) ?? 10;
        final minute = timeMatch.group(2) ?? '00';
        final hh = hour.toString().padLeft(2, '0');
        return '$dateStr $hh:$minute';
      }
    }

    // Tabiiy so'zlashuv vaqtlari (agar soat ko'rsatilmagan bo'lsa)
    if (s.contains('kechga') || s.contains('kechqurun') || s.contains('kechki')) {
      return '$dateStr 18:00';
    } else if (s.contains('ertalab') || s.contains('tongda')) {
      return '$dateStr 09:00';
    } else if (s.contains('tushda') || s.contains('abed')) {
      return '$dateStr 13:00';
    }

    return dateStr;
  }

  /// Vazifa va bonus bo'yicha tabiiy nutqni tahlil qilish (Chekka holatlar bilan)
  /// Masalan: "Ali ga 3 kunda yangi sayt qilishni topshir, tezkor, bitirsa oyligiga 10% qo'sh"
  static Map<String, dynamic>? parseTaskWithBonus(String text) {
    final lower = text.toLowerCase();
    final hasTaskTrigger = lower.contains('buyur') ||
        lower.contains('topshir') ||
        lower.contains('yukla') ||
        lower.contains('vazifa') ||
        lower.contains('reja') ||
        lower.contains('qilsin') ||
        lower.contains('bajarsin');
    final hasBonusTrigger = lower.contains('bonus') ||
        lower.contains('oyligig') ||
        lower.contains('oylik') ||
        lower.contains('qo\'sh') ||
        lower.contains('qosh');

    if (!hasTaskTrigger && !hasBonusTrigger) return null;

    // 1. Xodim ismini aniqlash (so'z + ga/ka yoki tanilgan ismlar)
    String? employee;
    const knownNames = [
      'karim', 'salim', 'rahim', 'hakim', 'azim', 'olim', 'muqim',
      'botir', 'sardor', 'vali', 'ali', 'hasan', 'husan', 'nodir', 'jasur',
      'temur', 'bobur', 'bekzod', 'sherzod', 'oybek', 'anvar', 'malika'
    ];

    final words = text.split(RegExp(r'\s+'));
    for (var i = 0; i < words.length; i++) {
      final w = words[i].replaceAll(RegExp(r"[^\w\d]"), '');
      if (w.isEmpty) continue;
      final wLower = w.toLowerCase();

      // Agar keyingi so'z "ga" yoki "ka" bo'lsa: "Ali ga"
      if (i + 1 < words.length && (words[i + 1].toLowerCase() == 'ga' || words[i + 1].toLowerCase() == 'ka')) {
        employee = w[0].toUpperCase() + w.substring(1);
        break;
      }

      // Agar so'z "ga", "ka", "qa" bilan tugasa: "Aliga", "Karimga"
      if (wLower.endsWith('ga') || wLower.endsWith('ka') || wLower.endsWith('qa')) {
        var baseName = w.substring(0, w.length - 2);
        if (baseName.isNotEmpty) {
          employee = baseName[0].toUpperCase() + baseName.substring(1);
          break;
        }
      }

      // Ma'lum ismlardan biri bo'lsa
      for (final kn in knownNames) {
        if (wLower.startsWith(kn)) {
          employee = kn[0].toUpperCase() + kn.substring(1);
          break;
        }
      }
      if (employee != null) break;
    }
    employee ??= 'Xodim';

    // 2. Bonus foizi yoki summasini aniqlash (Manfiy sonlar chetlanadi)
    num bonusPercent = 0;
    num fixedBonus = 0;

    final pctMatch = RegExp(r'(-?\d+)\s*(%|foiz)').firstMatch(lower);
    if (pctMatch != null) {
      final pVal = num.tryParse(pctMatch.group(1)!) ?? 0;
      bonusPercent = pVal > 0 ? pVal : 0;
    } else {
      final sumMatch = RegExp(r"(-?\d+[\d\s]*)\s*(million|mln|ming|k|so['`]?m|som)?").firstMatch(lower);
      if (sumMatch != null) {
        final val = parseNumber(sumMatch.group(0)!);
        if (val > 0) {
          fixedBonus = val;
        }
      }
    }

    // 3. Muddat (deadline) mavjudligini tekshirish
    String? deadline;
    if (lower.contains('bugun') ||
        lower.contains('erta') ||
        lower.contains('ertaga') ||
        lower.contains('kunda') ||
        lower.contains('kundan') ||
        lower.contains('gacha') ||
        lower.contains('kechga') ||
        lower.contains('hafta')) {
      deadline = parseDate(text);
    }

    // 4. Ustuvorlik (Priority)
    String priority = 'normal';
    if (lower.contains('tez') ||
        lower.contains('shoshil') ||
        lower.contains('darhol') ||
        lower.contains('zudlik') ||
        lower.contains('muhim')) {
      priority = 'urgent';
    }

    // 5. Vazifa nomini tozalab olish
    String taskName = 'Yangi topshiriq';
    var cleaned = text
        .replaceAll(RegExp(r'(ali|vali|sardor|nodir|hasan|husan|karim|salim|botir|malika|xodim)\s*(ga|ka)?', caseSensitive: false), '')
        .replaceAll(RegExp(r'(ish\s*buyur|topshir|yukla|reja\s*ber|vazifa\s*ber|buyur)', caseSensitive: false), '')
        .replaceAll(RegExp(r'(va\s*bitirsa|agar\s*bitirsa|tugatsa|bajarilsa|qilsa|qilsin)', caseSensitive: false), '')
        .replaceAll(RegExp(r"(oyligiga|oylik|bonus|qo['`]?sh|qosh|belgila)", caseSensitive: false), '')
        .replaceAll(RegExp(r"(tezkor|shoshilinch|darhol|zudlik\s*bilan)", caseSensitive: false), '')
        .replaceAll(RegExp(r"(bugun|ertaga|kechgacha|gacha)", caseSensitive: false), '')
        .replaceAll(RegExp(r"\d+\s*(%|foiz|ming|mln|so['`]?m|som|kun|kunda)?", caseSensitive: false), '')
        .replaceAll(RegExp(r'[,.\-!?]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.length >= 3) {
      taskName = cleaned[0].toUpperCase() + cleaned.substring(1);
    }

    return {
      'employee': employee,
      'taskName': taskName,
      'bonusPercent': bonusPercent,
      'fixedBonus': fixedBonus,
      'deadline': deadline,
      'priority': priority,
    };
  }
}
