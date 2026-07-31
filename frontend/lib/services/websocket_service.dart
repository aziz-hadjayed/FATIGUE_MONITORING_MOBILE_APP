// lib/services/websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/work_session.dart';
import '../utils/constants.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  bool _isConnected = false;
  bool _manualDisconnect = false;
  String? _errorMessage;
  final List<WorkSession> _sessions = [];
  String? _currentEmployeeId;

  final List<void Function(List<WorkSession>)> _listeners = [];
  final List<VoidCallback> _statusListeners = [];

  // Getters
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  List<WorkSession> get sessions => List.unmodifiable(_sessions);

  // ─── Listeners ────────────────────────────────────────────────────
  void addListener(void Function(List<WorkSession>) callback) {
    if (!_listeners.contains(callback)) {
      _listeners.add(callback);
    }
  }

  void removeListener(void Function(List<WorkSession>) callback) {
    _listeners.remove(callback);
  }

  void addStatusListener(VoidCallback callback) {
    if (!_statusListeners.contains(callback)) {
      _statusListeners.add(callback);
    }
  }

  void removeStatusListener(VoidCallback callback) {
    _statusListeners.remove(callback);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener(_sessions);
    }
  }

  void _notifyStatusListeners() {
    for (final listener in _statusListeners) {
      listener();
    }
  }

  // ─── Connexion ────────────────────────────────────────────────────
  Future<void> connect(String employeeId) async {
    if (_isConnected && _currentEmployeeId == employeeId) return;

    if (_isConnected) {
      await disconnect();
    } else if (_channel != null) {
      await _cleanupClosedConnection();
    }

    _manualDisconnect = false;
    _currentEmployeeId = employeeId;
    final shouldRequestHistory = _sessions.isEmpty;
    final wsUrl = '${ApiConstants.wsUrl}/$employeeId';
    if (kDebugMode) print('[WS] Connexion à $wsUrl');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _errorMessage = null;
      _notifyStatusListeners();

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
      _startHeartbeat();

      // Send the command get_history after connection
      Future.delayed(Duration(milliseconds: 500), () {
        if (_isConnected && _currentEmployeeId == employeeId) {
          if (shouldRequestHistory) {
            _sendCommand('get_history');
            print(' Command "get_history" sent');
          } else {
            print(' History already loaded, waiting for real time');
          }
        }
      });

      if (kDebugMode) print(' Connected');
    } catch (e) {
      _setError('Error : $e');
    }
  }

  // ─── Réception des messages ───────────────────────────────────────
  void _onMessage(dynamic message) {
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;

      if (json['type'] == 'history_batch') {
        final items = json['items'] as List<dynamic>? ?? [];
        final batchSessions = items
            .whereType<Map<String, dynamic>>()
            .map(_sessionFromJson)
            .toList();

        _sessions.addAll(batchSessions);
        _trimSessions();
        _notifyListeners();

        if (kDebugMode) {
          print('Batch historique ajouté: ${batchSessions.length}');
        }
        return;
      }

      //  Vérifier si c'est une session unique
      if (json.containsKey('timestamp') && json.containsKey('state')) {
        final session = _sessionFromJson(json);
        _sessions.add(session);
        _trimSessions();

        _notifyListeners();
        if (kDebugMode) {
          print(
            ' Session added: ${session.timestamp} | Vision: ${session.confidenceVision}',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print(' Parse Error $e | Raw: $message');
    }
  }

  WorkSession _sessionFromJson(Map<String, dynamic> json) {
    final confidenceValue = json['confidence_vision'];
    final confidenceVision = confidenceValue is num
        ? confidenceValue.toDouble()
        : double.tryParse(confidenceValue?.toString() ?? '') ?? 0.0;

    return WorkSession(
      timestamp: DateTime.parse(json['timestamp'] as String),
      state: WorkState.fromInt(
        json['state'] is int
            ? json['state']
            : int.parse(json['state'].toString()),
      ),
      confidenceVision: confidenceVision,
    );
  }

  void _trimSessions() {
    if (_sessions.length > 10000) {
      _sessions.removeRange(0, _sessions.length - 5000);
    }
  }

  // ─── Envoi de commandes ──────────────────────────────────────────
  void _sendCommand(String command) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(command);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _sendCommand('ping');
    });
  }

  void _scheduleReconnect() {
    final employeeId = _currentEmployeeId;
    if (_manualDisconnect || employeeId == null) return;
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_manualDisconnect) return;
      if (kDebugMode) print(' Reconnecting...');
      connect(employeeId);
    });
  }

  Future<void> _cleanupClosedConnection() async {
    _heartbeatTimer?.cancel();
    await _subscription?.cancel();
    _channel = null;
    _subscription = null;
    _isConnected = false;
  }

  // ─── Commandes publiques ─────────────────────────────────────────
  void requestHistory() {
    _sendCommand('get_history');
  }

  void requestHistoryByDate(String date) {
    _sendCommand('get_history_range:$date');
  }

  // ─── Déconnexion ──────────────────────────────────────────────────
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    if (_channel != null) {
      try {
        await _channel!.sink.close(1000);
      } catch (e) {
        if (kDebugMode) print(' Error during close: $e');
      }
    }

    await _subscription?.cancel();
    _channel = null;
    _subscription = null;
    _isConnected = false;
    _currentEmployeeId = null;
    _sessions.clear();
    _notifyStatusListeners();
    if (kDebugMode) print(' Disconnected');
  }

  // ─── Gestion erreurs ──────────────────────────────────────────────
  void _onError(Object error) {
    _setError('Stream error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    _heartbeatTimer?.cancel();
    _isConnected = false;
    _channel = null;
    _subscription = null;
    _notifyStatusListeners();
    if (kDebugMode) print(' Connection closed by the server');
    _scheduleReconnect();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _isConnected = false;
    _notifyStatusListeners();
    if (kDebugMode) print(' ERROR $msg');
  }
}
