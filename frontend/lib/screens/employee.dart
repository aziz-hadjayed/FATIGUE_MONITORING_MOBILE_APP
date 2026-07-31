// screens/employee.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import '../providers/employee_provider.dart';
import 'package:go_router/go_router.dart';
import '../models/work_session.dart';
import '../utils/constants.dart';

class EmployeeScreen extends StatefulWidget {
  final String? employeeId;

  const EmployeeScreen({super.key, this.employeeId});

  @override
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen> {
  bool _isZoomMenuOpen = false;
  final FatigueMonitor _fatigueMonitor = FatigueMonitor();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.employeeId ?? '';
      if (id.isNotEmpty) {
        context.read<EmployeeProvider>().loadEmployeeDetail(id);
      }
    });
  }

  Future<void> _initializeNotifications() async {
    await NotificationManager.initialize();

    // Demander la permission pour les notifications
    final status = await Permission.notification.request();
    print('Permission notification: $status');

    final enabled = await NotificationManager.requestPermissions();
    print('Notifications plugin autorisées: $enabled');

    if (status.isPermanentlyDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Active les notifications dans les paramètres.'),
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<EmployeeProvider>();

    // Démarrer ou arrêter la surveillance selon l'état
    if (provider.isLive && provider.diracData != null) {
      _fatigueMonitor.startMonitoring(provider);
    } else {
      _fatigueMonitor.stopMonitoring();
    }
  }

  @override
  void dispose() {
    _fatigueMonitor.stopMonitoring();
    print('EmployeeScreen.dispose()');
    context.read<EmployeeProvider>().clearSelection();
    super.dispose();
    print('EmployeeScreen.dispose() terminé');
  }

  double _getChartWidth(int picCount) {
    final minWidth = (picCount * 30.0) + 40.0;
    final screenWidth = MediaQuery.of(context).size.width;
    return minWidth > screenWidth ? minWidth : screenWidth;
  }

  IconData _getRoleIcon(String? role) {
    if (role == null) return Icons.person;
    final r = role.toLowerCase();
    if (r.contains('developer') || r.contains('engineer')) return Icons.code;
    if (r.contains('manager')) return Icons.manage_accounts;
    if (r.contains('designer')) return Icons.design_services;
    if (r.contains('analyst') || r.contains('data')) return Icons.analytics;
    if (r.contains('devops')) return Icons.cloud_circle;
    return Icons.person;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmployeeProvider>();
    final diracData = provider.diracData;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.turquoise,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.darkBlue),
          onPressed: () => context.go('/home'),
        ),
        title: const Text(
          'Employee Profile',
          style: TextStyle(
            color: AppColors.darkBlue,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: provider.isLive ? AppColors.green : AppColors.red,
                    shape: BoxShape.circle,
                    boxShadow: provider.isLive
                        ? [
                            BoxShadow(
                              color: AppColors.green.withOpacity(0.4),
                              blurRadius: 6,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  provider.isLive ? 'Live' : 'Offline',
                  style: TextStyle(
                    color: AppColors.darkBlue,
                    fontSize: 12,
                    fontWeight: provider.isLive ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: AppColors.turquoise,
                          child: Icon(
                            _getRoleIcon(null),
                            color: AppColors.darkBlue,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Bracelet #${provider.selectedEmployee?.id ?? ''}',
                          style: const TextStyle(
                            color: AppColors.darkBlue,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _ZoomControls(
                          provider: provider,
                          isOpen: _isZoomMenuOpen,
                          onToggle: () => setState(
                            () => _isZoomMenuOpen = !_isZoomMenuOpen,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Courbe Energétique (${provider.currentStep.label})",
                              style: TextStyle(
                                color: AppColors.darkBlue.withOpacity(0.6),
                                fontSize: 14,
                              ),
                            ),
                            if (diracData != null)
                              Text(
                                '${diracData.pics.length} pics',
                                style: TextStyle(
                                  color: AppColors.darkBlue.withOpacity(0.4),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 250,
                          child: diracData != null && diracData.pics.isNotEmpty
                              ? SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: _getChartWidth(
                                      diracData.pics.length,
                                    ),
                                    height: 250,
                                    child: _DiracComb(diracData: diracData),
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.lightGray,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.turquoise,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          provider.isLive
                                              ? 'En attente des données...'
                                              : 'Connexion WebSocket...',
                                          style: TextStyle(
                                            color: AppColors.darkBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 24),
                        const _StateLegend(),
                        const SizedBox(height: 16),
                        if (diracData != null) _LiveStats(diracData: diracData),
                        const SizedBox(height: 16),
                        if (diracData != null)
                          _RendementCard(diracData: diracData),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
// ... (le reste des widgets _ZoomControls, _DiracComb, _StateLegend, _LiveStats, _StatItem ....)

// ─── Zoom Controls (inchangé visuellement) ──────────────────────────
class _ZoomControls extends StatelessWidget {
  final EmployeeProvider provider;
  final bool isOpen;
  final VoidCallback onToggle;

  const _ZoomControls({
    required this.provider,
    required this.isOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final fast = [DiracStep.step30sec];
    final medium = [
      DiracStep.step1min,
      DiracStep.step5min,
      DiracStep.step10min,
      DiracStep.step15min,
    ];
    final slow = [
      DiracStep.step20min,
      DiracStep.step30min,
      DiracStep.step1hour,
    ];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.lightGray,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ZoomChip(
                label: 'Fast',
                isSelected: fast.contains(provider.currentStep),
                onTap: onToggle,
              ),
              _ZoomChip(
                label: 'Medium',
                isSelected: medium.contains(provider.currentStep),
                onTap: onToggle,
              ),
              _ZoomChip(
                label: 'Slow',
                isSelected: slow.contains(provider.currentStep),
                onTap: onToggle,
              ),
            ],
          ),
        ),
        if (isOpen)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _ZoomStepGrid(
                  steps: fast,
                  provider: provider,
                  title: 'Rapide (secondes)',
                ),
                const Divider(height: 24),
                _ZoomStepGrid(
                  steps: medium,
                  provider: provider,
                  title: 'Moyen (minutes)',
                ),
                const Divider(height: 24),
                _ZoomStepGrid(
                  steps: slow,
                  provider: provider,
                  title: 'Lent (heures)',
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ZoomChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _ZoomChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.turquoise : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? AppColors.darkBlue
                : AppColors.darkBlue.withOpacity(0.5),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ZoomStepGrid extends StatelessWidget {
  final List<DiracStep> steps;
  final EmployeeProvider provider;
  final String title;
  const _ZoomStepGrid({
    required this.steps,
    required this.provider,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.darkBlue.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: steps.map((step) {
            final isSelected = provider.currentStep == step;
            return GestureDetector(
              onTap: () => provider.setStep(step),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.turquoise : AppColors.lightGray,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  step.label,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.darkBlue
                        : AppColors.darkBlue.withOpacity(0.6),
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── DiracComb, StateLegend, LiveStats (inchangés) ─────────────────
class _DiracComb extends StatelessWidget {
  final DiracData diracData;
  const _DiracComb({required this.diracData});

  @override
  Widget build(BuildContext context) {
    final pics = diracData.pics;
    final sw = MediaQuery.of(context).size.width;

    // Largeur dynamique : au moins 30px par pic
    final chartWidth = (pics.length * 30.0 + 40.0).clamp(sw, double.infinity);
    final barW = ((chartWidth - 40) / pics.length * 0.7).clamp(3.0, 16.0);

    return SizedBox(
      width: chartWidth, // Largeur dynamique
      height: 250,
      child: Stack(
        children: [
          // ─── BAR CHART ──────────────────────────────────────────────
          BarChart(
            BarChartData(
              alignment: BarChartAlignment.center,
              maxY: 1.2,
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 0.25,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: AppColors.darkBlue.withOpacity(0.08),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= pics.length) return const SizedBox();
                      if (pics.length > 40 && i % 8 != 0)
                        return const SizedBox();
                      if (pics.length > 20 && i % 4 != 0)
                        return const SizedBox();
                      if (pics.length > 12 && i % 2 != 0)
                        return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Transform.rotate(
                          angle: pics.length > 24 ? -0.4 : 0,
                          child: Text(
                            pics[i].label,
                            style: TextStyle(
                              color: AppColors.darkBlue.withOpacity(0.4),
                              fontSize: 9,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: pics.asMap().entries.map((e) {
                final pic = e.value;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: pic.intensity,
                      color: pic.dominantState.color,
                      width: barW,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: 1.0,
                        color: AppColors.lightGray,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),

          // ─── SIGNE SUR LES PICS DE FATIGUE CONFIRMÉE ──────────
          ...pics
              .asMap()
              .entries
              .where((entry) {
                final pic = entry.value;
                return pic.dominantState == WorkState.fatigue &&
                    pic.fatigueConfirmedCount > 0;
              })
              .map((entry) {
                final index = entry.key;
                final pic = entry.value;

                // Calcul des positions avec la largeur dynamique
                final totalPics = pics.length;
                final barSpacing = (chartWidth - 40) / totalPics;
                final x = 20 + (index * barSpacing) + (barSpacing / 2) - 8;
                final y = 20 + (1.0 - pic.intensity) * 200 - 20;

                return Positioned(
                  left: x,
                  top: y,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 197, 34, 34),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(
                            255,
                            197,
                            34,
                            34,
                          ).withOpacity(0.4),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '✓',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(),
        ],
      ),
    );
  }
}

class _StateLegend extends StatelessWidget {
  const _StateLegend();
  @override
  Widget build(BuildContext context) {
    final states = [
      WorkState.activity,
      WorkState.baseline,
      WorkState.preFatigue,
      WorkState.fatigue,
      WorkState.empty,
    ];
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: states
          .map(
            (s) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  s.label,
                  style: TextStyle(
                    color: AppColors.darkBlue.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _LiveStats extends StatelessWidget {
  final DiracData diracData;
  const _LiveStats({required this.diracData});

  @override
  Widget build(BuildContext context) {
    final total = diracData.pics.length;
    final active = diracData.pics
        .where((p) => p.dominantState == WorkState.activity)
        .length;
    final fatigue = diracData.pics
        .where((p) => p.dominantState == WorkState.fatigue)
        .length;
    final pre = diracData.pics
        .where((p) => p.dominantState == WorkState.preFatigue)
        .length;
    final base = diracData.pics
        .where((p) => p.dominantState == WorkState.baseline)
        .length;
    final empty = diracData.pics
        .where((p) => p.dominantState == WorkState.empty)
        .length;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ' Statistiques temps réel',
            style: TextStyle(
              color: AppColors.darkBlue,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(
                label: 'Actif',
                value: '$active',
                total: total,
                color: WorkState.activity.color,
              ),
              _StatItem(
                label: 'Pré-fatigue',
                value: '$pre',
                total: total,
                color: WorkState.preFatigue.color,
              ),
              _StatItem(
                label: 'Fatigue',
                value: '$fatigue',
                total: total,
                color: WorkState.fatigue.color,
              ),
              _StatItem(
                label: 'Repos',
                value: '$base',
                total: total,
                color: WorkState.baseline.color,
              ),
              _StatItem(
                label: 'Vide',
                value: '$empty',
                total: total,
                color: WorkState.empty.color,
              ),
            ],
          ),
          const SizedBox(height: 35),
        ],
      ),
    );
  }
}

class _RendementCard extends StatelessWidget {
  final DiracData diracData;
  const _RendementCard({required this.diracData});

  @override
  Widget build(BuildContext context) {
    final pics = diracData.pics;
    if (pics.isEmpty) return const SizedBox();

    const matinDebut = 7 * 60, matinFin = 12 * 60;
    const apremDebut = 14 * 60, apremFin = 17 * 60;

    final productifs = pics.where((pic) {
      final minutes = pic.startTime.hour * 60 + pic.startTime.minute;
      final dansCreneau =
          (minutes >= matinDebut && minutes < matinFin) ||
          (minutes >= apremDebut && minutes < apremFin);
      final bonEtat =
          pic.dominantState == WorkState.activity ||
          pic.dominantState == WorkState.preFatigue;
      return dansCreneau && bonEtat;
    }).length;

    final rendement = productifs / pics.length;
    final pourcentage = (rendement * 100).round();

    final Color couleur;
    final String label;
    if (pourcentage >= 80) {
      couleur = Colors.green;
      label = 'Excellent';
    } else if (pourcentage >= 60) {
      couleur = Colors.orange;
      label = 'Bon';
    } else if (pourcentage >= 40) {
      couleur = Colors.amber;
      label = 'Moyen';
    } else {
      couleur = Colors.red;
      label = 'Faible';
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Rendement',
                style: TextStyle(
                  color: AppColors.darkBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$pourcentage% · $label',
                style: TextStyle(
                  color: couleur,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rendement,
              minHeight: 6,
              backgroundColor: AppColors.darkBlue.withOpacity(0.08),
              color: couleur,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _TimeSlotChip(
                label: '07:00–12:00',
                color: WorkState.activity.color,
              ),
              const SizedBox(width: 8),
              _TimeSlotChip(
                label: '14:00–17:00',
                color: WorkState.activity.color,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── TimeSlotChip ──────────────────────────────────────────────────
class _TimeSlotChip extends StatelessWidget {
  final String label;
  final Color color;
  const _TimeSlotChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label, value;
  final int total;
  final Color color;
  const _StatItem({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final intValue = int.tryParse(value) ?? 0;
    final pct = total > 0 ? (intValue / total) * 100 : 0;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: AppColors.darkBlue.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 3,
            width: double.infinity,
            decoration: BoxDecoration(
              color: color.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              widthFactor: pct / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Notification Manager ──────────────────────────────────────────
class NotificationManager {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
  }

  static Future<bool?> requestPermissions() async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    final androidGranted = await android?.requestNotificationsPermission();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    return androidGranted ?? iosGranted;
  }

  static Future<void> showFatigueAlert(
    int fatigueCount,
    int totalPics,
    String employeeName,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'fatigue_channel',
          'Alerte Fatigue',
          channelDescription: 'Notifications d\'alerte de fatigue',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      0,
      '⚠️ Alerte Fatigue Détectée pour $employeeName',
      null,
      details,
    );
  }
}

// ─── Fatigue Monitor ──────────────────────────────────────────────
class FatigueMonitor {
  static const Duration analysisWindow = Duration(minutes: 15);
  static const double threshold = 0.7; // 70%

  Timer? _timer;
  bool _alertSent = false;
  bool _isMonitoring = false;

  void startMonitoring(EmployeeProvider provider) {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _alertSent = false;

    _checkFatigueCondition(provider);
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkFatigueCondition(provider);
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    _isMonitoring = false;
    _alertSent = false;
  }

  void _checkFatigueCondition(EmployeeProvider provider) {
    final currentData = provider.diracData;
    if (currentData == null || currentData.rawSessions.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final windowStart = now.subtract(analysisWindow);
    final recentSessions = currentData.rawSessions
        .where((session) => !session.timestamp.isBefore(windowStart))
        .toList();

    if (recentSessions.isEmpty) return;

    final totalPics = recentSessions.length;
    final fatigueCount = recentSessions
        .where((session) => session.state == WorkState.fatigue)
        .length;

    // Calculer le pourcentage de fatigue
    double fatigueRatio = fatigueCount / totalPics;
    print(
      '🔎 Fatigue monitor: $fatigueCount/$totalPics '
      '(${(fatigueRatio * 100).toStringAsFixed(1)}%)',
    );

    // Si 70% ou plus de fatigue et pas encore d'alerte
    if (fatigueRatio >= threshold && !_alertSent) {
      _alertSent = true;
      final employee = provider.selectedEmployee;
      final employeeName = employee == null || employee.fullName.trim().isEmpty
          ? 'Bracelet #${employee?.id ?? ''}'
          : employee.fullName;
      NotificationManager.showFatigueAlert(
        fatigueCount,
        totalPics,
        employeeName,
      );
    } else if (fatigueRatio < threshold) {
      // Réinitialiser si le ratio redevient normal
      _alertSent = false;
    }
  }

  void reset() {
    _alertSent = false;
  }
}
