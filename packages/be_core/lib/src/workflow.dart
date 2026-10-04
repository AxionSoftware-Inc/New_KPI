import 'protocol.dart';
import 'store.dart';
import 'uzbek_nlp.dart';

/// Yuqori qatlam: Ekotizimlararo kompozit ssenariylar va biznes workflowlar (L2 Layer)
class WorkflowEngine {
  WorkflowEngine({
    this.kpiStore,
    this.crmStore,
    this.financeStore,
  });

  final StandardStore? kpiStore;
  final StandardStore? crmStore;
  final StandardStore? financeStore;

  /// 1. Savdo bitimi muvaffaqiyatli yakunlanishi va kassaga pul kirimi (CRM + Finance + KPI)
  Future<ToolResult> dealWonWithPayment({
    required String client,
    required num amount,
    String category = 'savdo',
    String? note,
    String? employee,
  }) async {
    final clientName = client.trim();
    if (clientName.isEmpty) return ToolResult.err(error: "Mijoz ismi ko'rsatilmadi.");
    if (amount <= 0) return ToolResult.err(error: "Summa 0 dan katta bo'lishi kerak.");

    // 1. CRM da mijozni won qilish
    Entity? crmEntity;
    if (crmStore != null) {
      final existing = crmStore!.find(clientName);
      if (existing != null) {
        crmEntity = crmStore!.update(existing.id, status: 'won');
      } else {
        crmEntity = crmStore!.insert(
          name: clientName,
          status: 'won',
          meta: {'notes': ['Savdo yakunlandi ($amount so\'m)'], if (note != null) 'last_note': note},
        );
      }
    }

    // 2. Kassaga kirim qilish
    Entity? finEntity;
    if (financeStore != null) {
      finEntity = financeStore!.insert(
        name: 'Kirim: $clientName',
        status: 'income',
        meta: {
          'amount': amount,
          'from': clientName,
          'category': category,
          'note': note ?? 'Bitim yopildi',
        },
      );
    }

    // 3. Xodim KPI sini oshirish (agar ko'rsatilgan bo'lsa)
    Entity? kpiEntity;
    if (kpiStore != null && employee != null && employee.trim().isNotEmpty) {
      final kpiTarget = kpiStore!.find(employee);
      if (kpiTarget != null) {
        final currentActual = UzbekNlp.parseNumber(kpiTarget.meta['actual']);
        final newActual = currentActual + (kpiTarget.meta['unit'] == 'so\'m' ? amount : 1);
        final target = UzbekNlp.parseNumber(kpiTarget.meta['target'] ?? 1);
        final pct = target > 0 ? ((newActual / target) * 100).round() : 0;
        kpiEntity = kpiStore!.update(
          kpiTarget.id,
          status: pct >= 100 ? 'done' : kpiTarget.status,
          metaPatch: {'actual': newActual, 'pct': pct},
        );
      }
    }

    final message = "'$clientName' bilan bitim muvaffaqiyatli yakunlandi. "
        "Kassaga ${amount.toString()} so'm kirim qilindi"
        "${kpiEntity != null ? ' hamda $employee ning rejasi yangilandi' : ''}.";

    return ToolResult.ok(
      action: 'workflow_deal_won',
      data: {
        'crm': crmEntity?.toJson(),
        'finance': finEntity?.toJson(),
        'kpi': kpiEntity?.toJson(),
      },
      message: message,
    );
  }

  /// 2. Qarzni naqd pulda qaytarish va kassa kirimini bir vaqtda qayd qilish
  Future<ToolResult> debtSettleWithCash({
    required String person,
    num? amount,
  }) async {
    if (financeStore == null) return ToolResult.err(error: "Moliya ombori ulanmagan.");

    final personName = person.trim();
    final activeDebt = financeStore!.filter(
      status: 'debt_active',
      predicate: (e) {
        final match = UzbekNlp.matchEntity(personName, [e.name, '${e.meta['person']}']);
        return match != null;
      },
    ).firstOrNull ?? financeStore!.find(personName);

    if (activeDebt == null) {
      return ToolResult.err(error: "'$personName' bo'yicha faol qarz topilmadi.");
    }

    final total = UzbekNlp.parseNumber(activeDebt.meta['amount']);
    final currentPaid = UzbekNlp.parseNumber(activeDebt.meta['paid'] ?? 0);
    final remaining = total - currentPaid;
    final paidDelta = (amount != null && amount > 0) ? amount : remaining;

    final newPaid = currentPaid + paidDelta;
    final newRemaining = total - newPaid;
    final isFullyPaid = newRemaining <= 0;

    // Qarz holatini yangilash
    final updatedDebt = financeStore!.update(
      activeDebt.id,
      status: isFullyPaid ? 'debt_closed' : 'debt_active',
      metaPatch: {
        'paid': newPaid,
        'remaining': isFullyPaid ? 0 : newRemaining,
      },
    );

    // Kassaga haqiqiy kirim qo'shish
    final incomeRecord = financeStore!.insert(
      name: 'Qarz qaytarildi: ${activeDebt.meta['person'] ?? personName}',
      status: 'income',
      meta: {
        'amount': paidDelta,
        'from': activeDebt.meta['person'] ?? personName,
        'category': 'qarz_qaytarish',
      },
    );

    final msg = isFullyPaid
        ? "${activeDebt.meta['person'] ?? personName} ning qarzi TO'LIQ yopildi va kassaga $paidDelta so'm kirdi."
        : "${activeDebt.meta['person'] ?? personName} $paidDelta so'm to'ladi (Qoldiq: $newRemaining so'm).";

    return ToolResult.ok(
      action: 'workflow_debt_settle',
      data: {
        'debt': updatedDebt.toJson(),
        'income': incomeRecord.toJson(),
      },
      message: msg,
    );
  }

