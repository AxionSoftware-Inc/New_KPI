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

class KpiApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KPI & Vazifalar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      home: KpiMainShell(
        service: service,
        profileManager: profileManager,
        pluginManager: pluginManager,
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
  });

  final KpiService service;
  final ProfileManager profileManager;
  final PluginManager pluginManager;

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

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
        ),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Axion KPI & Vazifalar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: const Text(
                        'ENTERPRISE',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Biznes Ekotizim • ${isDirector ? "Boshqaruv" : "Xodim"} Rejimi',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
            const SizedBox(width: 16),
            // User Role Tag (Clickable to switch to profile)
            InkWell(
              onTap: () => setState(() => _currentIndex = 2),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDirector ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDirector ? const Color(0xFFC7D2FE) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isDirector ? const Color(0xFF4F46E5) : const Color(0xFF0EA5E9),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentUser.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDirector ? const Color(0xFF3730A3) : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${isDirector ? "Direktor" : "Xodim"})',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isDirector ? const Color(0xFF6366F1) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Plagin: O'zbekcha AI Ekosistema Assistent
          if (widget.pluginManager.isPluginActive('plugin_uzbek_ai'))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => _openAiAssistant(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF5FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFF9333EA), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'AI Buyruq',
                        style: TextStyle(color: Color(0xFF7E22CE), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Network Status Badge
          Container(
            margin: const EdgeInsets.only(right: 18),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi, size: 13, color: Color(0xFF16A34A)),
                SizedBox(width: 5),
                Text(':8081 Onlayn', style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold, fontSize: 11)),
              ],
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
            profileManager: widget.profileManager,
            pluginManager: widget.pluginManager,
            onProfileChanged: _switchUser,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
        ),
        child: NavigationBar(
          backgroundColor: Colors.white,
          elevation: 0,
          indicatorColor: const Color(0xFFEEF2FF),
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
              label: 'Profil & Sozlamalar',
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
    await tool.handler({'id': task.id, 'submitted_by': user.name});
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
    await tool.handler({'id': task.id, 'approved_by': user.name});

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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            // Top Command Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
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
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Topshiriq yoki xodim nomini qidirish...',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                              suffixIcon: _search.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                                      onPressed: () => setState(() => _search = ''),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Create CTA button
                      FilledButton.icon(
                        onPressed: widget.onGoToCreate,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Yangi Vazifa', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Segmented Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterPill('all', 'Barchasi', all.length, const Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        _buildFilterPill('active', '● Jarayonda', activeCount, const Color(0xFF3B82F6)),
                        const SizedBox(width: 8),
                        _buildFilterPill('submitted', '⏳ Tekshiruvda', submittedCount, const Color(0xFF9333EA)),
                        const SizedBox(width: 8),
                        _buildFilterPill('done', '✓ Bajarildi', doneCount, const Color(0xFF16A34A)),
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
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.assignment_outlined, size: 32, color: Color(0xFF6366F1)),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Hech qanday vazifa topilmadi',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Qidiruv parametrlarini o\'zgartiring yoki yangi vazifa biriktiring.',
                              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      itemCount: tasks.length,
                      itemBuilder: (ctx, idx) {
                        return _buildTaskCard(tasks[idx]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(String id, String label, int count, Color activeColor) {
    final isSel = _filter == id;
    return InkWell(
      onTap: () => setState(() => _filter = id),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? activeColor.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSel ? activeColor.withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
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
                color: isSel ? activeColor : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSel ? activeColor : const Color(0xFFCBD5E1),
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

  Widget _buildTaskCard(Entity task) {
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
      statusBg = const Color(0xFFF0FDF4);
      statusText = const Color(0xFF166534);
      statusBorder = const Color(0xFFBBF7D0);
      statusLabel = '✓ Bajarildi';
    } else if (status == 'submitted') {
      statusBg = const Color(0xFFFAF5FF);
      statusText = const Color(0xFF6B21A8);
      statusBorder = const Color(0xFFE9D5FF);
      statusLabel = '⏳ Tekshiruvda';
    } else {
      statusBg = const Color(0xFFEEF2FF);
      statusText = const Color(0xFF4338CA);
      statusBorder = const Color(0xFFC7D2FE);
      statusLabel = '● Jarayonda';
    }

    // Priority pill
    Color pBg = const Color(0xFFF1F5F9);
    Color pText = const Color(0xFF475569);
    Color pBorder = const Color(0xFFE2E8F0);
    String pLabel = 'Oddiy';
    if (priority == 'urgent') {
      pBg = const Color(0xFFFEF2F2);
      pText = const Color(0xFF991B1B);
      pBorder = const Color(0xFFFECACA);
      pLabel = '🚨 Shoshilinch';
    } else if (priority == 'high') {
      pBg = const Color(0xFFFFFBEB);
      pText = const Color(0xFF92400E);
      pBorder = const Color(0xFFFDE68A);
      pLabel = '⚡ Muhim';
    }

    // Checkpoint completion ratio
    final doneCheckpoints = checkpoints.where((c) => c is Map && c['is_done'] == true).length;
    final checkpointRatio = checkpoints.isEmpty ? 0.0 : doneCheckpoints / checkpoints.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
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
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFF94A3B8)),
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
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFF0F172A),
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
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
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
                      Text(assignedTo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                    ],
                  ),
                ),
                // Deadline
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_outlined, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 5),
                      Text(deadline, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                    ],
                  ),
                ),
                // Bonus
                if (bonus > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.monetization_on, size: 14, color: Color(0xFF16A34A)),
                        const SizedBox(width: 5),
                        Text(
                          '+${bonus.toInt()} so\'m',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                  ),
                  Text(
                    '${(checkpointRatio * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: checkpointRatio == 1.0 ? const Color(0xFF16A34A) : const Color(0xFF4F46E5),
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
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    checkpointRatio == 1.0 ? const Color(0xFF16A34A) : const Color(0xFF4F46E5),
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
                          color: isDone ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$cTitle',
                            style: TextStyle(
                              fontSize: 13,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                              color: isDone ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],

            // Action Buttons (Workflow & RBAC)
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Timestamp / Created by or Approved by
                if (status == 'done')
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: Color(0xFF16A34A)),
                      const SizedBox(width: 4),
                      Text(
                        'Tasdiqlandi: ${task.meta['approved_by'] ?? "Direktor"}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                      ),
                    ],
                  )
                else
                  Text(
                    'Biriktirdi: ${task.meta['assigned_by'] ?? "Direktor"}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),

                // Workflow action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status == 'active')
                      FilledButton.icon(
                        onPressed: () => _submitTask(task),
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label: const Text('Topshirish', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    if (status == 'submitted') ...[
                      OutlinedButton.icon(
                        onPressed: () async {
                          final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'kpi_reject');
                          await tool.handler({'id': task.id, 'reason': 'Qayta ishlansin'});
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.replay_rounded, size: 14, color: Color(0xFFD97706)),
                        label: const Text('Qaytarish', style: TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFDE68A)),
                          backgroundColor: const Color(0xFFFFFBEB),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _approveTask(task),
                        icon: const Icon(Icons.check_circle_rounded, size: 14),
                        label: const Text('Tasdiqlash & To\'lash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Header
              const Text(
                'Yangi Vazifa Biriktirish',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Xodimga yangi KPI topshirig\'ini yuklash, muddat va moliyaviy bonus belgilash',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),

              // AI Smart Delegation Banner
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
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Icon(Icons.auto_awesome, color: Color(0xFFC7D2FE), size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'O\'zbekcha AI Ekosistema Assistent',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4)),
                                    ),
                                    child: const Text('10% BONUS & LIMIT', style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tabiiy tilda topshiriq bering: AI muddat, xodim va xavfsiz 10% bonusni o\'zi hisoblaydi.',
                                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: widget.onOpenAi,
                          icon: const Icon(Icons.flash_on_rounded, size: 16),
                          label: const Text('AI Oyna', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF312E81),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Quick Templates (Presets)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tezkor namunalar (1-klikda to\'ldirish):',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildPresetChip('⚡ Oy yakuni hisoboti (Ali • 500k)', 'Oy yakuni hisoboti', 'Ali', '500000'),
                        _buildPresetChip('🎯 Mijozlar bazasi auditi (Sardor • 300k)', 'Mijozlar bazasi auditi', 'Sardor', '300000'),
                        _buildPresetChip('🚀 Dasturiy testlarni o\'tkazish (Vali • 700k)', 'Dasturiy testlarni o\'tkazish', 'Vali', '700000'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Main Form Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Field 1: Vazifa nomi
                    const Text('Vazifa Nomi *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Masalan: Serverni yangilash va zaxiralash',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Field 2: Biriktirilgan xodim (Selectable User Cards)
                    const Text('Ijrochi Xodim *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _employees.map((emp) {
                        final isSel = _selectedEmployee == emp['name'];
                        return InkWell(
                          onTap: () => setState(() => _selectedEmployee = emp['name']!),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                width: isSel ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isSel ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      emp['name']![0],
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      emp['name']!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                                        color: isSel ? const Color(0xFF312E81) : const Color(0xFF334155),
                                      ),
                                    ),
                                    Text(
                                      '${emp['role']} • ${emp['dept']}',
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                                if (isSel) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF4F46E5)),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Field 3 & 4: Deadline & Priority in 2 Columns
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Deadline
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Tugash Muddati *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: ['Bugun', 'Ertaga', '3 kunda', '1 haftada', '1 oyda'].map((d) {
                                  final isSel = _selectedDeadline == d;
                                  return ChoiceChip(
                                    label: Text(d),
                                    selected: isSel,
                                    selectedColor: const Color(0xFFEEF2FF),
                                    backgroundColor: const Color(0xFFF8FAFC),
                                    labelStyle: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      color: isSel ? const Color(0xFF4338CA) : const Color(0xFF475569),
                                    ),
                                    side: BorderSide(
                                      color: isSel ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                                    ),
                                    onSelected: (val) {
                                      if (val) setState(() => _selectedDeadline = d);
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Priority
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Ustuvorlik *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  {'id': 'normal', 'label': 'Oddiy'},
                                  {'id': 'high', 'label': '⚡ Muhim'},
                                  {'id': 'urgent', 'label': '🚨 Shoshilinch'},
                                ].map((p) {
                                  final isSel = _selectedPriority == p['id'];
                                  return ChoiceChip(
                                    label: Text(p['label']!),
                                    selected: isSel,
                                    selectedColor: const Color(0xFFEEF2FF),
                                    backgroundColor: const Color(0xFFF8FAFC),
                                    labelStyle: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      color: isSel ? const Color(0xFF4338CA) : const Color(0xFF475569),
                                    ),
                                    side: BorderSide(
                                      color: isSel ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                                    ),
                                    onSelected: (val) {
                                      if (val) setState(() => _selectedPriority = p['id']!);
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Field 5: Bonus Summasi
                    const Text('Bonus Summasi (UZS)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bonusController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.monetization_on_outlined, size: 20, color: Color(0xFF16A34A)),
                        hintText: '500000',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 14, color: Color(0xFF16A34A)),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Xavfsizlik chegarasi: Maksimal 2,000,000 UZS. Chegaradan oshgan qism avtomatik cheklanadi.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Field 6: Nazorat punktlari (Bosqichlar / Checkpoints)
                    const Text('Nazorat punktlari (Rejadagi qadamlar):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _checkpointController,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Masalan: 1-bosqich: Loyihani tahlil qilish',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                    if (_checkpoints.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ..._checkpoints.asMap().entries.map((e) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(e.value, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B))),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() => _checkpoints.removeAt(e.key)),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 28),

                    // Primary Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _saveTask,
                        icon: const Icon(Icons.add_task_rounded, size: 18),
                        label: const Text(
                          'Vazifani Biriktirish & Ishga Tushirish',
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

  Widget _buildPresetChip(String label, String name, String emp, String bonus) {
    return InkWell(
      onTap: () => _addPreset(name, emp, bonus),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
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
    required this.profileManager,
    required this.pluginManager,
    required this.onProfileChanged,
  });

  final ProfileManager profileManager;
  final PluginManager pluginManager;
  final ValueChanged<UserProfile> onProfileChanged;

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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --------------------------------------------------------------
              // 1. HERO EXECUTIVE PROFILE CARD (PREMIUM WORKSPACE IDENTITY)
              // --------------------------------------------------------------
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Accent Banner Strip
                    Container(
                      height: 6,
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        gradient: LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF818CF8), Color(0xFF06B6D4)],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Avatar with Status Ring
                              Stack(
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
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
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        _profile.name[0],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 3),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 20),
                              // Name, Role & Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          _profile.name,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.verified, color: Color(0xFF4F46E5), size: 18),
                                        const Spacer(),
                                        // Enterprise Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEEF2FF),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: const Color(0xFFC7D2FE)),
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
                                              const SizedBox(width: 6),
                                              Text(
                                                _profile.role.name.toUpperCase(),
                                                style: const TextStyle(
                                                  color: Color(0xFF3730A3),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${_profile.department} Departamenti • Axion Software Inc.',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF475569),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Contact Meta Strip
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 8,
                                      children: [
                                        _buildMetaItem(Icons.email_outlined, _profile.email),
                                        _buildMetaItem(Icons.phone_outlined, _profile.phone),
                                        _buildMetaItem(Icons.badge_outlined, 'ID: #${_profile.id.toUpperCase()}'),
                                        _buildMetaItem(Icons.security, '2FA Himoyalangan'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --------------------------------------------------------------
              // 2. EXECUTIVE METRICS STRIP (4 STATS CARDS)
              // --------------------------------------------------------------
              Row(
                children: [
                  Expanded(child: _buildMetricTile('Vazifalar Soni', '18 ta', '14 ta bajarilgan', const Color(0xFF4F46E5), Icons.task_alt)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricTile('KPI Reytingi', '98.4%', 'A\'lo daraja', const Color(0xFF10B981), Icons.trending_up)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricTile('Bonus Fondi', '2.5M UZS', 'Moliyadan tasdiqlangan', const Color(0xFF0284C7), Icons.monetization_on_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricTile('Vakolat Darajasi', isDirector ? 'Tier 1' : 'Tier 3', isDirector ? 'To\'liq nazorat' : 'Standart xodim', const Color(0xFF7C3AED), Icons.shield_outlined)),
                ],
              ),
              const SizedBox(height: 24),

              // --------------------------------------------------------------
              // 3. SEGMENTED TABS CONTROLLER (LINEAR / STRIPE STYLE)
              // --------------------------------------------------------------
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildSegmentButton(0, Icons.manage_accounts_outlined, 'Foydalanuvchi & RBAC Rollar'),
                    _buildSegmentButton(1, Icons.extension_outlined, 'Plaginlar Markazi (${plugins.length})'),
                    _buildSegmentButton(2, Icons.dns_outlined, 'Infratuzilma & Xavfsizlik'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --------------------------------------------------------------
              // 4. SEGMENT CONTENT VIEWS
              // --------------------------------------------------------------
              if (_selectedSegment == 0) _buildRbacSection(),
              if (_selectedSegment == 1) _buildPluginsSection(plugins),
              if (_selectedSegment == 2) _buildInfrastructureSection(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // Segment Tab Tugmasi
  Widget _buildSegmentButton(int index, IconData icon, String label) {
    final isSelected = _selectedSegment == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSegment = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
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
                size: 16,
                color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 1-BO'LIM: RBAC ROLLARI VA FOYDALANUVCHILAR
  Widget _buildRbacSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Foydalanuvchi va Rolni Tanlash (RBAC)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tizim sinovi uchun istalgan akkauntga o\'tishingiz mumkin. Ruxsatlar darhol moslashadi.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),
        ...UserProfile.defaultProfiles.map((p) {
          final isCurrent = p.id == _profile.id;
          final isDir = p.role == UserRole.director;
          final isMgr = p.role == UserRole.salesManager;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isCurrent ? const Color(0xFFEEF2FF) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                width: isCurrent ? 1.5 : 1.0,
              ),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isCurrent ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDir ? Icons.shield : (isMgr ? Icons.business_center : Icons.person),
                  color: isCurrent ? Colors.white : const Color(0xFF64748B),
                  size: 20,
                ),
              ),
              title: Row(
                children: [
                  Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDir
                          ? const Color(0xFFFEF3C7)
                          : (isCurrent ? Colors.white : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p.role.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDir ? const Color(0xFF92400E) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
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
              ),
              trailing: isCurrent
                  ? Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF4F46E5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 14, color: Colors.white),
                    )
                  : OutlinedButton(
                      onPressed: () {
                        widget.onProfileChanged(p);
                        setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('O\'tish', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                    ),
              onTap: () {
                widget.onProfileChanged(p);
                setState(() {});
              },
            ),
          );
        }),
      ],
    );
  }

  // 2-BO'LIM: PLAGINLAR MARKAZI (MICROKERNEL STORE)
  Widget _buildPluginsSection(List<EcosystemPlugin> plugins) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Plaginlar Markazi (Microkernel Engine)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Barcha funksiyalar yadroga tegmasdan plagin sifatida ulanadi va boshqariladi.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Text(
                '${plugins.where((p) => p.isEnabled).length} ta faol',
                style: const TextStyle(color: Color(0xFF065F46), fontSize: 11, fontWeight: FontWeight.bold),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: plugin.isEnabled ? const Color(0xFFE2E8F0) : const Color(0xFFF1F5F9),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
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
                        ? const Color(0xFFFAF5FF)
                        : (plugin.isEnabled ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isAi
                          ? const Color(0xFFE9D5FF)
                          : (plugin.isEnabled ? const Color(0xFFC7D2FE) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Icon(
                    isAi
                        ? Icons.auto_awesome
                        : (plugin.id == 'plugin_ecosystem_bridge' ? Icons.sync_alt : Icons.extension_outlined),
                    color: isAi
                        ? const Color(0xFF9333EA)
                        : (plugin.isEnabled ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8)),
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
                          Text(
                            plugin.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: plugin.isEnabled ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'v${plugin.version}',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              plugin.targetApps.join(' • ').toUpperCase(),
                              style: const TextStyle(fontSize: 9, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plugin.description,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      if (isConfigurable) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              isAi
                                  ? 'Chegara: ${plugin.metadata['max_bonus_limit'] ?? 2000000} UZS'
                                  : 'Chiqim chegarasi: ${plugin.metadata['max_payout_limit'] ?? 3000000} UZS',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF4F46E5), fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: () => _showPluginConfigDialog(context, plugin),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFC7D2FE)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.tune, size: 12, color: Color(0xFF4F46E5)),
                                    SizedBox(width: 4),
                                    Text('Sozlash', style: TextStyle(fontSize: 11, color: Color(0xFF4F46E5), fontWeight: FontWeight.bold)),
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
  Widget _buildInfrastructureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tizim va Microservice Infratuzilmasi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Lokal tarmoqdagi HTTP REST API portlari va xotira holati.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _buildMicroserviceRow('KPI Engine API', ':8081', 'Online (Faol)', 'REST API /schema & /execute', true),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              _buildMicroserviceRow('CRM Gateway', ':8082', 'Ulanishga tayyor', 'Bitimlar va mijozlar oqimi', true),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              _buildMicroserviceRow('Moliya & Kassa Hub', ':8083', 'Ulanishga tayyor', 'Kassa chiqim/kirim balansi', true),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Storage & Audit Log
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 18),
                  SizedBox(width: 8),
                  Text('Xavfsiz Xotira (StandardStore v1.0)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                ],
              ),
              SizedBox(height: 6),
              Text(
                '• Baza formati: JSON Lines (Fayl darajasidagi xavfsiz blokirovka)\n• Avtomatik zaxira nusxalash (Backup): Har 24 soatda faol\n• Kesh va xotira oqishi: 0 MB (Nol oqish kafolatlangan)',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.5),
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

  Widget _buildMetricTile(String title, String val, String sub, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
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
              Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              Icon(icon, size: 15, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
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

  Widget _buildMicroserviceRow(String name, String port, String status, String note, bool isOnline) {
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
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(port, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    ),
                  ],
                ),
                Text(note, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
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

