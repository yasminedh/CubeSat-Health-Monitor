// =============================================================================
// telemetry_service.dart
// Riverpod providers + Firebase Firestore integration
//
// Structure Firestore :
//   sessions/{sessionId}/
//     startTime, endTime, packetCount
//     packets/{auto}/  ← chaque paquet HK
//   alerts/{auto}/     ← alertes FDIR + seuils Flutter
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE INSTANCE
// ─────────────────────────────────────────────────────────────────────────────
final _db = FirebaseFirestore.instance;

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class TelemetryPacket {
  final DateTime timestamp;
  final double   temp;
  final int      pressure;
  final double   altitude;
  final int      battery;
  final String   mode;
  final int      packetCount;

  const TelemetryPacket({
    required this.timestamp,
    required this.temp,
    required this.pressure,
    required this.altitude,
    required this.battery,
    required this.mode,
    this.packetCount = 0,
  });

  factory TelemetryPacket.fromJson(Map<String, dynamic> j) => TelemetryPacket(
    timestamp:   DateTime.now(),
    temp:        (j['temp']         as num).toDouble(),
    pressure:    (j['pressure']     as num).toInt(),
    altitude:    (j['altitude']     as num?)?.toDouble() ?? 0.0,
    battery:     (j['battery']      as num).toInt(),
    mode:        j['mode']?.toString() ?? 'UNKNOWN',
    packetCount: (j['packet_count'] as num?)?.toInt() ?? 0,
  );

  factory TelemetryPacket.fromFirestore(Map<String, dynamic> d) => TelemetryPacket(
    timestamp:   (d['timestamp'] as Timestamp).toDate(),
    temp:        (d['temp']      as num).toDouble(),
    pressure:    (d['pressure']  as num).toInt(),
    altitude:    (d['altitude']  as num?)?.toDouble() ?? 0.0,
    battery:     (d['battery']   as num).toInt(),
    mode:        d['mode']?.toString() ?? 'UNKNOWN',
  );

  Map<String, dynamic> toFirestore() => {
    'timestamp': Timestamp.fromDate(timestamp),
    'temp':      temp,
    'pressure':  pressure,
    'altitude':  altitude,
    'battery':   battery,
    'mode':      mode,
  };
}

// ── État agrégé telemetry ────────────────────────────────────────────────────
class TelemetryState {
  final TelemetryPacket? latest;
  final List<double> tempHistory;
  final List<double> batteryHistory;
  final List<double> pressureHistory;
  final List<double> altitudeHistory;
  final bool historyMode;

  const TelemetryState({
    this.latest,
    this.tempHistory     = const [],
    this.batteryHistory  = const [],
    this.pressureHistory = const [],
    this.altitudeHistory = const [],
    this.historyMode     = false,
  });

  TelemetryState copyWith({
    TelemetryPacket? latest,
    List<double>? tempHistory,
    List<double>? batteryHistory,
    List<double>? pressureHistory,
    List<double>? altitudeHistory,
    bool? historyMode,
  }) => TelemetryState(
    latest:          latest          ?? this.latest,
    tempHistory:     tempHistory     ?? this.tempHistory,
    batteryHistory:  batteryHistory  ?? this.batteryHistory,
    pressureHistory: pressureHistory ?? this.pressureHistory,
    altitudeHistory: altitudeHistory ?? this.altitudeHistory,
    historyMode:     historyMode     ?? this.historyMode,
  );
}

// ── Beacon ───────────────────────────────────────────────────────────────────
class BeaconState {
  final String mode;
  final bool   alive;
  final bool   remoteHold;
  final int    packetCount;

  const BeaconState({
    this.mode        = 'NO_SIGNAL',
    this.alive       = false,
    this.remoteHold  = false,
    this.packetCount = 0,
  });

  bool get isEmergency => mode == 'EMERGENCY';
  bool get isSafe      => mode == 'SAFE';
  bool get isNominal   => mode == 'NOMINAL';

