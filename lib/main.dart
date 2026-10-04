import 'dart:convert';
import 'dart:io';
import 'package:be_core/be_core.dart';
import 'package:flutter/material.dart';
import 'kpi_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storagePath = await getAppStoragePath('kpi_data.json');
  final service = await KpiService.init(storagePath);
  final server = StandardAppServer(schema: service.schema, store: service.store);
  try {
    await server.start();
  } catch (e) {
    stderr.writeln('Server start ogohlantirish: $e');
  }

  final profileManager = await ProfileManager.create();
  final pluginManager = await PluginManager.create();

  runApp(KpiApp(
    service: service,
    profileManager: profileManager,
    pluginManager: pluginManager,
  ));
}

/// Moliya tizimidan bonus chiqim qilish (Localhost :8083 yoki Tarmoq IP :8083)
Future<bool> recordFinanceBonusExpense({
  required String employee,
  required num amount,
  required String taskName,
}) async {
  final payload = jsonEncode({
    'tool': 'finance_expense',
    'params': {
      'amount': amount,
      'category': 'Oylik/Bonus',
      'to': employee,
      'note': 'Vazifa yakunlandi: $taskName',
    }
  });

  for (final host in ['127.0.0.1:8083', '192.168.8.104:8083']) {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(Uri.parse('http://$host/execute'));
      req.headers.contentType = ContentType.json;
      req.write(payload);
      final resp = await req.close();
      client.close();
      if (resp.statusCode == 200) return true;
    } catch (_) {}
  }
  return false;
}

// ============================================================================
// DESIGN SYSTEM & THEME ARCHITECTURE (LIGHT / DARK THEMES)
// ============================================================================
class KpiTheme {
  // Light Palette
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Colors.white;
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightTextMuted = Color(0xFF64748B);

  // Dark Palette (Midnight Executive)
  static const Color darkBg = Color(0xFF0B0F19);
  static const Color darkCard = Color(0xFF131B2E);
  static const Color darkBorder = Color(0xFF1E293B);
  static const Color darkText = Color(0xFFF8FAFC);
  static const Color darkTextMuted = Color(0xFF94A3B8);

  // Primary Accent Colors
  static const Color primary = Color(0xFF4F46E5);
  static const Color primaryLight = Color(0xFF6366F1);
  static const Color accentEmerald = Color(0xFF10B981);
  static const Color accentAmber = Color(0xFFF59E0B);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: primary,
      scaffoldBackgroundColor: lightBg,
      cardColor: lightCard,
      dividerColor: lightBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: Color(0xFFEEF2FF),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: primaryLight,
      scaffoldBackgroundColor: darkBg,
      cardColor: darkCard,
      dividerColor: darkBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkCard,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: darkCard,
        elevation: 0,
        indicatorColor: Color(0xFF1E293B),
      ),
    );
  }
}

class KpiApp extends StatefulWidget {
  const KpiApp({
    super.key,
    required this.service,
    required this.profileManager,
    required this.pluginManager,
  });

  final KpiService service;
  final ProfileManager profileManager;
  final PluginManager pluginManager;

  @override
  State<KpiApp> createState() => _KpiAppState();
}

