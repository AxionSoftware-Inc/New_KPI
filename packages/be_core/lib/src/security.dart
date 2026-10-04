import 'store.dart';

/// Tizim xavfsizligi va rollarni boshqarish moduli (Security & RBAC)
enum UserRole {
  director,     // Barcha huquqlar (KPI, CRM, Finance, Sozlamalar, Zaxiralash, Tasdiqlash)
  salesManager, // Menejer (Vazifa topshirish, CRM, bo'lim nazorati)
  employee,     // Xodim (Faqat o'ziga topshirilgan vazifalar, topshirish, hisobot)
  cashier,      // Kassir (Kassa, to'lovlar)
}

class UserAccount {
  const UserAccount({
    required this.id,
    required this.name,
    required this.role,
    this.department = 'Umumiy',
  });

  final String id;
  final String name;
  final UserRole role;
  final String department;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.name,
        'department': department,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        id: json['id'] as String,
        name: json['name'] as String,
        role: UserRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => UserRole.employee,
        ),
        department: (json['department'] as String?) ?? 'Umumiy',
      );
}

class SecurityManager {
  SecurityManager({
    this.currentRole = UserRole.director,
    UserAccount? currentUser,
    this.directorPin = '7777',
    this.pinRequired = false,
  }) : currentUser = currentUser ?? defaultAccounts.first;

  UserRole currentRole;
  UserAccount currentUser;
  String directorPin;
  bool pinRequired;

  /// Standart test va kompaniya foydalanuvchilari
  static const defaultAccounts = [
    UserAccount(id: 'u1', name: 'Direktor (Rahbar)', role: UserRole.director, department: 'Boshqaruv'),
    UserAccount(id: 'u2', name: 'Vali (Menejer)', role: UserRole.salesManager, department: 'Savdo'),
    UserAccount(id: 'u3', name: 'Ali (Xodim)', role: UserRole.employee, department: 'IT & Savdo'),
    UserAccount(id: 'u4', name: 'Sardor (Xodim)', role: UserRole.employee, department: 'Savdo'),
    UserAccount(id: 'u5', name: 'Malika (Kassir)', role: UserRole.cashier, department: 'Moliya'),
  ];

  /// Rol ruxsatlarini tekshirish
  bool canAccessFinance() => currentUser.role == UserRole.director || currentUser.role == UserRole.cashier;
  bool canAccessCrm() => currentUser.role == UserRole.director || currentUser.role == UserRole.salesManager;
  bool canAccessKpi() => true;
  bool canViewProfit() => currentUser.role == UserRole.director;
  bool canDeleteRecords() => currentUser.role == UserRole.director;

  // --- KPI & Vazifalar RBAC Ruxsatlari ---

  /// Vazifa biriktirish huquqi (Faqat rahbar va menejer)
  bool canAssignTask(UserAccount user) {
    return user.role == UserRole.director || user.role == UserRole.salesManager;
  }

  /// Vazifani topshirish huquqi (O'ziga yuklatilgan xodim yoki rahbar)
  bool canSubmitTask(UserAccount user, Entity task) {
    if (user.role == UserRole.director) return true;
    final assignedTo = task.meta['assigned_to'] ?? task.meta['employee'];
    if (assignedTo == null) return true;
    return assignedTo.toString().toLowerCase().contains(user.name.split(' ').first.toLowerCase());
  }

  /// Vazifani tasdiqlash va bonusni moliyadan yechishga ruxsat
  /// MUHIM: Xodim o'zining vazifasini o'zi tasdiqlab bonus ola OLMAYDI (Self-approval taqiqlangan)
  bool canApproveTask(UserAccount user, Entity task) {
    if (user.role == UserRole.director) return true;
    if (user.role == UserRole.salesManager) {
      final assignedTo = task.meta['assigned_to'] ?? task.meta['employee'];
      // Menejer o'ziga topshirilgan vazifani o'zi tasdiqlay olmaydi
      if (assignedTo != null && assignedTo.toString().toLowerCase().contains(user.name.split(' ').first.toLowerCase())) {
        return false;
      }
      return true;
    }
    return false;
  }

  /// Vazifani qayta ishlashga (rework) qaytarish
  bool canRejectTask(UserAccount user, Entity task) {
    return canApproveTask(user, task);
  }

  /// Vazifani o'chirish huquqi (faqat direktor)
  bool canDeleteTask(UserAccount user) {
    return user.role == UserRole.director;
  }

  /// Vazifani ko'rish huquqi (Direktor va menejer barchasini ko'radi, xodim o'zinikini ko'radi)
  bool canViewTask(UserAccount user, Entity task) {
    if (user.role == UserRole.director || user.role == UserRole.salesManager) return true;
    final assignedTo = task.meta['assigned_to'] ?? task.meta['employee'];
    final assignedBy = task.meta['assigned_by'];
    final uName = user.name.split(' ').first.toLowerCase();
    if (assignedTo != null && assignedTo.toString().toLowerCase().contains(uName)) return true;
    if (assignedBy != null && assignedBy.toString().toLowerCase().contains(uName)) return true;
    if (task.name.toLowerCase().contains(uName)) return true;
    return false;
  }

  /// Foydalanuvchini almashtirish
  void switchUser(UserAccount account) {
    currentUser = account;
    currentRole = account.role;
  }

  void switchRole(UserRole role) {
    currentRole = role;
    currentUser = defaultAccounts.firstWhere(
      (a) => a.role == role,
      orElse: () => defaultAccounts.first,
    );
  }

  /// PIN kod orqali direktor roliga o'tish
  bool unlockDirector(String pin) {
    if (pin.trim() == directorPin.trim()) {
      switchUser(defaultAccounts.first);
      return true;
    }
    return false;
  }
}