  BeaconState copyWith({String? mode, bool? alive, bool? remoteHold, int? packetCount}) =>
      BeaconState(
        mode:        mode        ?? this.mode,
        alive:       alive       ?? this.alive,
        remoteHold:  remoteHold  ?? this.remoteHold,
        packetCount: packetCount ?? this.packetCount,
      );
}

// ── Alert ─────────────────────────────────────────────────────────────────────
class AlertEntry {
  final DateTime timestamp;
  final String   message;
  final String   mode;
  final bool     isThreshold;

  const AlertEntry({
    required this.timestamp,
    required this.message,
    required this.mode,
    this.isThreshold = false,
  });

  Map<String, dynamic> toFirestore() => {
    'timestamp':   Timestamp.fromDate(timestamp),
    'message':     message,
    'mode':        mode,
    'isThreshold': isThreshold,
  };
}

// ── Session ───────────────────────────────────────────────────────────────────
class GroundSession {
  final String   id;
  final DateTime startTime;
  DateTime?      endTime;
  int            packetCount;

  GroundSession({
    required this.id,
    required this.startTime,
    this.endTime,
    this.packetCount = 0,
  });

  String get label {
    final h = startTime.hour.toString().padLeft(2, '0');
    final m = startTime.minute.toString().padLeft(2, '0');
    final d = '${startTime.day.toString().padLeft(2,'0')}/'
              '${startTime.month.toString().padLeft(2,'0')}';
    return '$d  $h:$m';
  }
}

// ── Thresholds ────────────────────────────────────────────────────────────────
class AlertThresholds {
  final double tempMax;
  final double tempMin;
  final double pressureMax;
  final double pressureMin;
  final double altitudeMax;
  final double altitudeMin;
  final int    batteryMin;

  const AlertThresholds({
    this.tempMax      = 60.0,
    this.tempMin      = -20.0,
    this.pressureMax  = 110000,
    this.pressureMin  = 90000,
    this.altitudeMax  = 5000.0,
    this.altitudeMin  = -100.0,
    this.batteryMin   = 15,
  });

  AlertThresholds copyWith({
    double? tempMax,    double? tempMin,
    double? pressureMax,double? pressureMin,
    double? altitudeMax,double? altitudeMin,
    int?    batteryMin,
  }) => AlertThresholds(
    tempMax:      tempMax      ?? this.tempMax,
    tempMin:      tempMin      ?? this.tempMin,
    pressureMax:  pressureMax  ?? this.pressureMax,
    pressureMin:  pressureMin  ?? this.pressureMin,
    altitudeMax:  altitudeMax  ?? this.altitudeMax,
    altitudeMin:  altitudeMin  ?? this.altitudeMin,
    batteryMin:   batteryMin   ?? this.batteryMin,
  );
}

// =============================================================================
// RIVERPOD PROVIDERS
// =============================================================================

// ── 1. MQTT client ────────────────────────────────────────────────────────────
class MqttNotifier extends Notifier<MqttServerClient?> {
  @override MqttServerClient? build() => null;
  void setClient(MqttServerClient c) => state = c;
  void clear()                        => state = null;
}
final mqttClientProvider =
    NotifierProvider<MqttNotifier, MqttServerClient?>(MqttNotifier.new);

final connectionProvider = Provider<bool>((ref) {
  final c = ref.watch(mqttClientProvider);
  return c?.connectionStatus?.state == MqttConnectionState.connected;
});

// ── 2. Telemetry ──────────────────────────────────────────────────────────────
class TelemetryNotifier extends Notifier<TelemetryState> {
  static const _max = 60;
  @override TelemetryState build() => const TelemetryState();

  void addPacket(TelemetryPacket p) {
    final t  = _push(List.from(state.tempHistory),     p.temp);
    final b  = _push(List.from(state.batteryHistory),  p.battery.toDouble());
    final pr = _push(List.from(state.pressureHistory), p.pressure.toDouble());
    final al = _push(List.from(state.altitudeHistory), p.altitude);
    state = state.copyWith(
      latest: p, tempHistory: t, batteryHistory: b,
      pressureHistory: pr, altitudeHistory: al, historyMode: false,
    );
  }