class _KpiAppState extends State<KpiApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KPI & Vazifalar',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: KpiTheme.light(),
      darkTheme: KpiTheme.dark(),
      home: KpiMainShell(
        service: widget.service,
        profileManager: widget.profileManager,
        pluginManager: widget.pluginManager,
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class KpiMainShell extends StatefulWidget {
  const KpiMainShell({
    super.key,
    required this.service,
    required this.profileManager,
    required this.pluginManager,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  final KpiService service;
  final ProfileManager profileManager;
  final PluginManager pluginManager;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  State<KpiMainShell> createState() => _KpiMainShellState();
}

class _KpiMainShellState extends State<KpiMainShell> {
  int _currentIndex = 0;
  final SecurityManager _security = SecurityManager();

  @override
  void initState() {
    super.initState();
    widget.service.store.addListener(_onStoreChanged);
    _syncUser();
  }

  @override
  void dispose() {
    widget.service.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _syncUser() {
    final cur = widget.profileManager.current;
    final matched = SecurityManager.defaultAccounts.firstWhere(
      (a) => a.id == cur.id,
      orElse: () => UserAccount(id: cur.id, name: cur.name, role: cur.role, department: cur.department),
    );
    _security.currentUser = matched;
  }

  void _switchUser(UserProfile profile) async {
    await widget.profileManager.switchProfile(profile);
    _syncUser();
    if (mounted) setState(() {});
  }

  void _openAiAssistant(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => KpiAiAssistantSheet(
        pluginManager: widget.pluginManager,
        service: widget.service,
        security: _security,
        onTaskCreated: () => setState(() => _currentIndex = 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = widget.service.store.all.where((e) => e.status == 'active').length;
    final currentUser = _security.currentUser;
    final isDirector = currentUser.role == UserRole.director;
    final isDark = widget.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? KpiTheme.darkBg : KpiTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? KpiTheme.darkCard : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: isDark ? KpiTheme.darkBorder : KpiTheme.lightBorder),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'KPI & Vazifalar',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? KpiTheme.darkText : KpiTheme.lightText,
                    letterSpacing: -0.3,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ':8081 • ${isDirector ? "Direktor" : "Xodim"}',
                      style: TextStyle(fontSize: 10, color: isDark ? KpiTheme.darkTextMuted : KpiTheme.lightTextMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Theme Toggle Button (Light/Dark Mode)
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
              color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF64748B),
              size: 20,
            ),
            tooltip: isDark ? "Yorug' rejim" : "Tungi rejim",
            visualDensity: VisualDensity.compact,
            onPressed: widget.onToggleTheme,
          ),
          // Plagin: O'zbekcha AI Ekosistema Assistent
          if (widget.pluginManager.isPluginActive('plugin_uzbek_ai'))
            IconButton(
              icon: const Icon(Icons.auto_awesome, color: Color(0xFF9333EA), size: 20),
              tooltip: "AI Buyruq",
              visualDensity: VisualDensity.compact,
              onPressed: () => _openAiAssistant(context),
            ),
          // User Avatar Button (Taps to switch to Profile Tab 2)
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 4),
            child: InkWell(
              onTap: () => setState(() => _currentIndex = 2),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3730A3), Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: const Color(0xFFC7D2FE), width: 1.5),
                ),
                child: Center(
                  child: Text(
                    currentUser.name[0],
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Vazifalar ro'yxati (Core List)
          KpiTasksTab(
            service: widget.service,
            security: _security,
            onGoToCreate: () => setState(() => _currentIndex = 1),
          ),
          // Tab 1: Vazifa yaratish (Core Create Form)
          KpiCreateTaskTab(
            service: widget.service,
            security: _security,
            pluginManager: widget.pluginManager,
            onOpenAi: () => _openAiAssistant(context),
            onTaskCreated: () => setState(() => _currentIndex = 0),
          ),
          // Tab 2: Profil & Sozlamalar (Core Profile & Settings)
          KpiProfileTab(
            service: widget.service,
            profileManager: widget.profileManager,
            pluginManager: widget.pluginManager,
            onProfileChanged: _switchUser,
            isDarkMode: widget.isDarkMode,
            onToggleTheme: widget.onToggleTheme,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? KpiTheme.darkCard : Colors.white,
          border: Border(top: BorderSide(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0), width: 1)),
        ),
        child: NavigationBar(
          backgroundColor: isDark ? KpiTheme.darkCard : Colors.white,
          elevation: 0,
          indicatorColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF),
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: activeCount > 0,
                backgroundColor: const Color(0xFF4F46E5),
                label: Text('$activeCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                child: const Icon(Icons.task_alt_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: activeCount > 0,
                backgroundColor: const Color(0xFF4F46E5),
                label: Text('$activeCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                child: const Icon(Icons.task_alt, color: Color(0xFF4F46E5)),
              ),
              label: 'Vazifalar',
            ),
            const NavigationDestination(
              icon: Icon(Icons.add_task_outlined),
              selectedIcon: Icon(Icons.add_task, color: Color(0xFF4F46E5)),
              label: 'Vazifa Qo\'shish',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: Color(0xFF4F46E5)),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 0: VAZIFALAR RO'YXATI (CORE LIST)
// ============================================================================
class KpiTasksTab extends StatefulWidget {
  const KpiTasksTab({
    super.key,
    required this.service,
    required this.security,
    required this.onGoToCreate,
  });

  final KpiService service;
  final SecurityManager security;
  final VoidCallback onGoToCreate;

  @override
  State<KpiTasksTab> createState() => _KpiTasksTabState();
}

class _KpiTasksTabState extends State<KpiTasksTab> {
  String _filter = 'all'; // all, active, submitted, done
  String _search = '';

  List<Entity> get _tasks {
    var items = widget.service.store.all;
    final user = widget.security.currentUser;

    // RBAC: Oddiy xodim o'ziga tegishlisini ko'radi
    if (user.role == UserRole.employee) {
      items = items.where((e) => widget.security.canViewTask(user, e)).toList();
    }

    if (_filter == 'active') {
      items = items.where((e) => e.status == 'active').toList();
    } else if (_filter == 'submitted') {
      items = items.where((e) => e.status == 'submitted').toList();
    } else if (_filter == 'done') {
      items = items.where((e) => e.status == 'done').toList();
    }

    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase().trim();
      items = items.where((e) => e.name.toLowerCase().contains(q) || (e.meta['assigned_to'] ?? '').toString().toLowerCase().contains(q)).toList();
    }

    return items;
  }

  void _submitTask(Entity task) async {
    final user = widget.security.currentUser;
    if (!widget.security.canSubmitTask(user, task)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xatolik: Faqat biriktirilgan xodim vazifani topshira oladi.')),
      );
      return;
    }

    final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'kpi_submit');
    await tool.handler({'id': task.id, 'name': task.name, 'submitted_by': user.name});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${task.name}" topshirildi. Rahbar tasdig\'i kutilmoqda.')),
      );
      setState(() {});
    }
  }

  void _approveTask(Entity task) async {
    final user = widget.security.currentUser;
    if (!widget.security.canApproveTask(user, task)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xatolik: Xodim o\'z vazifasini o\'zi tasdiqlay olmaydi.')),
      );
      return;
    }

    final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'kpi_approve');
    await tool.handler({'id': task.id, 'name': task.name, 'approved_by': user.name});

    // Moliya kassa chiqimi (bonus to'lovi)
    final bonus = UzbekNlp.parseNumber(task.meta['bonus_amount']).toDouble();
    final employee = task.meta['assigned_to'] ?? 'Xodim';
    if (bonus > 0) {
      // 1. Ekotizim Voqealar Shinası (EventBus) orqali e'lon qilish -> Bridge plaginini avtomat ishga tushiradi
      await EventBus.instance.publish(EcosystemEvent(
        name: 'kpi_task_approved',
        sourceApp: 'kpi',
        payload: {
          'task_id': task.id,
          'assigned_to': '$employee',
          'bonus_amount': bonus,
          'task_name': task.name,
        },
      ));

      // 2. Mahalliy zaxira yozish
      await recordFinanceBonusExpense(
        employee: '$employee',
        amount: bonus,
        taskName: task.name,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vazifa tasdiqlandi! ${bonus > 0 ? "$bonus so'm bonus moliyadan yozildi." : ""}')),
      );
      setState(() {});
    }
  }

  void _deleteTask(Entity task) async {
    if (widget.security.currentUser.role != UserRole.director) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xatolik: Faqat direktor o\'chira oladi.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Vazifani o\'chirish', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Haqiqatdan ham "${task.name}" vazifasini butunlay o\'chirmoqchimisiz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      widget.service.store.delete(task.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${task.name}" o\'chirildi.')),
        );
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    final all = widget.service.store.all;
    final activeCount = all.where((e) => e.status == 'active').length;
    final submittedCount = all.where((e) => e.status == 'submitted').length;
    final doneCount = all.where((e) => e.status == 'done').length;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          children: [
            // Top Command Header (Mobile First)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? KpiTheme.darkCard : Colors.white,
                border: Border(bottom: BorderSide(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0), width: 1)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Search box
                      Expanded(
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Topshiriq yoki xodimni qidirish...',
                              hintStyle: TextStyle(fontSize: 13, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF94A3B8)),
                              prefixIcon: Icon(Icons.search_rounded, size: 20, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF94A3B8)),
                              suffixIcon: _search.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear, size: 16, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF94A3B8)),
                                      onPressed: () => setState(() => _search = ''),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            style: TextStyle(fontSize: 13, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A)),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Compact mobile add button
                      IconButton.filled(
                        onPressed: widget.onGoToCreate,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.all(10),
                        ),
                        tooltip: 'Yangi vazifa',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Segmented Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterPill('all', 'Barchasi', all.length, const Color(0xFF4F46E5), isDark),
                        const SizedBox(width: 8),
                        _buildFilterPill('active', '● Jarayonda', activeCount, const Color(0xFF3B82F6), isDark),
                        const SizedBox(width: 8),
                        _buildFilterPill('submitted', '⏳ Tekshiruvda', submittedCount, const Color(0xFF9333EA), isDark),
                        const SizedBox(width: 8),
                        _buildFilterPill('done', '✓ Bajarildi', doneCount, const Color(0xFF16A34A), isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tasks List Area
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(Icons.assignment_outlined, size: 32, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1)),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Hech qanday vazifa topilmadi',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Qidiruv parametrlarini o\'zgartiring yoki yangi vazifa biriktiring.',
                              style: TextStyle(fontSize: 13, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: widget.onGoToCreate,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Birinchi vazifani yaratish'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: tasks.length,
                      itemBuilder: (ctx, idx) {
                        return _buildTaskCard(tasks[idx], isDark);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(String id, String label, int count, Color activeColor, bool isDark) {
    final isSel = _filter == id;
    return InkWell(
      onTap: () => setState(() => _filter = id),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? activeColor.withValues(alpha: isDark ? 0.25 : 0.1) : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSel ? activeColor.withValues(alpha: 0.8) : (isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                color: isSel ? (isDark ? Colors.white : activeColor) : (isDark ? KpiTheme.darkTextMuted : const Color(0xFF475569)),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSel ? activeColor : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(Entity task, bool isDark) {
    final status = task.status;
    final assignedTo = (task.meta['assigned_to'] ?? 'Biriktirilmagan').toString();
    final deadline = (task.meta['deadline'] ?? 'Muddatsiz').toString();
    final priority = (task.meta['priority'] ?? 'normal').toString();
    final bonus = UzbekNlp.parseNumber(task.meta['bonus_amount']);
    final checkpoints = (task.meta['checkpoints'] as List<dynamic>?) ?? [];
    final user = widget.security.currentUser;

    // Status colors and labels
    Color statusBg;
    Color statusText;
    Color statusBorder;
    String statusLabel;

    if (status == 'done') {
      statusBg = isDark ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFFF0FDF4);
      statusText = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF166534);
      statusBorder = isDark ? const Color(0xFF065F46) : const Color(0xFFBBF7D0);
      statusLabel = '✓ Bajarildi';
    } else if (status == 'submitted') {
      statusBg = isDark ? const Color(0xFF3B0764).withValues(alpha: 0.5) : const Color(0xFFFAF5FF);
      statusText = isDark ? const Color(0xFFD8B4FE) : const Color(0xFF6B21A8);
      statusBorder = isDark ? const Color(0xFF7E22CE) : const Color(0xFFE9D5FF);
      statusLabel = '⏳ Tekshiruvda';
    } else {
      statusBg = isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF);
      statusText = isDark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA);
      statusBorder = isDark ? const Color(0xFF4338CA) : const Color(0xFFC7D2FE);
      statusLabel = '● Jarayonda';
    }

    // Priority pill
    Color pBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    Color pText = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
    Color pBorder = isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0);
    String pLabel = 'Oddiy';
    if (priority == 'urgent') {
      pBg = isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2);
      pText = isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
      pBorder = isDark ? const Color(0xFF991B1B) : const Color(0xFFFECACA);
      pLabel = '🚨 Shoshilinch';
    } else if (priority == 'high') {
      pBg = isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB);
      pText = isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
      pBorder = isDark ? const Color(0xFFB45309) : const Color(0xFFFDE68A);
      pLabel = '⚡ Muhim';
    }

    // Checkpoint completion ratio
    final doneCheckpoints = checkpoints.where((c) => c is Map && c['is_done'] == true).length;
    final checkpointRatio = checkpoints.isEmpty ? 0.0 : doneCheckpoints / checkpoints.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? KpiTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Priority, Status and Actions
            Row(
              children: [
                // Priority pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: pBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: pBorder),
                  ),
                  child: Text(
                    pLabel,
                    style: TextStyle(color: pText, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                // Status pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusBorder),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(color: statusText, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const Spacer(),
                if (user.role == UserRole.director)
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF94A3B8)),
                    tooltip: 'Vazifani o\'chirish',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _deleteTask(task),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Task Name / Title
            Text(
              task.name,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),

            // Metadata Row: Assignee, Deadline, Bonus
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Assignee
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF4F46E5),
                        ),
                        child: Center(
                          child: Text(
                            assignedTo.isNotEmpty ? assignedTo[0] : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(assignedTo, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? KpiTheme.darkText : const Color(0xFF334155))),
                    ],
                  ),
                ),
                // Deadline
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_outlined, size: 14, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
                      const SizedBox(width: 5),
                      Text(deadline, style: TextStyle(fontSize: 12, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF475569))),
                    ],
                  ),
                ),
                // Bonus
                if (bonus > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.4) : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? const Color(0xFF065F46) : const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.monetization_on, size: 14, color: Color(0xFF10B981)),
                        const SizedBox(width: 5),
                        Text(
                          '+${bonus.toInt()} so\'m',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF15803D)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // Checkpoints / Subtasks Section
            if (checkpoints.isNotEmpty) ...[
              const SizedBox(height: 14),
              // Progress Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bosqichlar: $doneCheckpoints/${checkpoints.length} bajarildi',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF475569)),
                  ),
                  Text(
                    '${(checkpointRatio * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: checkpointRatio == 1.0 ? const Color(0xFF10B981) : const Color(0xFF818CF8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: checkpointRatio,
                  minHeight: 5,
                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    checkpointRatio == 1.0 ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Checkpoint Items
              ...checkpoints.asMap().entries.map((entry) {
                final c = entry.value;
                final isDone = c is Map && c['is_done'] == true;
                final cTitle = c is Map ? (c['title'] ?? 'Bosqich') : '$c';

                return InkWell(
                  onTap: status == 'done'
                      ? null
                      : () {
                          if (c is Map) {
                            c['is_done'] = !isDone;
                            widget.service.store.update(task.id, metaPatch: {'checkpoints': checkpoints});
                            setState(() {});
                          }
                        },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(
                          isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                          size: 16,
                          color: isDone ? const Color(0xFF10B981) : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$cTitle',
                            style: TextStyle(
                              fontSize: 13,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                              color: isDone
                                  ? (isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8))
                                  : (isDark ? KpiTheme.darkText : const Color(0xFF1E293B)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],

            // Action Buttons (Workflow & RBAC) - Mobile First Stacking
            const SizedBox(height: 12),
            Divider(height: 1, color: isDark ? KpiTheme.darkBorder : const Color(0xFFF1F5F9)),
            const SizedBox(height: 10),

            // Metadata: Biriktirdi / Tasdiqlandi
            Row(
              children: [
                if (status == 'done') ...[
                  const Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Tasdiqlandi: ${task.meta['approved_by'] ?? "Direktor"}',
                      style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF15803D), fontWeight: FontWeight.w600),
                    ),
                  ),
                ] else ...[
                  Icon(Icons.person_pin_circle_outlined, size: 14, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF94A3B8)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Biriktirdi: ${task.meta['assigned_by'] ?? "Direktor"}',
                      style: TextStyle(fontSize: 11, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              ],
            ),

            if (status == 'active') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _submitTask(task),
                  icon: const Icon(Icons.send_rounded, size: 14),
                  label: const Text('Topshirish (Tekshiruvga yuborish)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],

            if (status == 'submitted') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'kpi_reject');
                        await tool.handler({'id': task.id, 'name': task.name, 'reason': 'Qayta ishlansin'});
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.replay_rounded, size: 14, color: Color(0xFFD97706)),
                      label: const Text('Qaytarish', style: TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: isDark ? const Color(0xFFB45309) : const Color(0xFFFDE68A)),
                        backgroundColor: isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: () => _approveTask(task),
                      icon: const Icon(Icons.check_circle_rounded, size: 14),
                      label: const Text('Tasdiqlash & Bonus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 1: VAZIFA YARATISH (CORE CREATE FORM)
// ============================================================================
class KpiCreateTaskTab extends StatefulWidget {
  const KpiCreateTaskTab({
    super.key,
    required this.service,
    required this.security,
    required this.onTaskCreated,
    this.pluginManager,
    this.onOpenAi,
  });

  final KpiService service;
  final SecurityManager security;
  final VoidCallback onTaskCreated;
  final PluginManager? pluginManager;
  final VoidCallback? onOpenAi;

  @override
  State<KpiCreateTaskTab> createState() => _KpiCreateTaskTabState();
}

class _KpiCreateTaskTabState extends State<KpiCreateTaskTab> {
  final _nameController = TextEditingController();
  final _bonusController = TextEditingController(text: '500000');
  String _selectedEmployee = 'Ali';
  String _selectedDeadline = '3 kunda';
  String _selectedPriority = 'normal';
  final List<String> _checkpoints = [];
  final _checkpointController = TextEditingController();

  final List<Map<String, String>> _employees = [
    {'name': 'Ali', 'role': 'Xodim', 'dept': 'Ijrochi'},
    {'name': 'Sardor', 'role': 'Menejer', 'dept': 'Savdo'},
    {'name': 'Vali', 'role': 'Dasturchi', 'dept': 'IT Bo\'lim'},
    {'name': 'Malika', 'role': 'Kassir', 'dept': 'Moliya'},
  ];

  void _addPreset(String name, String emp, String bonus) {
    _nameController.text = name;
    _selectedEmployee = emp;
    _bonusController.text = bonus;
    setState(() {});
  }

  void _saveTask() async {
    final title = _nameController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Iltimos, vazifa nomini kiriting.')),
      );
      return;
    }

    final bonus = UzbekNlp.parseNumber(_bonusController.text.trim());
    final user = widget.security.currentUser;

    final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'kpi_add');
    await tool.handler({
      'name': title,
      'assigned_to': _selectedEmployee,
      'assigned_by': user.name,
      'deadline': _selectedDeadline,
      'bonus_amount': bonus,
      'priority': _selectedPriority,
      'checkpoints': _checkpoints.map((c) => {'title': c, 'is_done': false}).toList(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$title" vazifasi muvaffaqiyatli yaratildi!')),
      );
      _nameController.clear();
      _checkpoints.clear();
      widget.onTaskCreated();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAiActive = widget.pluginManager?.isPluginActive('plugin_uzbek_ai') == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Header
              Text(
                'Yangi Vazifa Biriktirish',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Xodimga yangi KPI topshirig\'ini yuklash, muddat va moliyaviy bonus belgilash',
                style: TextStyle(fontSize: 12, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),

              // AI Smart Delegation Banner (Mobile First)
              if (isAiActive) ...[
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: const Icon(Icons.auto_awesome, color: Color(0xFFC7D2FE), size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'O\'zbekcha AI Assistent',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4)),
                            ),
                            child: const Text('10% LIMIT', style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tabiiy tilda topshiriq bering: AI muddat, xodim va 10% xavfsiz bonusni avtomat hisoblaydi.',
                        style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onOpenAi,
                          icon: const Icon(Icons.flash_on_rounded, size: 16),
                          label: const Text('AI Buyruq Oynasini Ochish', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF312E81),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Quick Templates (Presets)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? KpiTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tezkor namunalar (1-klikda to\'ldirish):',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF475569)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildPresetChip('⚡ Oy hisoboti (Ali • 500k)', 'Oy yakuni hisoboti', 'Ali', '500000', isDark),
                        _buildPresetChip('🎯 Baza auditi (Sardor • 300k)', 'Mijozlar bazasi auditi', 'Sardor', '300000', isDark),
                        _buildPresetChip('🚀 IT testlar (Vali • 700k)', 'Dasturiy testlarni o\'tkazish', 'Vali', '700000', isDark),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Main Form Card (Mobile First)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? KpiTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Field 1: Vazifa nomi
                    Text('Vazifa Nomi *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: TextStyle(fontSize: 14, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Masalan: Serverni yangilash va zaxiralash',
                        hintStyle: TextStyle(fontSize: 13, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: isDark ? KpiTheme.darkBorder : const Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Field 2: Biriktirilgan xodim (2x2 Mobile Grid)
                    Text('Ijrochi Xodim *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 8),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.5,
                      children: _employees.map((emp) {
                        final isSel = _selectedEmployee == emp['name'];
                        return InkWell(
                          onTap: () => setState(() => _selectedEmployee = emp['name']!),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? (isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF))
                                  : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? const Color(0xFF4F46E5) : (isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                                width: isSel ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: isSel ? const Color(0xFF4F46E5) : (isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      emp['name']![0],
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        emp['name']!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                                          color: isSel
                                              ? (isDark ? Colors.white : const Color(0xFF312E81))
                                              : (isDark ? KpiTheme.darkText : const Color(0xFF334155)),
                                        ),
                                      ),
                                      Text(
                                        emp['dept']!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 10, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSel)
                                  const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF4F46E5)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Field 3: Tugash Muddati (Mobile Scrollable Chips)
                    Text('Tugash Muddati *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['Bugun', 'Ertaga', '3 kunda', '1 haftada', '1 oyda'].map((d) {
                          final isSel = _selectedDeadline == d;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(d),
                              selected: isSel,
                              selectedColor: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                              backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                color: isSel ? (isDark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA)) : (isDark ? KpiTheme.darkTextMuted : const Color(0xFF475569)),
                              ),
                              side: BorderSide(
                                color: isSel ? const Color(0xFF6366F1) : (isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                              ),
                              onSelected: (val) {
                                if (val) setState(() => _selectedDeadline = d);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Field 4: Ustuvorlik (Mobile 3-column Expanded Row)
                    Text('Ustuvorlik *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        {'id': 'normal', 'label': 'Oddiy'},
                        {'id': 'high', 'label': '⚡ Muhim'},
                        {'id': 'urgent', 'label': '🚨 Shoshilinch'},
                      ].map((p) {
                        final isSel = _selectedPriority == p['id'];
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ChoiceChip(
                              label: Center(child: Text(p['label']!)),
                              selected: isSel,
                              selectedColor: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                              backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                color: isSel ? (isDark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA)) : (isDark ? KpiTheme.darkTextMuted : const Color(0xFF475569)),
                              ),
                              side: BorderSide(
                                color: isSel ? const Color(0xFF6366F1) : (isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                              ),
                              onSelected: (val) {
                                if (val) setState(() => _selectedPriority = p['id']!);
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Field 5: Bonus Summasi
                    Text('Bonus Summasi (UZS)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bonusController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF15803D)),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.monetization_on_outlined, size: 20, color: Color(0xFF16A34A)),
                        hintText: '500000',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          borderSide: BorderSide(color: Color(0xFF16A34A), width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.4) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? const Color(0xFF065F46) : const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF16A34A)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Xavfsizlik chegarasi: Maksimal 2,000,000 UZS. Chegaradan oshgan qism avtomatik cheklanadi.',
                              style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF15803D), fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Field 6: Nazorat punktlari (Bosqichlar / Checkpoints)
                    Text('Nazorat punktlari (Rejadagi qadamlar):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _checkpointController,
                            style: TextStyle(fontSize: 13, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A)),
                            decoration: InputDecoration(
                              hintText: 'Masalan: 1-bosqich reja',
                              hintStyle: TextStyle(fontSize: 12, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onSubmitted: (_) {
                              final text = _checkpointController.text.trim();
                              if (text.isNotEmpty) {
                                setState(() {
                                  _checkpoints.add(text);
                                  _checkpointController.clear();
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () {
                            final text = _checkpointController.text.trim();
                            if (text.isNotEmpty) {
                              setState(() {
                                _checkpoints.add(text);
                                _checkpointController.clear();
                              });
                            }
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Qo\'shish'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF334155),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                    if (_checkpoints.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ..._checkpoints.asMap().entries.map((e) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(e.value, style: TextStyle(fontSize: 12, color: isDark ? KpiTheme.darkText : const Color(0xFF1E293B))),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, size: 16, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF94A3B8)),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() => _checkpoints.removeAt(e.key)),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 24),

                    // Primary Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _saveTask,
                        icon: const Icon(Icons.add_task_rounded, size: 18),
                        label: const Text(
                          'Vazifani Biriktirish & Boshlash',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, String name, String emp, String bonus, bool isDark) {
    return InkWell(
      onTap: () => _addPreset(name, emp, bonus),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF334155)),
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 2: PROFIL & SOZLAMALAR (ENTERPRISE GRADE PROFILE & SETTINGS)
// ============================================================================
class KpiProfileTab extends StatefulWidget {
  const KpiProfileTab({
    super.key,
    required this.service,
    required this.profileManager,
    required this.pluginManager,
    required this.onProfileChanged,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  final KpiService service;
  final ProfileManager profileManager;
  final PluginManager pluginManager;
  final ValueChanged<UserProfile> onProfileChanged;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  @override
  State<KpiProfileTab> createState() => _KpiProfileTabState();
}

class _KpiProfileTabState extends State<KpiProfileTab> {
  UserProfile get _profile => widget.profileManager.current;
  int _selectedSegment = 0; // 0: Profil & Rollar, 1: Plaginlar Markazi, 2: Infratuzilma & Audit

  void _showPluginConfigDialog(BuildContext context, EcosystemPlugin plugin) {
    showDialog(
      context: context,
      builder: (ctx) => KpiPluginConfigDialog(
        plugin: plugin,
        pluginManager: widget.pluginManager,
        onSaved: () => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plugins = widget.pluginManager.getAllPlugins();
    final isDirector = _profile.role == UserRole.director;
    final isDark = widget.isDarkMode;

    final allTasks = widget.service.store.all;

    // RBAC bo'yicha tegishli vazifalar:
    final relevantTasks = isDirector 
        ? allTasks 
        : allTasks.where((t) => t.meta['assigned_to'] == _profile.name).toList();

    final totalCount = relevantTasks.length;
    final doneCount = relevantTasks.where((t) => t.status == 'done').length;
    final activeCount = relevantTasks.where((t) => t.status == 'active').length;

    // 1. Haqiqiy hisoblangan KPI foizi:
    final double kpiPercent = totalCount > 0 ? (doneCount / totalCount) * 100 : 100.0;
    final String kpiFormatted = totalCount > 0 ? '${kpiPercent.toStringAsFixed(1)}%' : '100%';
    final String kpiSub = totalCount == 0 
        ? 'Vazifalar kutilmoqda' 
        : (doneCount == totalCount ? 'A\'lo ko\'rsatkich' : '$activeCount ta jarayonda');

    // 2. Haqiqiy to'langan / ishlab topilgan bonus fondi:
    final num totalBonusNum = relevantTasks
        .where((t) => t.status == 'done')
        .fold<num>(0, (sum, t) => sum + UzbekNlp.parseNumber(t.meta['bonus_amount']));

    String bonusFormatted;
    if (totalBonusNum >= 1000000) {
      bonusFormatted = '${(totalBonusNum / 1000000).toStringAsFixed(1)}M UZS';
    } else if (totalBonusNum >= 1000) {
      bonusFormatted = '${(totalBonusNum / 1000).toInt()}k UZS';
    } else {
      bonusFormatted = '${totalBonusNum.toInt()} UZS';
    }
    final String bonusSub = isDirector ? 'Jami to\'langan' : 'Ishlab topilgan';

    // 3. Vakolat darajasi:
    String tierLabel;
    String tierDesc;
    if (isDirector) {
      tierLabel = 'Tier 1';
      tierDesc = 'To\'liq boshqaruv';
    } else if (_profile.role == UserRole.salesManager) {
      tierLabel = 'Tier 2';
      tierDesc = 'Menejer nazorati';
    } else {
      tierLabel = 'Tier 3';
      tierDesc = 'Ijrochi xodim';
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --------------------------------------------------------------
              // 1. HERO EXECUTIVE PROFILE CARD (PREMIUM MOBILE IDENTITY)
              // --------------------------------------------------------------
              Container(
                decoration: BoxDecoration(
                  color: isDark ? KpiTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Accent Banner Strip
                    Container(
                      height: 5,
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        gradient: LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF818CF8), Color(0xFF06B6D4)],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              // Avatar with Status Ring
                              Stack(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [Color(0xFF3730A3), Color(0xFF4F46E5)],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        _profile.name[0],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: isDark ? KpiTheme.darkCard : Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              // Name, Role & Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _profile.name,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A),
                                              letterSpacing: -0.4,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(Icons.verified, color: Color(0xFF4F46E5), size: 16),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_profile.department} • Axion Software',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF).withValues(alpha: isDark ? 0.15 : 1.0),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFC7D2FE).withValues(alpha: isDark ? 0.3 : 1.0)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF4F46E5),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            _profile.role.name.toUpperCase(),
                                            style: TextStyle(
                                              color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Divider(height: 1, color: isDark ? KpiTheme.darkBorder : const Color(0xFFF1F5F9)),
                          const SizedBox(height: 10),
                          // Contact Meta Strip
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _buildMetaItem(Icons.email_outlined, _profile.email),
                              _buildMetaItem(Icons.phone_outlined, _profile.phone),
                              _buildMetaItem(Icons.badge_outlined, 'ID: #${_profile.id.toUpperCase()}'),
                              _buildMetaItem(Icons.security, '2FA Himoyalangan'),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Theme Switcher Tile (Interactive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  widget.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                  size: 16,
                                  color: widget.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.isDarkMode ? 'Tungi rejim (Dark Mode)' : 'Kunduzgi rejim (Light Mode)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Switch.adaptive(
                                  value: widget.isDarkMode,
                                  activeTrackColor: const Color(0xFF4F46E5),
                                  onChanged: (_) => widget.onToggleTheme(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --------------------------------------------------------------
              // 2. EXECUTIVE METRICS GRID (2x2 MOBILE FIRST - REAL DYNAMIC DATA)
              // --------------------------------------------------------------
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          'Vazifalar',
                          '$totalCount ta',
                          '$doneCount ta bajarilgan',
                          const Color(0xFF4F46E5),
                          Icons.task_alt,
                          isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          'KPI Reyting',
                          kpiFormatted,
                          kpiSub,
                          const Color(0xFF10B981),
                          Icons.trending_up,
                          isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          'Bonus Fondi',
                          bonusFormatted,
                          bonusSub,
                          const Color(0xFF0284C7),
                          Icons.monetization_on_outlined,
                          isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          'Vakolat',
                          tierLabel,
                          tierDesc,
                          const Color(0xFF7C3AED),
                          Icons.shield_outlined,
                          isDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // --------------------------------------------------------------
              // 3. SEGMENTED TABS CONTROLLER (COMPACT MOBILE PILLS)
              // --------------------------------------------------------------
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildSegmentButton(0, Icons.manage_accounts_outlined, 'Rollar', isDark),
                    _buildSegmentButton(1, Icons.extension_outlined, 'Plaginlar (${plugins.length})', isDark),
                    _buildSegmentButton(2, Icons.dns_outlined, 'Tizim', isDark),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --------------------------------------------------------------
              // 4. SEGMENT CONTENT VIEWS
              // --------------------------------------------------------------
              if (_selectedSegment == 0) _buildRbacSection(isDark),
              if (_selectedSegment == 1) _buildPluginsSection(plugins, isDark),
              if (_selectedSegment == 2) _buildInfrastructureSection(isDark),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // Segment Tab Tugmasi
  Widget _buildSegmentButton(int index, IconData icon, String label, bool isDark) {
    final isSelected = _selectedSegment == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSegment = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? (isDark ? KpiTheme.darkCard : Colors.white) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? const Color(0xFF6366F1) : (isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? KpiTheme.darkText : const Color(0xFF0F172A))
                      : (isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 1-BO'LIM: RBAC ROLLARI VA FOYDALANUVCHILAR (MOBILE FIRST CARD)
  Widget _buildRbacSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foydalanuvchi va Rolni Tanlash (RBAC)',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        Text(
          'Tizim sinovi uchun istalgan akkauntga o\'tishingiz mumkin. Ruxsatlar darhol moslashadi.',
          style: TextStyle(fontSize: 12, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        ...UserProfile.defaultProfiles.map((p) {
          final isCurrent = p.id == _profile.id;
          final isDir = p.role == UserRole.director;
          final isMgr = p.role == UserRole.salesManager;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isCurrent
                  ? (isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF))
                  : (isDark ? KpiTheme.darkCard : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent ? const Color(0xFF6366F1) : (isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                width: isCurrent ? 1.5 : 1.0,
              ),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: isDark ? 0.2 : 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0xFF4F46E5)
                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isDir ? Icons.shield : (isMgr ? Icons.business_center : Icons.person),
                        color: isCurrent ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                  color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isDir
                                      ? (isDark ? const Color(0xFF78350F).withValues(alpha: 0.4) : const Color(0xFFFEF3C7))
                                      : (isCurrent
                                          ? (isDark ? const Color(0xFF312E81) : Colors.white)
                                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  p.role.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isDir
                                        ? (isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E))
                                        : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${p.department} • Axion ID: #${p.id}',
                            style: TextStyle(fontSize: 10, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Faol', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    else
                      OutlinedButton(
                        onPressed: () {
                          widget.onProfileChanged(p);
                          setState(() {});
                        },
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          side: BorderSide(color: isDark ? KpiTheme.darkBorder : const Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'O\'tish',
                          style: TextStyle(fontSize: 11, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF475569), fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildPermissionTag(
                      isDir ? 'To\'liq Tasdiq' : (isMgr ? 'Menejer Tasdig\'i' : 'Vazifa Topshirish'),
                      true,
                    ),
                    _buildPermissionTag(
                      isDir ? 'O\'chirish Huquqi' : 'O\'chirish Cheklangan',
                      isDir,
                    ),
                    _buildPermissionTag(
                      isDir ? 'Moliya Chiqimi' : 'Faqat KPI',
                      isDir,
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // 2-BO'LIM: PLAGINLAR MARKAZI (MICROKERNEL STORE)
  Widget _buildPluginsSection(List<EcosystemPlugin> plugins, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plaginlar Markazi (Microkernel Engine)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Barcha funksiyalar yadroga tegmasdan plagin sifatida ulanadi va boshqariladi.',
                    style: TextStyle(fontSize: 12, color: isDark ? KpiTheme.darkTextMuted : Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0)),
              ),
              child: Text(
                '${plugins.where((p) => p.isEnabled).length} ta faol',
                style: TextStyle(
                  color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Har bir plagin uchun SaaS Card
        ...plugins.map((plugin) {
          final isConfigurable = plugin.id == 'plugin_uzbek_ai' || plugin.id == 'plugin_ecosystem_bridge';
          final isAi = plugin.id == 'plugin_uzbek_ai';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? KpiTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? KpiTheme.darkBorder : (plugin.isEnabled ? const Color(0xFFE2E8F0) : const Color(0xFFF1F5F9)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plugin Icon Box
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isAi
                        ? (isDark ? const Color(0xFF3B0764).withValues(alpha: 0.5) : const Color(0xFFFAF5FF))
                        : (plugin.isEnabled
                            ? (isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF))
                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC))),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isAi
                          ? (isDark ? const Color(0xFF7E22CE) : const Color(0xFFE9D5FF))
                          : (plugin.isEnabled
                              ? (isDark ? const Color(0xFF4338CA) : const Color(0xFFC7D2FE))
                              : (isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0))),
                    ),
                  ),
                  child: Icon(
                    isAi
                        ? Icons.auto_awesome
                        : (plugin.id == 'plugin_ecosystem_bridge' ? Icons.sync_alt : Icons.extension_outlined),
                    color: isAi
                        ? const Color(0xFFC084FC)
                        : (plugin.isEnabled ? const Color(0xFF818CF8) : const Color(0xFF94A3B8)),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Title, Tags, Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              plugin.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: plugin.isEnabled
                                    ? (isDark ? KpiTheme.darkText : const Color(0xFF0F172A))
                                    : (isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'v${plugin.version}',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              plugin.targetApps.join(' • ').toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plugin.description,
                        style: TextStyle(fontSize: 12, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
                      ),
                      if (isConfigurable) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              isAi
                                  ? 'Chegara: ${plugin.metadata['max_bonus_limit'] ?? 2000000} UZS'
                                  : 'Chiqim chegarasi: ${plugin.metadata['max_payout_limit'] ?? 3000000} UZS',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: () => _showPluginConfigDialog(context, plugin),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: isDark ? const Color(0xFF4338CA) : const Color(0xFFC7D2FE)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.tune, size: 12, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Sozlash',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Switch
                Switch.adaptive(
                  value: plugin.isEnabled,
                  activeTrackColor: const Color(0xFF4F46E5),
                  onChanged: (val) async {
                    await widget.pluginManager.togglePlugin(plugin.id, val);
                    setState(() {});
                  },
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // 3-BO'LIM: INFRATUZILMA VA XAVFSIZLIK
  Widget _buildInfrastructureSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tizim va Microservice Infratuzilmasi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        Text(
          'Lokal tarmoqdagi HTTP REST API portlari va xotira holati.',
          style: TextStyle(fontSize: 12, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),

        Container(
          decoration: BoxDecoration(
            color: isDark ? KpiTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _buildMicroserviceRow('KPI Engine API', ':8081', 'Online (Faol)', 'REST API /schema & /execute', true, isDark),
              Divider(height: 1, color: isDark ? KpiTheme.darkBorder : const Color(0xFFF1F5F9)),
              _buildMicroserviceRow('CRM Gateway', ':8082', 'Ulanishga tayyor', 'Bitimlar va mijozlar oqimi', true, isDark),
              Divider(height: 1, color: isDark ? KpiTheme.darkBorder : const Color(0xFFF1F5F9)),
              _buildMicroserviceRow('Moliya & Kassa Hub', ':8083', 'Ulanishga tayyor', 'Kassa chiqim/kirim balansi', true, isDark),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Storage & Audit Log
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Xavfsiz Xotira (StandardStore v1.0)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '• Baza formati: JSON Lines (Fayl darajasidagi xavfsiz blokirovka)\n• Avtomatik zaxira nusxalash (Backup): Har 24 soatda faol\n• Kesh va xotira oqishi: 0 MB (Nol oqish kafolatlangan)',
                style: TextStyle(fontSize: 12, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF475569), height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Yordamchi vidjetlar
  Widget _buildMetaItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildMetricTile(String title, String val, String sub, Color color, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? KpiTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? KpiTheme.darkBorder : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(icon, size: 15, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTag(String text, bool isGranted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isGranted ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isGranted ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isGranted ? const Color(0xFF166534) : const Color(0xFF991B1B),
        ),
      ),
    );
  }

  Widget _buildMicroserviceRow(String name, String port, String status, String note, bool isOnline, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFF10B981) : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? KpiTheme.darkText : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        port,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(note, style: TextStyle(fontSize: 11, color: isDark ? KpiTheme.darkTextMuted : const Color(0xFF64748B))),
              ],
            ),
          ),
          Text(status, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
        ],
      ),
    );
  }
}


// ============================================================================
// PLAGIN: O'ZBEKCHA AI EKOTIZIM ASSISTENTI (MODAL BOTTOM SHEET)
// ============================================================================
class KpiAiAssistantSheet extends StatefulWidget {
  const KpiAiAssistantSheet({
    super.key,
    required this.pluginManager,
    required this.service,
    required this.security,
    required this.onTaskCreated,
  });

  final PluginManager pluginManager;
  final KpiService service;
  final SecurityManager security;
  final VoidCallback onTaskCreated;

  @override
  State<KpiAiAssistantSheet> createState() => _KpiAiAssistantSheetState();
}

class _KpiAiAssistantSheetState extends State<KpiAiAssistantSheet> {
  final _controller = TextEditingController(
    text: "Ali ga saytni bitirish vazifasini topshir va bitirsa oyligiga 10% qo'sh",
  );
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String _error = '';

  void _analyze() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = '';
      _result = null;
    });

    final res = await widget.pluginManager.executeCommand(
      'plugin_uzbek_ai',
      'parse_task_order',
      {'prompt': prompt},
    );

    setState(() {
      _isLoading = false;
      if (res['success'] == true) {
        _result = res;
      } else {
        _error = res['error'] ?? 'Buyruqni tahlil qilib bo\'lmadi.';
      }
    });
  }

  void _confirmAndCreate() async {
    if (_result == null) return;

    final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'kpi_add');
    await tool.handler({
      'name': _result!['name'],
      'assigned_to': _result!['assigned_to'],
      'assigned_by': widget.security.currentUser.name,
      'deadline': _result!['deadline'] ?? '3 kunda',
      'bonus_amount': _result!['bonus_amount'] ?? 0,
      'priority': _result!['priority'] ?? 'high',
      'checkpoints': [
        {'title': '1-bosqich: Dastlabki reja va tahlil', 'is_done': false},
        {'title': '2-bosqich: Asosiy vazifani bajarish', 'is_done': false},
        {'title': '3-bosqich: Yakunlash va topshirish', 'is_done': false},
      ],
    });

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI Vazifasi yaratildi: "${_result!['name']}"')),
      );
      widget.onTaskCreated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF5FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Color(0xFF9333EA), size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'O\'zbekcha AI Ekosistema Assistent',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Tabiiy tilda topshiriq bering • 10% bonus va xavfsizlik chegarasi',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Tezkor namunalar
            const Text('Tezkor namunalar:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildPromptChip('Ali: 10% oylik bonusi', "Ali ga saytni bitirish vazifasini topshir va bitirsa oyligiga 10% qo'sh"),
                _buildPromptChip('Sardor: 300 000 bonus', "Sardorga mijozlar hisobotini tayyorlashni buyur, bonusi 300000"),
                _buildPromptChip('Vali: 50% qo\'sh (Chegara)', "Valiga yangi modul topshir va 50% qo'sh"),
              ],
            ),
            const SizedBox(height: 14),

            // Buyruq kiritish maydoni
            TextField(
              controller: _controller,
              maxLines: 2,
              style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
              decoration: InputDecoration(
                hintText: 'Masalan: Ali ga saytni bitirish vazifasini topshir va bitirsa oyligiga 10% qo\'sh',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF9333EA), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Tahlil qilish tugmasi
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _analyze,
                icon: _isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.psychology_outlined, size: 18),
                label: Text(
                  _isLoading ? 'AI tahlil qilmoqda...' : 'AI Buyrug\'ini Tahlil Qilish',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12))),
                  ],
                ),
              ),
            ],

            // Tahlil natijasi
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified, color: Color(0xFF16A34A), size: 18),
                        const SizedBox(width: 6),
                        const Text('AI Tahlil Natijasi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF9333EA),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Tayyor', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const Divider(height: 20, color: Color(0xFFE9D5FF)),
                    Text(
                      '• Vazifa: ${_result!['name']}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Biriktirildi: ${_result!['assigned_to']}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Hisoblangan bonus: ${(_result!['bonus_amount'] as num).toInt()} so\'m ${_result!['is_percent'] ? "(${_result!['percent_value']}% oylikdan)" : ""}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF15803D), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Muddat: ${_result!['deadline']}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                    ),

                    if (_result!['is_capped'] == true) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${_result!['warning']}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: _confirmAndCreate,
                        icon: const Icon(Icons.add_task_rounded, size: 16),
                        label: const Text('Tasdiqlash va Vazifani Saqlash', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChip(String label, String prompt) {
    return InkWell(
      onTap: () {
        _controller.text = prompt;
        _analyze();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF475569)),
        ),
      ),
    );
  }
}

// ============================================================================
// PLAGIN SOZLAMALARI VA CHEGARALAR DIALOGI (PLUGIN CONFIG DIALOG)
// ============================================================================
class KpiPluginConfigDialog extends StatefulWidget {
  const KpiPluginConfigDialog({
    super.key,
    required this.plugin,
    required this.pluginManager,
    required this.onSaved,
  });

  final EcosystemPlugin plugin;
  final PluginManager pluginManager;
  final VoidCallback onSaved;

  @override
  State<KpiPluginConfigDialog> createState() => _KpiPluginConfigDialogState();
}

class _KpiPluginConfigDialogState extends State<KpiPluginConfigDialog> {
  late final TextEditingController _limitController;

  @override
  void initState() {
    super.initState();
    final isAi = widget.plugin.id == 'plugin_uzbek_ai';
    final curLimit = isAi
        ? (widget.plugin.metadata['max_bonus_limit'] ?? 2000000)
        : (widget.plugin.metadata['max_payout_limit'] ?? 3000000);
    _limitController = TextEditingController(text: '$curLimit');
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  void _save() async {
    final val = double.tryParse(_limitController.text.trim()) ?? 2000000.0;
    if (widget.plugin.id == 'plugin_uzbek_ai') {
      widget.plugin.metadata['max_bonus_limit'] = val;
      final handler = widget.pluginManager.getHandler('plugin_uzbek_ai') as UzbekAiPluginHandler?;
      if (handler != null) {
        handler.maxBonusLimit = val;
      }
    } else if (widget.plugin.id == 'plugin_ecosystem_bridge') {
      widget.plugin.metadata['max_payout_limit'] = val;
      final handler = widget.pluginManager.getHandler('plugin_ecosystem_bridge') as EcosystemBridgePluginHandler?;
      if (handler != null) {
        handler.maxPayoutLimit = val;
      }
    }
    await widget.pluginManager.registerPlugin(widget.plugin);
    if (mounted) {
      Navigator.of(context).pop();
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAi = widget.plugin.id == 'plugin_uzbek_ai';

    return AlertDialog(
      title: Row(
        children: [
          Icon(isAi ? Icons.auto_awesome : Icons.sync_alt, color: Colors.purple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAi ? 'AI Bonus Chegarasi' : 'Bridge Chiqim Chegarasi',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAi
                  ? 'AI orqali topshiriq berilganda har bir vazifa uchun berilishi mumkin bo\'lgan maksimal bonus miqdori (Guardrail):'
                  : 'KPI va CRM hodisalari orqali Moliyaga avtomatik kassa chiqimi yozilishining xavfsizlik chegarasi:',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _limitController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: isAi ? 'Maksimal bonus chegarasi (so\'m)' : 'Maksimal chiqim chegarasi (so\'m)',
                suffixText: 'so\'m',
                border: const OutlineInputBorder(),
              ),
            ),
            if (isAi) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Xodimlar bazaviy oyliklari:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    SizedBox(height: 4),
                    Text('• Ali: 5 000 000 so\'m (10% = 500 000)', style: TextStyle(fontSize: 11)),
                    Text('• Sardor: 6 000 000 so\'m (10% = 600 000)', style: TextStyle(fontSize: 11)),
                    Text('• Vali: 4 500 000 so\'m (10% = 450 000)', style: TextStyle(fontSize: 11)),
                    Text('• Malika: 4 000 000 so\'m (10% = 400 000)', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Bekor qilish'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}