  /// 3. Kassadan naqd pul berib qarz yozish (Chiqim + Nasiya)
  Future<ToolResult> lendCash({
    required String person,
    required num amount,
    String? dueDate,
  }) async {
    if (financeStore == null) return ToolResult.err(error: "Moliya ombori ulanmagan.");
    if (amount <= 0) return ToolResult.err(error: "Summa 0 dan katta bo'lishi kerak.");

    final personName = person.trim();

    // 1. Qarz ro'yxatiga olish
    final meta = <String, dynamic>{
      'person': personName,
      'amount': amount,
      'type': 'receivable',
      'paid': 0,
      'remaining': amount,
    };
    if (dueDate != null) meta['due_date'] = UzbekNlp.parseDate(dueDate);

    final debtRecord = financeStore!.insert(
      name: 'Qarz: $personName',
      status: 'debt_active',
      meta: meta,
    );

    // 2. Kassadan chiqim qilish
    final expenseRecord = financeStore!.insert(
      name: 'Qarz berildi: $personName',
      status: 'expense',
      meta: {
        'amount': amount,
        'to': personName,
        'category': 'qarz_berish',
      },
    );

    return ToolResult.ok(
      action: 'workflow_lend_cash',
      data: {
        'debt': debtRecord.toJson(),
        'expense': expenseRecord.toJson(),
      },
      message: "$personName ga $amount so'm qarz berildi va kassadan chiqim qilindi.",
    );
  }

  /// 4. Yagona boshqaruv hisoboti (Executive Master Summary: Finance + CRM + KPI)
  Future<ToolResult> executiveReport() async {
    // 1. Moliya
    num totalIncome = 0;
    num totalExpense = 0;
    num totalReceivables = 0;
    if (financeStore != null) {
      totalIncome = financeStore!.filter(status: 'income').fold<num>(0, (s, e) => s + UzbekNlp.parseNumber(e.meta['amount']));
      totalExpense = financeStore!.filter(status: 'expense').fold<num>(0, (s, e) => s + UzbekNlp.parseNumber(e.meta['amount']));
      totalReceivables = financeStore!.filter(status: 'debt_active', predicate: (e) => e.meta['type'] == 'receivable').fold<num>(0, (s, e) => s + UzbekNlp.parseNumber(e.meta['remaining']));
    }

    // 2. CRM
    var totalClients = 0;
    var wonDeals = 0;
    var meetingsCount = 0;
    if (crmStore != null) {
      totalClients = crmStore!.filter(predicate: (e) => e.status != 'meeting' && e.status != 'reminder').length;
      wonDeals = crmStore!.filter(status: 'won').length;
      meetingsCount = crmStore!.filter(status: 'meeting').length;
    }

    // 3. KPI
    var avgKpi = 0;
    var totalTasks = 0;
    if (kpiStore != null) {
      final all = kpiStore!.all;
      totalTasks = all.length;
      if (all.isNotEmpty) {
        final sum = all.fold<num>(0, (s, e) => s + UzbekNlp.parseNumber(e.meta['pct']));
        avgKpi = (sum / all.length).round();
      }
    }

    final netProfit = totalIncome - totalExpense;
    final summaryMessage =
        "📊 BIZNES XULOSASI:\n"
        "• Kassa: Kirim: $totalIncome so'm | Chiqim: $totalExpense so'm | Sof foyda: $netProfit so'm\n"
        "• Tashqi qarzlar: $totalReceivables so'm\n"
        "• CRM: Jami mijoz: $totalClients ta | Yutilgan bitim: $wonDeals ta | Rejalashtirilgan uchrashuv: $meetingsCount ta\n"
        "• KPI: Rejalar o'rtacha $avgKpi% ga bajarildi ($totalTasks ta vazifa).";

    return ToolResult.ok(
      action: 'workflow_executive_report',
      data: {
        'finance': {
          'income': totalIncome,
          'expense': totalExpense,
          'profit': netProfit,
          'receivables': totalReceivables,
        },
        'crm': {
          'clients': totalClients,
          'won': wonDeals,
          'meetings': meetingsCount,
        },
        'kpi': {
          'avg_pct': avgKpi,
          'total_tasks': totalTasks,
        },
      },
      message: summaryMessage,
    );
  }