  void loadHistory(List<TelemetryPacket> packets) {
    if (packets.isEmpty) return;
    final lim = packets.length > _max ? packets.sublist(packets.length - _max) : packets;
    state = state.copyWith(
      latest:          lim.last,
      tempHistory:     lim.map((p) => p.temp).toList(),
      batteryHistory:  lim.map((p) => p.battery.toDouble()).toList(),
      pressureHistory: lim.map((p) => p.pressure.toDouble()).toList(),
      altitudeHistory: lim.map((p) => p.altitude).toList(),
      historyMode: true,
    );
  }

  void reset() => state = const TelemetryState();

  List<double> _push(List<double> l, double v) {
    l.add(v);
    if (l.length > _max) l.removeAt(0);
    return l;
  }
}
final telemetryProvider =
    NotifierProvider<TelemetryNotifier, TelemetryState>(TelemetryNotifier.new);

// ── 3. Beacon ─────────────────────────────────────────────────────────────────
class BeaconNotifier extends Notifier<BeaconState> {
  @override BeaconState build() => const BeaconState();
  void update(Map<String, dynamic> d) => state = state.copyWith(
    mode:        d['mode']?.toString() ?? state.mode,
    alive:       d['alive'] == true,
    remoteHold:  d['remote_hold'] == 1,
    packetCount: (d['packet_count'] as num?)?.toInt() ?? state.packetCount,
  );
  void reset() => state = const BeaconState();
}
final beaconProvider =
    NotifierProvider<BeaconNotifier, BeaconState>(BeaconNotifier.new);

// ── 4. Alerts ─────────────────────────────────────────────────────────────────
class AlertsNotifier extends Notifier<List<AlertEntry>> {
  @override List<AlertEntry> build() => [];
  void add(AlertEntry e) => state = [...state, e];
  void clear()           => state = [];
}
final alertsProvider =
    NotifierProvider<AlertsNotifier, List<AlertEntry>>(AlertsNotifier.new);

// ── 5. Log ────────────────────────────────────────────────────────────────────
class LogNotifier extends Notifier<List<String>> {
  @override List<String> build() => [];
  void add(String msg) {
    final n = DateTime.now();
    final ts = '[${n.hour.toString().padLeft(2,'0')}:'
               '${n.minute.toString().padLeft(2,'0')}:'
               '${n.second.toString().padLeft(2,'0')}]';
    final next = [...state, '$ts $msg'];
    if (next.length > 100) next.removeAt(0);
    state = next;
  }
  void clear() => state = [];
}
final logProvider =
    NotifierProvider<LogNotifier, List<String>>(LogNotifier.new);

// ── 6. Thresholds ─────────────────────────────────────────────────────────────
class ThresholdsNotifier extends Notifier<AlertThresholds> {
  @override AlertThresholds build() => const AlertThresholds();
  void update(AlertThresholds t)    => state = t;
}
final thresholdsProvider =
    NotifierProvider<ThresholdsNotifier, AlertThresholds>(ThresholdsNotifier.new);

// ── 7. Sessions ───────────────────────────────────────────────────────────────
class SessionsNotifier extends Notifier<List<GroundSession>> {
  GroundSession? _current;
  String?        _currentFsId; // Firestore doc ID

  @override List<GroundSession> build() => [];

  Future<void> startSession() async {
    final s = GroundSession(
      id:        'session_${DateTime.now().millisecondsSinceEpoch}',
      startTime: DateTime.now(),
    );
    _current = s;
    state = [s, ...state];

    // Créer le document session dans Firestore
    try {
      final ref = await _db.collection('sessions').add({
        'startTime':   Timestamp.fromDate(s.startTime),
        'endTime':     null,
        'packetCount': 0,
      });
      _currentFsId = ref.id;
    } catch (e) {
      // pas de Firebase dispo → ignorer
    }
  }

