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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.indigo, size: 24),
            const SizedBox(width: 8),
            const Text(
              'KPI & Vazifalar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(width: 12),
            // Faol profil nishoni
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _security.currentUser.role == UserRole.director
                    ? Colors.indigo.shade50
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _security.currentUser.role == UserRole.director
                      ? Colors.indigo.shade300
                      : Colors.blue.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _security.currentUser.role == UserRole.director ? Icons.shield : Icons.person,
                    size: 13,
                    color: _security.currentUser.role == UserRole.director
                        ? Colors.indigo.shade800
                        : Colors.blue.shade800,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.profileManager.current.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _security.currentUser.role == UserRole.director
                          ? Colors.indigo.shade900
                          : Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Plagin: O'zbekcha AI Ekosistema Assistent
          if (widget.pluginManager.isPluginActive('plugin_uzbek_ai'))
            IconButton(
              icon: const Icon(Icons.auto_awesome, color: Colors.purple),
              tooltip: "O'zbekcha AI Assistent",
              onPressed: () => _openAiAssistant(context),
            ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade400),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi, size: 13, color: Colors.green),
                SizedBox(width: 5),
                Text(':8081', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: activeCount > 0,
              label: Text('$activeCount'),
              child: const Icon(Icons.task_alt),
            ),
            label: 'Vazifalar',
          ),
          const NavigationDestination(
            icon: Icon(Icons.add_task),
            label: 'Vazifa Qo\'shish',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil & Sozlamalar',
          ),
        ],
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
  String _filter = 'all'; // all, active, submitted, done, overdue
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
    widget.service.store.delete(task.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    final all = widget.service.store.all;
    final activeCount = all.where((e) => e.status == 'active').length;
    final submittedCount = all.where((e) => e.status == 'submitted').length;
    final doneCount = all.where((e) => e.status == 'done').length;

    return Column(
      children: [
        // Qidirish va Filtrlar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Vazifa yoki xodim nomini qidirish...',
                  hintStyle: const TextStyle(fontSize: 13),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF1F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      selected: _filter == 'all',
                      label: Text('Barchasi (${all.length})'),
                      onSelected: (_) => setState(() => _filter = 'all'),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      selected: _filter == 'active',
                      label: Text('Bajarilmoqda ($activeCount)'),
                      selectedColor: Colors.amber.shade100,
                      onSelected: (_) => setState(() => _filter = 'active'),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      selected: _filter == 'submitted',
                      label: Text('Tekshiruvda ($submittedCount)'),
                      selectedColor: Colors.purple.shade100,
                      onSelected: (_) => setState(() => _filter = 'submitted'),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      selected: _filter == 'done',
                      label: Text('Bajarildi ($doneCount)'),
                      selectedColor: Colors.green.shade100,
                      onSelected: (_) => setState(() => _filter = 'done'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Vazifalar ro'yxati
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'Hech qanday vazifa topilmadi',
                        style: TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: widget.onGoToCreate,
                        icon: const Icon(Icons.add),
                        label: const Text('Yangi vazifa yaratish'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: tasks.length,
                  itemBuilder: (ctx, idx) {
                    final task = tasks[idx];
                    return _buildTaskCard(task);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(Entity task) {
    final status = task.status;
    final assignedTo = task.meta['assigned_to'] ?? 'Biriktirilmagan';
    final deadline = task.meta['deadline'] ?? 'Muddatsiz';
    final bonus = UzbekNlp.parseNumber(task.meta['bonus_amount']);
    final checkpoints = (task.meta['checkpoints'] as List<dynamic>?) ?? [];
    final user = widget.security.currentUser;

    Color statusColor;
    String statusText;
    if (status == 'done') {
      statusColor = Colors.green;
      statusText = 'Bajarildi ✅';
    } else if (status == 'submitted') {
      statusColor = Colors.purple;
      statusText = 'Tekshiruvda ⏳';
    } else {
      statusColor = Colors.amber.shade800;
      statusText = 'Jarayonda';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                if (user.role == UserRole.director) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                    onPressed: () => _deleteTask(task),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Metadata: Xodim, Muddat, Bonus
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  avatar: const Icon(Icons.person, size: 14),
                  label: Text('$assignedTo', style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Chip(
                  avatar: const Icon(Icons.calendar_today, size: 14),
                  label: Text('$deadline', style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (bonus > 0)
                  Chip(
                    avatar: const Icon(Icons.monetization_on, size: 14, color: Colors.green),
                    label: Text('+${bonus.toInt()} so\'m', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),

            // Checkpoints / Nazorat punktlari
            if (checkpoints.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Bosqichlar:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(isDone ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: isDone ? Colors.green : Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$cTitle',
                            style: TextStyle(
                              fontSize: 12,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                              color: isDone ? Colors.grey : Colors.black87,
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
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status == 'active')
                  FilledButton.icon(
                    onPressed: () => _submitTask(task),
                    icon: const Icon(Icons.send, size: 14),
                    label: const Text('Topshirish', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (status == 'submitted') ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final tool = widget.service.schema.tools.firstWhere((t) => t.name == 'kpi_reject');
                      await tool.handler({'id': task.id, 'reason': 'Qayta ishlansin'});
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.replay, size: 14, color: Colors.orange),
                    label: const Text('Qaytarish', style: TextStyle(fontSize: 12, color: Colors.orange)),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _approveTask(task),
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('Tasdiqlash', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
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

  final List<String> _employees = ['Ali', 'Sardor', 'Vali', 'Malika'];

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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Yangi Vazifa Yaratish',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Xodimga vazifa yuklatish, muddat va bonus belgilash',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Plagin: O'zbekcha AI Ekosistema Assistent
          if (widget.pluginManager?.isPluginActive('plugin_uzbek_ai') == true) ...[
            Card(
              elevation: 0,
              color: Colors.purple.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.purple.shade200),
              ),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.auto_awesome, color: Colors.purple),
                title: const Text(
                  'AI Ovozli va Matnli Buyruq (10% Oylik Bonusi)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple),
                ),
                subtitle: const Text(
                  'Tabiiy tilda topshiriq bering, AI bonus va xavfsizlik chegarasini o\'zi hisoblaydi',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.purple),
                onTap: widget.onOpenAi,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Tezkor namunalar
          const Text('Tezkor namunalar:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Oy yakuni hisoboti (Ali)'),
                onPressed: () => _addPreset('Oy yakuni hisoboti', 'Ali', '500000'),
              ),
              ActionChip(
                label: const Text('Mijozlar bazasini tozalash (Sardor)'),
                onPressed: () => _addPreset('Mijozlar bazasini tozalash', 'Sardor', '300000'),
              ),
              ActionChip(
                label: const Text('Dasturiy testlarni o\'tkazish (Vali)'),
                onPressed: () => _addPreset('Dasturiy testlarni o\'tkazish', 'Vali', '700000'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Vazifa nomi
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Vazifa nomi *',
              hintText: 'Masalan: Serverni yangilash va zaxiralash',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Ijrochini tanlash
          const Text('Biriktirilgan xodim:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _employees.map((emp) {
              final isSel = _selectedEmployee == emp;
              return ChoiceChip(
                label: Text(emp),
                selected: isSel,
                onSelected: (val) {
                  if (val) setState(() => _selectedEmployee = emp);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Muddat
          const Text('Tugash muddati:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: ['Bugun', 'Ertaga', '3 kunda', '1 haftada', '1 oyda'].map((d) {
              final isSel = _selectedDeadline == d;
              return ChoiceChip(
                label: Text(d),
                selected: isSel,
                onSelected: (val) {
                  if (val) setState(() => _selectedDeadline = d);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Bonus
          TextField(
            controller: _bonusController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Bonus summasi (so\'m)',
              hintText: '500000',
              prefixIcon: Icon(Icons.monetization_on_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Ustuvorlik
          const Text('Ustuvorlik:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              {'id': 'normal', 'label': 'Oddiy'},
              {'id': 'high', 'label': 'Muhim'},
              {'id': 'urgent', 'label': 'Shoshilinch'},
            ].map((p) {
              final isSel = _selectedPriority == p['id'];
              return ChoiceChip(
                label: Text(p['label']!),
                selected: isSel,
                onSelected: (val) {
                  if (val) setState(() => _selectedPriority = p['id']!);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Nazorat punktlari (Checkpoints)
          const Text('Nazorat punktlari (Qadamlar):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _checkpointController,
                  decoration: const InputDecoration(
                    hintText: 'Qadam nomi (masalan: 1-bosqich: Dastlabki reja)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  final text = _checkpointController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _checkpoints.add(text);
                      _checkpointController.clear();
                    });
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Qo\'shish'),
              ),
            ],
          ),
          if (_checkpoints.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._checkpoints.asMap().entries.map((e) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, size: 18),
                title: Text(e.value, style: const TextStyle(fontSize: 13)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _checkpoints.removeAt(e.key)),
                ),
              );
            }),
          ],
          const SizedBox(height: 24),

          // Saqlash tugmasi
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _saveTask,
              icon: const Icon(Icons.add_task),
              label: const Text('Vazifani Yaratish va Biriktirish', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 2: PROFIL & SOZLAMALAR (CORE PROFILE & SETTINGS)
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

  @override
  Widget build(BuildContext context) {
    final plugins = widget.pluginManager.getAllPlugins();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profil Kartasi
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.indigo.shade100,
                    child: Text(
                      _profile.name[0],
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _profile.name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_profile.role.name.toUpperCase()} • ${_profile.department}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_profile.phone}  |  ${_profile.email}',
                          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Foydalanuvchini Almashtirish (RBAC)
          const Text(
            'Foydalanuvchi va Rolni Tanlash (RBAC)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Column(
            children: UserProfile.defaultProfiles.map((p) {
              final isCurrent = p.id == _profile.id;
              return Card(
                elevation: 0,
                color: isCurrent ? Colors.indigo.shade50 : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isCurrent ? Colors.indigo.shade300 : Colors.grey.shade200,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    p.role == UserRole.director ? Icons.shield : Icons.person,
                    color: isCurrent ? Colors.indigo : Colors.grey,
                  ),
                  title: Text(p.name, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text('${p.role.name} • ${p.department}'),
                  trailing: isCurrent
                      ? const Icon(Icons.check_circle, color: Colors.indigo)
                      : const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                  onTap: () {
                    widget.onProfileChanged(p);
                    setState(() {});
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Tizim & Server Holati
          const Text(
            'Tizim va Microservice Holati',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: const Column(
              children: [
                ListTile(
                  dense: true,
                  leading: Icon(Icons.dns, color: Colors.green),
                  title: Text('KPI Microservice Server'),
                  subtitle: Text('Port: 8081  |  Holati: Faol (Online)'),
                ),
                Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.hub_outlined, color: Colors.blue),
                  title: Text('Moliya & CRM Integratsiyasi'),
                  subtitle: Text('Portlar: :8082 (CRM), :8083 (Moliya)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Plaginlar Markazi (Microkernel Plugin Registry)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Plaginlar Markazi (Microkernel Engine)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${plugins.where((p) => p.isEnabled).length} ta faol',
                  style: TextStyle(color: Colors.purple.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: plugins.map((plugin) {
                final isConfigurable = plugin.id == 'plugin_uzbek_ai' || plugin.id == 'plugin_ecosystem_bridge';
                return SwitchListTile(
                  dense: true,
                  secondary: Icon(
                    plugin.id == 'plugin_uzbek_ai'
                        ? Icons.auto_awesome
                        : (plugin.id == 'plugin_ecosystem_bridge' ? Icons.sync_alt : Icons.extension_outlined),
                    color: Colors.purple,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(plugin.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      if (isConfigurable)
                        InkWell(
                          onTap: () => _showPluginConfigDialog(context, plugin),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tune, size: 11, color: Colors.purple),
                                SizedBox(width: 3),
                                Text('Sozlash', style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(plugin.description, style: const TextStyle(fontSize: 11)),
                  value: plugin.isEnabled,
                  onChanged: (val) async {
                    await widget.pluginManager.togglePlugin(plugin.id, val);
                    setState(() {});
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

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
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.purple, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'O\'zbekcha AI Ekosistema Assistent',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Tabiiy tilda vazifa buyuring (10% bonus va xavfsizlik chegarasi)',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tezkor namunalar
            const Text('Tezkor namunalar:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  label: const Text('Ali: 10% oylik bonusi', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _controller.text = "Ali ga saytni bitirish vazifasini topshir va bitirsa oyligiga 10% qo'sh";
                    _analyze();
                  },
                ),
                ActionChip(
                  label: const Text('Sardor: 300 000 bonus', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _controller.text = "Sardorga mijozlar hisobotini tayyorlashni buyur, bonusi 300000";
                    _analyze();
                  },
                ),
                ActionChip(
                  label: const Text('Vali: 50% qo\'sh (Chegara testi)', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _controller.text = "Valiga yangi modul topshir va 50% qo'sh";
                    _analyze();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Buyruq kiritish maydoni
            TextField(
              controller: _controller,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Masalan: Ali ga saytni bitirish vazifasini topshir va bitirsa oyligiga 10% qo\'sh',
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Tahlil qilish tugmasi
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _analyze,
                icon: _isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.psychology, size: 18),
                label: Text(_isLoading ? 'AI tahlil qilmoqda...' : 'AI Buyrug\'ini Tahlil Qilish'),
                style: FilledButton.styleFrom(backgroundColor: Colors.purple),
              ),
            ),

            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 12))),
                  ],
                ),
              ),
            ],

            // Tahlil natijasi
            if (_result != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: Colors.purple.shade50.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.purple.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified, color: Colors.green, size: 18),
                          const SizedBox(width: 6),
                          const Text('AI Tahlil Natijasi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Tayyor', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Text('• Vazifa: ${_result!['name']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('• Biriktirildi: ${_result!['assigned_to']}', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '• Hisoblangan bonus: ${(_result!['bonus_amount'] as num).toInt()} so\'m ${_result!['is_percent'] ? "(${_result!['percent_value']}% oylikdan)" : ""}',
                        style: const TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('• Muddat: ${_result!['deadline']}', style: const TextStyle(fontSize: 12)),

                      if (_result!['is_capped'] == true) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade600),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber, color: Colors.amber, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${_result!['warning']}',
                                  style: TextStyle(fontSize: 11, color: Colors.brown.shade900, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: _confirmAndCreate,
                          icon: const Icon(Icons.add_task, size: 16),
                          label: const Text('Tasdiqlash va Vazifani Saqlash', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
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

