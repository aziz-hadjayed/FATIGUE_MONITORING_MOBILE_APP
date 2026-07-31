// lib/providers/employee_provider.dart
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/work_session.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../utils/constants.dart';

class DiracData {
  final List<WorkSession> rawSessions;
  final List<DiracPic> pics;
  final DiracStep currentStep;
  final DateTime startTime;
  final DateTime endTime;

  DiracData({
    required this.rawSessions,
    required this.pics,
    required this.currentStep,
    required this.startTime,
    required this.endTime,
  });
}

class EmployeeProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final WebSocketService _webSocket = WebSocketService();
  bool get isLive => _webSocket.isConnected;

  /// Clé de navigation globale à fournir depuis main.dart :
  /// EmployeeProvider(navigatorKey: navigatorKey)
  final GlobalKey<NavigatorState> _navigatorKey;

  String? _currentEmployeeId;

  List<Employee> _allEmployees = [];
  List<Employee> _filteredEmployees = [];
  Employee? _selectedEmployee;
  DiracData? _diracData;
  bool _isLoading = false;
  String? _error;
  DiracStep _currentStep = DiracStep.step30min;

  EmployeeProvider({GlobalKey<NavigatorState>? navigatorKey})
    : _navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>();

  // Getters
  List<Employee> get employees => _filteredEmployees;
  Employee? get selectedEmployee => _selectedEmployee;
  DiracData? get diracData => _diracData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DiracStep get currentStep => _currentStep;

  // ============================================================
  // EMPLOYÉS (HTTP)
  // ============================================================

  Future<void> loadEmployees() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _allEmployees = await _apiService.fetchEmployees();
      _filteredEmployees = _allEmployees;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addEmployee(
    String id,
    String firstName,
    String lastName,
    String role,
  ) async {
    _isLoading = true;
    notifyListeners();

    try {
      final newEmployee = await _apiService.addEmployee(
        id,
        firstName,
        lastName,
        role,
      );
      _allEmployees.add(newEmployee);
      _filteredEmployees = _allEmployees;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void search(String query) {
    if (query.isEmpty) {
      _filteredEmployees = _allEmployees;
    } else {
      _filteredEmployees = _allEmployees
          .where(
            (e) =>
                e.fullName.toLowerCase().contains(query.toLowerCase()) ||
                e.role.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    }
    notifyListeners();
  }

  Future<bool> deleteEmployee(String id) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _apiService.deleteEmployee(id);
      _allEmployees.removeWhere((e) => e.id == id);
      _filteredEmployees = _allEmployees;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ============================================================
  // HISTORIQUE + TEMPS RÉEL (WebSocket)
  // ============================================================

  Future<void> loadEmployeeDetail(String employeeId) async {
    _isLoading = true;
    _error = null;
    _currentEmployeeId = employeeId;
    notifyListeners();

    try {
      _selectedEmployee = _allEmployees.firstWhere(
        (e) => e.id.toString() == employeeId,
      );

      _webSocket.removeListener(_onWebSocketData);
      _webSocket.removeStatusListener(_onWebSocketStatusChanged);
      await _webSocket.disconnect();
      _webSocket.addListener(_onWebSocketData);
      _webSocket.addStatusListener(_onWebSocketStatusChanged);
      await _webSocket.connect(employeeId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  void _onWebSocketData(List<WorkSession> sessions) {
    _buildDiracData(sessions);
    if (sessions.isNotEmpty) {
      final last = sessions.last;
      print(
        '[Provider] Dernière session: State=${last.state} | Vision=${last.confidenceVision}',
      );
    }
  }

  void _onWebSocketStatusChanged() {
    notifyListeners();
  }

  // ─── Commande pour historique par date ──────────────────────────
  void requestHistoryByDate(String date) {
    _webSocket.requestHistoryByDate(date);
  }

  // ============================================================
  // TRAITEMENT DES DONNÉES
  // ============================================================

  void _buildDiracData(List<WorkSession> sessions) {
    final now = DateTime.now();
    final startTime = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endTime = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final filteredSessions = sessions.where((s) {
      return s.timestamp.isAfter(
            startTime.subtract(const Duration(seconds: 1)),
          ) &&
          s.timestamp.isBefore(endTime.add(const Duration(seconds: 1)));
    }).toList();

    final pics = _aggregateByStep(
      filteredSessions,
      _currentStep,
      startTime,
      endTime,
    );

    _diracData = DiracData(
      rawSessions: filteredSessions,
      pics: pics,
      currentStep: _currentStep,
      startTime: startTime,
      endTime: endTime,
    );

    notifyListeners();
  }

  DateTime _clampDateTime(DateTime value, DateTime start, DateTime end) {
    if (value.isBefore(start)) return start;
    if (value.isAfter(end)) return end;
    return value;
  }

  List<DiracPic> _aggregateByStep(
    List<WorkSession> sessions,
    DiracStep step,
    DateTime startTime,
    DateTime endTime,
  ) {
    if (sessions.isEmpty) return [];

    final Map<int, List<WorkSession>> groups = {};
    final totalDuration = endTime.difference(startTime);
    final stepDuration = step.duration;
    final numberOfPics =
        (totalDuration.inMilliseconds / stepDuration.inMilliseconds).ceil();

    for (final session in sessions) {
      final offset = session.timestamp.difference(startTime);
      final groupIndex = (offset.inMilliseconds / stepDuration.inMilliseconds)
          .floor();
      groups.putIfAbsent(groupIndex, () => []).add(session);
    }

    final List<DiracPic> pics = [];

    for (int i = 0; i < numberOfPics; i++) {
      final intervalStart = startTime.add(
        Duration(milliseconds: i * stepDuration.inMilliseconds),
      );
      final intervalEnd = intervalStart.add(stepDuration);

      if (intervalStart.isAfter(endTime)) break;

      final clampedEnd = _clampDateTime(intervalEnd, startTime, endTime);
      final groupSessions = groups[i] ?? [];

      if (groupSessions.isEmpty) {
        pics.add(
          DiracPic(
            startTime: intervalStart,
            endTime: clampedEnd,
            dominantState: WorkState.empty,
            intensity: WorkState.empty.height,
            count: 0,
            fatigueConfirmedCount: 0,
          ),
        );
      } else {
        final Map<WorkState, int> stateCount = {};
        int fatigueConfirmedCount = 0;

        for (final session in groupSessions) {
          stateCount[session.state] = (stateCount[session.state] ?? 0) + 1;

          // COMPTER LES FATIGUES CONFIRMÉES PAR VISION
          if (session.state == WorkState.fatigue &&
              session.confidenceVision == 1.0) {
            fatigueConfirmedCount++;
          }
        }

        WorkState dominantState = WorkState.baseline;
        int maxCount = 0;

        for (final entry in stateCount.entries) {
          if (entry.value > maxCount) {
            maxCount = entry.value;
            dominantState = entry.key;
          }
        }

        if (stateCount.values.where((c) => c == maxCount).length > 1) {
          int maxValue = -1;
          for (final entry in stateCount.entries) {
            if (entry.value == maxCount && entry.key.value > maxValue) {
              maxValue = entry.key.value;
              dominantState = entry.key;
            }
          }
        }

        pics.add(
          DiracPic(
            startTime: intervalStart,
            endTime: clampedEnd,
            dominantState: dominantState,
            intensity: dominantState.height,
            count: maxCount,
            fatigueConfirmedCount: fatigueConfirmedCount,
          ),
        );
      }
    }

    return pics;
  }

  void setStep(DiracStep newStep) {
    if (_currentStep == newStep) return;
    _currentStep = newStep;

    if (_diracData != null) {
      final newPics = _aggregateByStep(
        _diracData!.rawSessions,
        newStep,
        _diracData!.startTime,
        _diracData!.endTime,
      );

      _diracData = DiracData(
        rawSessions: _diracData!.rawSessions,
        pics: newPics,
        currentStep: newStep,
        startTime: _diracData!.startTime,
        endTime: _diracData!.endTime,
      );
      notifyListeners();
    }
  }

  // ============================================================
  // NOUVEAUX GETTERS POUR LA VISION
  // ============================================================

  // Statistiques de confirmation par vision
  Map<String, dynamic> getVisionStats() {
    if (_diracData == null) return {};

    final sessions = _diracData!.rawSessions;
    final fatigueSessions = sessions
        .where((s) => s.state == WorkState.fatigue)
        .toList();
    final confirmed = fatigueSessions
        .where((s) => s.confidenceVision == 1.0)
        .length;
    final infirmed = fatigueSessions
        .where((s) => s.confidenceVision == 0.0)
        .length;
    final total = fatigueSessions.length;

    return {
      'total_fatigue': total,
      'confirmed_by_vision': confirmed,
      'infirmed_by_vision': infirmed,
      'confirmation_rate': total == 0 ? 0 : (confirmed / total * 100).round(),
    };
  }

  // Récupérer les sessions de fatigue confirmées
  List<WorkSession> getConfirmedFatigueSessions() {
    if (_diracData == null) return [];
    return _diracData!.rawSessions
        .where((s) => s.state == WorkState.fatigue && s.confidenceVision == 1.0)
        .toList();
  }

  // Récupérer les sessions de fatigue infirmées
  List<WorkSession> getInfirmedFatigueSessions() {
    if (_diracData == null) return [];
    return _diracData!.rawSessions
        .where((s) => s.state == WorkState.fatigue && s.confidenceVision == 0.0)
        .toList();
  }

  // Vérifier si la dernière fatigue est confirmée
  bool isLastFatigueConfirmed() {
    if (_diracData == null || _diracData!.rawSessions.isEmpty) return false;

    for (var i = _diracData!.rawSessions.length - 1; i >= 0; i--) {
      final session = _diracData!.rawSessions[i];
      if (session.state == WorkState.fatigue) {
        return session.confidenceVision == 1.0;
      }
    }
    return false;
  }

  // ============================================================
  // NETTOYAGE
  // ============================================================

  Future<void> disconnectWebSocket() async {
    _webSocket.removeListener(_onWebSocketData);
    _webSocket.removeStatusListener(_onWebSocketStatusChanged);
    await _webSocket.disconnect();
  }

  Future<void> clearSelection() async {
    await disconnectWebSocket();
    _selectedEmployee = null;
    _diracData = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _webSocket.removeListener(_onWebSocketData);
    _webSocket.removeStatusListener(_onWebSocketStatusChanged);
    _webSocket.disconnect();
    super.dispose();
  }
}