  void addPacketCount() {
    _current?.packetCount++;
    state = [...state]; // force rebuild
    if (_currentFsId != null) {
      _db.collection('sessions').doc(_currentFsId).update({
        'packetCount': FieldValue.increment(1),
      }).catchError((_) {});
    }
  }

  Future<void> closeSession() async {
    _current?.endTime = DateTime.now();
    if (_currentFsId != null) {
      await _db.collection('sessions').doc(_currentFsId).update({
        'endTime': Timestamp.fromDate(_current!.endTime!),
      }).catchError((_) {});
    }
    _current      = null;
    _currentFsId  = null;
    state = [...state];
  }

  String? get currentFirestoreId => _currentFsId;
}
final sessionsProvider =
    NotifierProvider<SessionsNotifier, List<GroundSession>>(SessionsNotifier.new);

// ── 8. Firebase sessions list (pour history) ──────────────────────────────────
// Provider qui récupère les sessions Firestore pour le side panel
final firestoreSessionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final snap = await _db
        .collection('sessions')
        .orderBy('startTime', descending: true)
        .limit(20)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  } catch (_) {
    return [];
  }
});

// Provider pour charger les paquets d'une session Firestore
final sessionPacketsProvider =
    FutureProvider.family<List<TelemetryPacket>, String>((ref, sessionId) async {
  try {
    final snap = await _db
        .collection('sessions')
        .doc(sessionId)
        .collection('packets')
        .orderBy('timestamp')
        .get();
    return snap.docs
        .map((d) => TelemetryPacket.fromFirestore(d.data()))
        .toList();
  } catch (_) {
    return [];
  }
});

// =============================================================================
// MQTT LISTENER SERVICE
// =============================================================================
class MqttListenerService {
  final Ref _ref;
  StreamSubscription? _sub;

  MqttListenerService(this._ref);

