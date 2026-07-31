// lib/models/work_session.dart
import 'package:flutter/material.dart';

enum WorkState {
  baseline, // 0
  activity, // 1
  preFatigue, // 2
  fatigue, // 3
  empty; // 4

  factory WorkState.fromInt(int value) {
    if (value == 4) return WorkState.empty;
    return WorkState.values[value];
  }

  factory WorkState.fromString(String value) {
    switch (value.toLowerCase()) {
      case 'baseline':
        return WorkState.baseline;
      case 'activity':
        return WorkState.activity;
      case 'prefatigue':
      case 'pre_fatigue':
        return WorkState.preFatigue;
      case 'fatigue':
        return WorkState.fatigue;
      case 'empty':
        return WorkState.empty;
      default:
        return WorkState.baseline;
    }
  }

  Color get color {
    switch (this) {
      case WorkState.empty:
        return const Color(0xFFE2E8F0);
      case WorkState.baseline:
        return const Color(0xFF94A3B8);
      case WorkState.activity:
        return const Color(0xFF22C55E);
      case WorkState.preFatigue:
        return const Color(0xFFF59E0B);
      case WorkState.fatigue:
        return const Color(0xFFEF4444);
    }
  }

  String get label {
    switch (this) {
      case WorkState.empty:
        return 'Vide';
      case WorkState.baseline:
        return 'Repos';
      case WorkState.activity:
        return 'Actif';
      case WorkState.preFatigue:
        return 'Pré-fatigue';
      case WorkState.fatigue:
        return 'Fatigue';
    }
  }

  double get height {
    switch (this) {
      case WorkState.empty:
        return 0.0;
      case WorkState.baseline:
        return 1.0;
      case WorkState.activity:
        return 1.0;
      case WorkState.preFatigue:
        return 0.6;
      case WorkState.fatigue:
        return 0.2;
    }
  }

  int get value {
    switch (this) {
      case WorkState.empty:
        return 4;
      case WorkState.baseline:
        return 0;
      case WorkState.fatigue:
        return 1;
      case WorkState.preFatigue:
        return 2;
      case WorkState.activity:
        return 3;
    }
  }

  static WorkState fromValue(int value) {
    switch (value) {
      case 0:
        return WorkState.baseline;
      case 1:
        return WorkState.fatigue;
      case 2:
        return WorkState.preFatigue;
      case 3:
        return WorkState.activity;
      case 4:
        return WorkState.empty;
      default:
        return WorkState.baseline;
    }
  }
}

class WorkSession {
  final DateTime timestamp;
  final WorkState state;
  final double confidenceVision;

  WorkSession({
    required this.timestamp,
    required this.state,
    this.confidenceVision = 0.0,
  });

  factory WorkSession.fromJson(Map<String, dynamic> json) {
    return WorkSession(
      timestamp: DateTime.parse(json['timestamp']),
      state: WorkState.fromString(json['state']),
      confidenceVision: (json['confidence_vision'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'state': state.toString().split('.').last,
      'confidence_vision': confidenceVision,
    };
  }
}

// ─── Pic du peigne de Dirac ─────────────────────────────────────────
class DiracPic {
  final DateTime startTime;
  final DateTime endTime;
  final WorkState dominantState;
  final double intensity;
  final int count;
  final int fatigueConfirmedCount;

  DiracPic({
    required this.startTime,
    required this.endTime,
    required this.dominantState,
    required this.intensity,
    required this.count,
    this.fatigueConfirmedCount = 0,
  });

  String get label {
    final h = startTime.hour.toString().padLeft(2, '0');
    final m = startTime.minute.toString().padLeft(2, '0');
    final s = startTime.second.toString().padLeft(2, '0');
    if (startTime.second != 0 || startTime.minute != 0) {
      return '$h:$m:$s';
    }
    return '$h:$m';
  }

  Duration get duration => endTime.difference(startTime);
}