  /// 4. Xodimga vazifa va bonus biriktirish (Chegara va xavfsizlik nazorati bilan)
  Future<ToolResult> assignTaskWithBonus({
    required String employee,
    required String taskName,
    num bonusPercent = 0,
    num fixedBonus = 0,
    num baseSalary = 5000000,
    num maxAllowedBonus = 2000000,
    String? deadline,
  }) async {
    if (kpiStore == null) return ToolResult.err(error: "KPI ombori ulanmagan.");

    final emp = employee.trim();
    if (emp.isEmpty) return ToolResult.err(error: "Xodim ismi kiritilmadi.");

    num calculatedBonus = 0;
    if (bonusPercent > 0) {
      calculatedBonus = (baseSalary * (bonusPercent / 100)).round();
    } else if (fixedBonus > 0) {
      calculatedBonus = fixedBonus;
    }

    // Xavfsizlik chegarasi (Limit)
    bool isCapped = false;
    if (calculatedBonus > maxAllowedBonus) {
      calculatedBonus = maxAllowedBonus;
      isCapped = true;
    }

    final entity = kpiStore!.insert(
      name: '$emp: $taskName',
      status: 'active',
      meta: {
        'employee': emp,
        'task_name': taskName,
        'target': 100,
        'actual': 0,
        'unit': '%',
        'pct': 0,
        'priority': 'normal',
        'bonus_percent': bonusPercent,
        'bonus_amount': calculatedBonus,
        'base_salary': baseSalary,
        'bonus_limit': maxAllowedBonus,
        'bonus_paid': false,
        'is_capped': isCapped,
        if (deadline != null) 'deadline': deadline,
      },
    );

    final capMsg = isCapped ? " (Chegara bo'yicha maks. $maxAllowedBonus so'm belgilandi)" : "";
    final message = "$emp ga '$taskName' vazifasi biriktirildi. "
        "Bonus: ${calculatedBonus > 0 ? '$calculatedBonus so\'m$capMsg' : 'Belgilanmadi'}. "
        "Vazifa tugatilganda moliyadan avtomatik chiqim qilinadi.";

    return ToolResult.ok(
      action: 'workflow_assign_task_bonus',
      data: entity.toJson(),
      message: message,
    );
  }

  /// 5. Vazifa yakunlanganda xodim bonusini moliyadan avtomatik chiqim qilish
  Future<ToolResult> completeTaskWithBonus({
    required Object targetKey,
    num maxAllowedBonus = 2000000,
    String? note,
  }) async {
    if (kpiStore == null) return ToolResult.err(error: "KPI ombori ulanmagan.");

    final task = kpiStore!.find(targetKey);
    if (task == null) return ToolResult.err(error: "'$targetKey' vazifasi topilmadi.");

    final bonusAmount = UzbekNlp.parseNumber(task.meta['bonus_amount']);
    final isAlreadyPaid = task.meta['bonus_paid'] == true;
    final emp = task.meta['employee'] ?? task.name;

    // 1. KPI vazifasini done qilish
    final updatedTask = kpiStore!.update(
      task.id,
      status: 'done',
      metaPatch: {
        'actual': task.meta['target'] ?? 100,
        'pct': 100,
        'bonus_paid': isAlreadyPaid ? true : (bonusAmount > 0),
        'paid_at': DateTime.now().toIso8601String(),
      },
    );

    Entity? finEntity;
    String finMessage = '';

    // 2. Agar bonus bo'lsa va to'lanmagan bo'lsa, moliyadan yechish
    if (bonusAmount > 0 && !isAlreadyPaid && financeStore != null) {
      // Chegara tekshiruvi
      final finalBonus = bonusAmount > maxAllowedBonus ? maxAllowedBonus : bonusAmount;
      finEntity = financeStore!.insert(
        name: 'Bonus: $emp',
        status: 'expense',
        meta: {
          'amount': finalBonus,
          'to': emp,
          'category': 'Oylik/Bonus',
          'task_id': task.id,
          'note': note ?? "Vazifa yakunlandi: ${task.name}",
        },
      );
      finMessage = " Moliyadan $emp ga $finalBonus so'm bonus chiqim qilindi.";
    }

    final message = "'${updatedTask.name}' vazifasi to'liq bajarildi.$finMessage";

    return ToolResult.ok(
      action: 'workflow_task_done_bonus',
      data: {
        'kpi': updatedTask.toJson(),
        'finance': finEntity?.toJson(),
      },
      message: message,
    );
  }
}