  Future<void> attach(MqttServerClient client) async {
    _ref.read(mqttClientProvider.notifier).setClient(client);
    await _ref.read(sessionsProvider.notifier).startSession();
    _ref.read(logProvider.notifier).add('Connecté au broker MQTT');

    client.subscribe('cubesat/hk',     MqttQos.atMostOnce);
    client.subscribe('cubesat/beacon', MqttQos.atMostOnce);
    client.subscribe('cubesat/alert',  MqttQos.atMostOnce);
    client.subscribe('cubesat/ack',    MqttQos.atMostOnce);

    _sub = client.updates!.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>> events) {
    final rec     = events[0].payload as MqttPublishMessage;
    final payload = utf8.decode(rec.payload.message);
    final topic   = events[0].topic;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      switch (topic) {
        case 'cubesat/hk':     _handleHK(data);     break;
        case 'cubesat/beacon': _handleBeacon(data);  break;
        case 'cubesat/alert':  _handleAlert(data);   break;
        case 'cubesat/ack':
          _ref.read(logProvider.notifier)
              .add('ACK ← ${data["ack"]} (ok=${data["success"]})');
          break;
      }
    } catch (e) {
      _ref.read(logProvider.notifier).add('Parse error on $topic: $e');
    }
  }

  void _handleHK(Map<String, dynamic> data) {
    final packet = TelemetryPacket.fromJson(data);
    _ref.read(telemetryProvider.notifier).addPacket(packet);
    _ref.read(sessionsProvider.notifier).addPacketCount();
    _checkThresholds(packet);
    _ref.read(logProvider.notifier).add(
      'HK T=${packet.temp.toStringAsFixed(1)}°C '
      'P=${packet.pressure}Pa '
      'Alt=${packet.altitude.toStringAsFixed(1)}m '
      'B=${packet.battery}%',
    );

    // Écrire dans Firestore
    final fsId = _ref.read(sessionsProvider.notifier).currentFirestoreId;
    if (fsId != null) {
      _db
          .collection('sessions')
          .doc(fsId)
          .collection('packets')
          .add(packet.toFirestore())
          .catchError((_) {});
    }
  }

  void _handleBeacon(Map<String, dynamic> data) {
    _ref.read(beaconProvider.notifier).update(data);
  }

  void _handleAlert(Map<String, dynamic> data) {
    final entry = AlertEntry(
      timestamp: DateTime.now(),
      message:   data['alert']?.toString() ?? 'Unknown alert',
      mode:      data['mode']?.toString()  ?? 'UNKNOWN',
    );
    _ref.read(alertsProvider.notifier).add(entry);
    _ref.read(logProvider.notifier).add('⚠ ALERT: ${entry.message}');

    // Écrire alerte dans Firestore
    _db.collection('alerts').add(entry.toFirestore()).catchError((_) {});
  }

  void _checkThresholds(TelemetryPacket p) {
    final t = _ref.read(thresholdsProvider);
    void flag(String msg) {
      final e = AlertEntry(
        timestamp: DateTime.now(), message: '[SEUIL] $msg',
        mode: 'FLUTTER', isThreshold: true,
      );
      _ref.read(alertsProvider.notifier).add(e);
      _ref.read(logProvider.notifier).add('⚠ $msg');
      _db.collection('alerts').add(e.toFirestore()).catchError((_) {});
    }
    if (p.temp    > t.tempMax)     flag('Temp HAUTE: ${p.temp.toStringAsFixed(1)}°C');
    if (p.temp    < t.tempMin)     flag('Temp BASSE: ${p.temp.toStringAsFixed(1)}°C');
    if (p.battery < t.batteryMin)  flag('Batterie FAIBLE: ${p.battery}%');
    if (p.pressure > t.pressureMax) flag('Pression HAUTE: ${p.pressure}Pa');
    if (p.pressure < t.pressureMin) flag('Pression BASSE: ${p.pressure}Pa');
    if (p.altitude > t.altitudeMax) flag('Altitude HAUTE: ${p.altitude.toStringAsFixed(1)}m');
  }

  // ── Commandes MQTT ──────────────────────────────────────────────────────────
  void _publish(String topic, String payload) {
    final client = _ref.read(mqttClientProvider);
    if (client?.connectionStatus?.state != MqttConnectionState.connected) return;
    final b = MqttClientPayloadBuilder()..addString(payload);
    client!.publishMessage(topic, MqttQos.atMostOnce, b.payload!);
    _ref.read(logProvider.notifier).add('CMD → $topic : $payload');
  }

  void forceSafeMode()    => _publish('cubesat/cmd', '{"cmd":"safe"}');
  void forceNominalMode() => _publish('cubesat/cmd', '{"cmd":"nominal"}');
  void forceReboot()      => _publish('cubesat/cmd', '{"cmd":"reboot"}');
  void sendCustomPayload(String topic, String payload) => _publish(topic, payload);

  // ── Déconnexion ─────────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _sub?.cancel(); _sub = null;
    await _ref.read(sessionsProvider.notifier).closeSession();
    _ref.read(mqttClientProvider)?.disconnect();
    _ref.read(mqttClientProvider.notifier).clear();
    _ref.read(beaconProvider.notifier).reset();
    _ref.read(logProvider.notifier).add('Déconnecté');
  }

  // ── Export CSV ───────────────────────────────────────────────────────────────
  String exportCsv(List<TelemetryPacket> packets, {String sessionId = ''}) {
    final b = StringBuffer()
      ..writeln('# CubeSat Ground Station Export')
      ..writeln('# Session: $sessionId')
      ..writeln('# Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('timestamp,temp_c,pressure_pa,altitude_m,battery_pct,mode');
    for (final p in packets) {
      b.writeln('${p.timestamp.toIso8601String()},'
                '${p.temp.toStringAsFixed(2)},'
                '${p.pressure},'
                '${p.altitude.toStringAsFixed(2)},'
                '${p.battery},'
                '${p.mode}');
    }
    return b.toString();
  }
}

final mqttListenerProvider = Provider<MqttListenerService>((ref) {
  return MqttListenerService(ref);
});