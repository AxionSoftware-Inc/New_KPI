import 'security.dart';
import 'store.dart';

/// Standart foydalanuvchi profili modeli (Barcha ilovalar uchun yagona)
class UserProfile {
  UserProfile({
    required this.id,
    required this.name,
    required this.role,
    this.department = 'Umumiy',
    this.phone = '+998 90 123 45 67',
    this.email = 'user@biz-eco.uz',
    this.pinCode = '1234',
    this.isPinEnabled = false,
    this.themeMode = 'light',
    this.serverHost = '127.0.0.1',
    this.serverPort = 8081,
    DateTime? lastActive,
  }) : lastActive = lastActive ?? DateTime.now();

  final String id;
  String name;
  UserRole role;
  String department;
  String phone;
  String email;
  String pinCode;
  bool isPinEnabled;
  String themeMode;
  String serverHost;
  int serverPort;
  DateTime lastActive;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.name,
        'department': department,
        'phone': phone,
        'email': email,
        'pin_code': pinCode,
        'is_pin_enabled': isPinEnabled,
        'theme_mode': themeMode,
        'server_host': serverHost,
        'server_port': serverPort,
        'last_active': lastActive.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        role: UserRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => UserRole.employee,
        ),
        department: (json['department'] as String?) ?? 'Umumiy',
        phone: (json['phone'] as String?) ?? '+998 90 123 45 67',
        email: (json['email'] as String?) ?? 'user@biz-eco.uz',
        pinCode: (json['pin_code'] as String?) ?? '1234',
        isPinEnabled: (json['is_pin_enabled'] as bool?) ?? false,
        themeMode: (json['theme_mode'] as String?) ?? 'light',
        serverHost: (json['server_host'] as String?) ?? '127.0.0.1',
        serverPort: (json['server_port'] as int?) ?? 8081,
        lastActive: json['last_active'] != null
            ? DateTime.tryParse(json['last_active'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );

  UserProfile copyWith({
    String? id,
    String? name,
    UserRole? role,
    String? department,
    String? phone,
    String? email,
    String? pinCode,
    bool? isPinEnabled,
    String? themeMode,
    String? serverHost,
    int? serverPort,
    DateTime? lastActive,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      department: department ?? this.department,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      pinCode: pinCode ?? this.pinCode,
      isPinEnabled: isPinEnabled ?? this.isPinEnabled,
      themeMode: themeMode ?? this.themeMode,
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  /// Standart foydalanuvchilar ro'yxati
  static List<UserProfile> get defaultProfiles => [
        UserProfile(
          id: 'u1',
          name: 'Karim (Direktor)',
          role: UserRole.director,
          department: 'Boshqaruv',
          phone: '+998 90 111 00 01',
          email: 'karim@biz-eco.uz',
          pinCode: '7777',
          isPinEnabled: true,
        ),
        UserProfile(
          id: 'u2',
          name: 'Vali (Menejer)',
          role: UserRole.salesManager,
          department: 'Savdo & Mijozlar',
          phone: '+998 90 222 00 02',
          email: 'vali@biz-eco.uz',
          pinCode: '2222',
        ),
        UserProfile(
          id: 'u3',
          name: 'Ali (Xodim)',
          role: UserRole.employee,
          department: 'Dasturlash & IT',
          phone: '+998 90 333 00 03',
          email: 'ali@biz-eco.uz',
          pinCode: '3333',
        ),
        UserProfile(
          id: 'u4',
          name: 'Sardor (Xodim)',
          role: UserRole.employee,
          department: 'Savdo bo\'limi',
          phone: '+998 90 444 00 04',
          email: 'sardor@biz-eco.uz',
          pinCode: '4444',
        ),
        UserProfile(
          id: 'u5',
          name: 'Malika (Kassir)',
          role: UserRole.cashier,
          department: 'Moliya & Kassa',
          phone: '+998 90 555 00 05',
          email: 'malika@biz-eco.uz',
          pinCode: '5555',
          isPinEnabled: true,
        ),
      ];
}

/// Profil xotirasi va sinxronizatsiyasi (Profile Store)
class ProfileManager {
  ProfileManager({StandardStore? store}) : _store = store;

  StandardStore? _store;
  UserProfile _current = UserProfile.defaultProfiles.first;

  UserProfile get current => _current;

  static Future<ProfileManager> create() async {
    final path = await getAppStoragePath('user_profile.json');
    final store = await StandardStore.open(path);
    final manager = ProfileManager(store: store);
    await manager.init();
    return manager;
  }

  Future<void> init() async {
    if (_store == null) {
      final path = await getAppStoragePath('user_profile.json');
      _store = await StandardStore.open(path);
    }
    final item = _store!.find('active_profile');
    if (item != null) {
      _current = UserProfile.fromJson(item.meta);
    } else {
      _current = UserProfile.defaultProfiles.first;
      await saveProfile(_current);
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    _current = profile;
    if (_store != null) {
      final item = _store!.find('active_profile');
      if (item != null) {
        _store!.update(item.id, metaPatch: profile.toJson());
      } else {
        _store!.insert(name: 'active_profile', meta: profile.toJson());
      }
    }
  }

  Future<void> switchProfile(UserProfile profile) async {
    await saveProfile(profile);
  }

  bool verifyPin(String enteredPin) {
    if (!_current.isPinEnabled) return true;
    return _current.pinCode == enteredPin;
  }
}
