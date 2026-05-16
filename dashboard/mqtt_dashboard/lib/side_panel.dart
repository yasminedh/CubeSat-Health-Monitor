// =============================================================================
// side_panel.dart
// Fonctionne en deux modes :
//   • Desktop (≥900px) : colonne fixe de 264px intégrée dans le layout
//   • Mobile/Tablet    : contenu d'un Drawer Flutter (pleine hauteur)
//
// Sections :
//   1. Connection   — statut broker, déconnexion
//   2. Commands     — force safe/nominal/reboot + payload custom (confirmation à 2 étapes)
//   3. History      — sessions in-memory + sessions Firestore avec date range
//   4. Settings     — seuils d'alerte par slider
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'app_colors.dart';
import 'telemetry_service.dart';

class SidePanel extends ConsumerStatefulWidget {
  const SidePanel({super.key});

  @override
  ConsumerState<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends ConsumerState<SidePanel> {

  // ── Sections ouvertes/fermées ─────────────────────────────────────────────
  bool _connOpen     = true;
  bool _cmdOpen      = true;
  bool _histOpen     = false;
  bool _settOpen     = false;

  // ── Confirm 2-phases ─────────────────────────────────────────────────────
  bool _cSafe = false, _cNominal = false, _cReboot = false;

  // ── History ───────────────────────────────────────────────────────────────
  final _topicCtrl   = TextEditingController(text: 'cubesat/cmd');
  final _payloadCtrl = TextEditingController();
  String? _loadedId;
  DateTime _from = DateTime.now().subtract(const Duration(hours: 6));
  DateTime _to   = DateTime.now();

  // Onglet history: 'memory' | 'firebase'
  String _histTab = 'memory';

  // État pour le chargement Firestore
  bool _fsLoading = false;
  String? _fsError;

  @override
  void dispose() {
    _topicCtrl.dispose();
    _payloadCtrl.dispose();
    super.dispose();
  }

  MqttListenerService get _svc => ref.read(mqttListenerProvider);

  Color _cc(bool conn, String mode) {
    if (!conn)           return AppColors.textDim;
    if (mode=='EMERGENCY') return AppColors.accentRed;
    if (mode=='SAFE')      return AppColors.accentYellow;
    return AppColors.accentGreen;
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final connected  = ref.watch(connectionProvider);
    final beacon     = ref.watch(beaconProvider);
    final sessions   = ref.watch(sessionsProvider);
    final thresholds = ref.watch(thresholdsProvider);
    final cc         = _cc(connected, beacon.mode);

    return Container(
      width: 264,
      color: AppColors.sidePanel,
      child: Column(children: [
        _header(cc, beacon),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _section(Icons.wifi_rounded,    'Connection', _connOpen,
                () => setState(()=>_connOpen=!_connOpen),
                _connectionSection(connected, beacon, cc)),
              _div(),
              _section(Icons.send_rounded,    'Commands',   _cmdOpen,
                () => setState(()=>_cmdOpen=!_cmdOpen),
                _commandSection(connected)),
              _div(),
              _section(Icons.history_rounded, 'History',    _histOpen,
                () => setState(()=>_histOpen=!_histOpen),
                _historySection(sessions)),
              _div(),
              _section(Icons.tune_rounded,    'Settings',   _settOpen,
                () => setState(()=>_settOpen=!_settOpen),
                _settingsSection(thresholds)),
            ],
          ),
        ),
        _footer(beacon),
      ]),
    );
  }

  // ════════════════════════════════════════════════
  // HEADER
  // ════════════════════════════════════════════════
  Widget _header(Color cc, BeaconState beacon) => Container(
    height: 48, color: AppColors.header,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(children: [
      Icon(Icons.satellite_alt, color: AppColors.accentBlue, size: 16),
      const SizedBox(width: 8),
      Text('GROUND STATION', style: TextStyle(
        color: AppColors.textSecondary, fontSize: 10,
        letterSpacing: 1.8, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
      const Spacer(),
      if (beacon.remoteHold) ...[
        Icon(Icons.lock_outline, color: AppColors.accentYellow, size: 12),
        const SizedBox(width: 4),
      ],
      Container(width: 8, height: 8,
        decoration: BoxDecoration(color: cc, shape: BoxShape.circle)),
    ]),
  );

  // ════════════════════════════════════════════════
  // SECTION WRAPPER
  // ════════════════════════════════════════════════
  Widget _section(IconData icon, String title, bool open,
      VoidCallback onTap, Widget child) =>
    Column(children: [
      InkWell(onTap: onTap, child: Container(
        height: 38, color: AppColors.header,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          Icon(icon, color: AppColors.textSecondary, size: 15),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: AppColors.textSecondary,
            fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5)),
          const Spacer(),
          Icon(open ? Icons.expand_less : Icons.expand_more,
            color: AppColors.textDim, size: 16),
        ]),
      )),
      if (open) child,
    ]);

  Widget _div() => Container(height: 1, color: AppColors.separator);

  // ════════════════════════════════════════════════
  // 1. CONNECTION
  // ════════════════════════════════════════════════
  Widget _connectionSection(bool connected, BeaconState beacon, Color cc) =>
    Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Status pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cc.withOpacity(.08),
            border: Border.all(color: cc.withOpacity(.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Container(width: 7, height: 7,
              decoration: BoxDecoration(color: cc, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(connected ? beacon.mode : 'OFFLINE',
              style: TextStyle(color: cc, fontSize: 11, fontFamily: 'monospace',
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Spacer(),
            Text('HiveMQ', style: TextStyle(color: AppColors.textDim,
              fontSize: 9, fontFamily: 'monospace')),
          ]),
        ),

        if (beacon.remoteHold) ...[
          const SizedBox(height: 6),
          _pill('REMOTE HOLD ACTIF', Icons.lock_outline, AppColors.accentYellow),
        ],

        const SizedBox(height: 10),
        if (beacon.packetCount > 0)
          _info('Paquets reçus', '${beacon.packetCount}'),
        _info('Port', '8883 TLS'),
        _info('Topics', 'hk / beacon / alert / cmd'),

        const SizedBox(height: 12),
        if (connected)
          _btn('DISCONNECT', Icons.link_off_rounded, AppColors.accentRed,
            () async {
              await _svc.disconnect();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            }),
      ],
    ));

  // ════════════════════════════════════════════════
  // 2. COMMANDS
  // ════════════════════════════════════════════════
  Widget _commandSection(bool connected) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lbl('COMMANDES SATELLITE'),
      const SizedBox(height: 8),

      _confirmBtn(
        label: 'FORCE SAFE MODE',   confirmLabel: 'CONFIRMER SAFE',
        topic: 'cubesat/cmd',       payload: '{"cmd":"safe"}',
        icon: Icons.warning_amber_rounded, color: AppColors.accentYellow,
        confirmed: _cSafe, enabled: connected,
        onArm:    () => setState((){ _cSafe=true; _cNominal=false; _cReboot=false; }),
        onConfirm:() { _svc.forceSafeMode();    setState(()=>_cSafe=false); },
        onCancel: () => setState(()=>_cSafe=false),
      ),
      const SizedBox(height: 8),

      _confirmBtn(
        label: 'FORCE NOMINAL',     confirmLabel: 'CONFIRMER NOMINAL',
        topic: 'cubesat/cmd',       payload: '{"cmd":"nominal"}',
        icon: Icons.check_circle_outline_rounded, color: AppColors.accentGreen,
        confirmed: _cNominal, enabled: connected,
        onArm:    () => setState((){ _cNominal=true; _cSafe=false; _cReboot=false; }),
        onConfirm:() { _svc.forceNominalMode(); setState(()=>_cNominal=false); },
        onCancel: () => setState(()=>_cNominal=false),
      ),
      const SizedBox(height: 8),

      _confirmBtn(
        label: 'REBOOT SEQUENCE',   confirmLabel: 'CONFIRMER REBOOT',
        topic: 'cubesat/cmd',       payload: '{"cmd":"reboot"}',
        icon: Icons.restart_alt_rounded, color: AppColors.accentRed,
        confirmed: _cReboot, enabled: connected,
        onArm:    () => setState((){ _cReboot=true; _cSafe=false; _cNominal=false; }),
        onConfirm:() { _svc.forceReboot();      setState(()=>_cReboot=false); },
        onCancel: () => setState(()=>_cReboot=false),
      ),

      const SizedBox(height: 16),
      _lbl('PAYLOAD PERSONNALISÉ'),
      const SizedBox(height: 8),
      _field(_topicCtrl,   'Topic'),
      const SizedBox(height: 6),
      _field(_payloadCtrl, 'Payload JSON'),
      const SizedBox(height: 8),
      _btn('ENVOYER', Icons.send_rounded, AppColors.accentBlue,
        connected && _topicCtrl.text.isNotEmpty && _payloadCtrl.text.isNotEmpty
          ? () { _svc.sendCustomPayload(_topicCtrl.text.trim(), _payloadCtrl.text.trim());
                 _payloadCtrl.clear(); setState((){}); }
          : null),
    ]),
  );

  // ════════════════════════════════════════════════
  // 3. HISTORY
  // ════════════════════════════════════════════════
  Widget _historySection(List<GroundSession> sessions) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

      // ── Onglet mémoire / Firebase ─────────────────
      Row(children: [
        Expanded(child: _tabBtn('EN MÉMOIRE', 'memory')),
        const SizedBox(width: 6),
        Expanded(child: _tabBtn('FIREBASE',   'firebase')),
      ]),
      const SizedBox(height: 12),

      if (_histTab == 'memory') ...[
        // ── Sessions in-memory ─────────────────────
        _lbl('SESSIONS (${sessions.length})'),
        const SizedBox(height: 8),

        if (sessions.isEmpty)
          Text('Aucune session disponible.',
            style: TextStyle(color: AppColors.textDim, fontSize: 10, fontFamily: 'monospace'))
        else
          ...sessions.map((s) => _sessionTile(
            id:          s.id,
            label:       s.label,
            packetCount: s.packetCount,
            isLive:      s.endTime == null,
            onTap: () {
              // Reconstruct packets from telemetry history (in-memory)
              // On passe l'id de session, le notifier gère les paquets
              ref.read(logProvider.notifier).add(
                '[HISTORY] Session ${s.label} — ${s.packetCount} paquets');
              setState(() => _loadedId = s.id);
            },
          )),

        const SizedBox(height: 12),
        _btn('RETOUR LIVE', Icons.live_tv_rounded, AppColors.accentBlue, () {
          ref.read(telemetryProvider.notifier).reset();
          setState(() => _loadedId = null);
          ref.read(logProvider.notifier).add('[LIVE] Retour au mode temps réel');
        }),

      ] else ...[
        // ── Firestore history ──────────────────────
        

        const SizedBox(height: 16),
        _lbl('SESSIONS FIRESTORE'),
        const SizedBox(height: 8),

        // Liste des sessions Firestore
        Consumer(builder: (ctx, r, _) {
          final fsSessions = r.watch(firestoreSessionsProvider);
          return fsSessions.when(
            loading: () => Center(child: SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textDim))),
            error:   (e, _) => Text('Erreur: $e',
              style: TextStyle(color: AppColors.accentRed, fontSize: 9, fontFamily: 'monospace')),
            data: (list) {
              if (list.isEmpty) return Text('Aucune session.',
                style: TextStyle(color: AppColors.textDim, fontSize: 10, fontFamily: 'monospace'));
              return Column(
                children: list.map((s) {
                  final id  = s['id'] as String;
                  final ts  = (s['startTime'] as Timestamp?)?.toDate();
                  final cnt = (s['packetCount'] as num?)?.toInt() ?? 0;
                  final label = ts != null
                      ? DateFormat('dd/MM  HH:mm').format(ts)
                      : id;
                  return _sessionTile(
                    id: id, label: label, packetCount: cnt,
                    isLive: s['endTime'] == null,
                    onTap: () => _loadFirebaseSession(id, label),
                  );
                }).toList(),
              );
            },
          );
        }),

        const SizedBox(height: 10),
        _btn('RETOUR LIVE', Icons.live_tv_rounded, AppColors.accentBlue, () {
          ref.read(telemetryProvider.notifier).reset();
          setState(() { _loadedId = null; _fsError = null; });
          ref.read(logProvider.notifier).add('[LIVE] Retour au mode temps réel');
        }),
      ],
    ]),
  );

  // ─── Charger les paquets d'une session Firestore par plage de dates ─────────
  Future<void> _loadFirebaseHistory() async {
    setState(() { _fsLoading = true; _fsError = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('packets')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_from))
          .where('timestamp', isLessThanOrEqualTo:
              Timestamp.fromDate(_to.add(const Duration(days: 1))))
          //.orderBy('timestamp')
          .limit(500)
          .get();

      final packets = snap.docs
          .map((d) => TelemetryPacket.fromFirestore(d.data()))
          .toList();

      ref.read(telemetryProvider.notifier).loadHistory(packets);
      ref.read(logProvider.notifier).add(
        '[FIREBASE] ${packets.length} paquets chargés (${DateFormat('dd/MM').format(_from)}→${DateFormat('dd/MM').format(_to)})');
      setState(() { _fsLoading = false; _loadedId = 'firebase_range'; });
    } catch (e) {
      setState(() { _fsLoading = false; _fsError = 'Erreur: $e'; });
    }
  }

  // ─── Charger tous les paquets d'une session Firestore spécifique ─────────────
  Future<void> _loadFirebaseSession(String sessionId, String label) async {
    setState(() { _fsLoading = true; _fsError = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sessions')
          .doc(sessionId)
          .collection('packets')
          .orderBy('timestamp')
          .get();

      final packets = snap.docs
          .map((d) => TelemetryPacket.fromFirestore(d.data()))
          .toList();

      ref.read(telemetryProvider.notifier).loadHistory(packets);
      ref.read(logProvider.notifier)
          .add('[FIREBASE] Session "$label" — ${packets.length} paquets');
      setState(() { _fsLoading = false; _loadedId = sessionId; });
    } catch (e) {
      setState(() { _fsLoading = false; _fsError = 'Erreur: $e'; });
    }
  }

  // ════════════════════════════════════════════════
  // 4. SETTINGS
  // ════════════════════════════════════════════════
  Widget _settingsSection(AlertThresholds t) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lbl('SEUILS D\'ALERTE'),
      const SizedBox(height: 10),

      _slider('Temp max (°C)',    t.tempMax,    0,   120,
        (v) => ref.read(thresholdsProvider.notifier).update(t.copyWith(tempMax: v))),
      _slider('Temp min (°C)',    t.tempMin,  -50,    50,
        (v) => ref.read(thresholdsProvider.notifier).update(t.copyWith(tempMin: v))),
      _slider('Batterie min (%)', t.batteryMin.toDouble(), 0, 50,
        (v) => ref.read(thresholdsProvider.notifier).update(t.copyWith(batteryMin: v.toInt()))),
      _slider('Altitude max (m)', t.altitudeMax, 0, 10000,
        (v) => ref.read(thresholdsProvider.notifier).update(t.copyWith(altitudeMax: v))),

      const SizedBox(height: 4),
      Text('Appliqué immédiatement.',
        style: TextStyle(color: AppColors.textDim, fontSize: 9, fontFamily: 'monospace')),

      const SizedBox(height: 14),
      _lbl('AFFICHAGE'),
      const SizedBox(height: 6),
      _info('Fenêtre graphique', '60 points'),
      _info('HK nominal',       '3 s'),
      _info('HK safe mode',     '8 s'),
    ]),
  );

  // ════════════════════════════════════════════════
  // FOOTER
  // ════════════════════════════════════════════════
  Widget _footer(BeaconState beacon) => Container(
    height: 36, color: AppColors.header,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(children: [
      Icon(Icons.info_outline, color: AppColors.textDim, size: 12),
      const SizedBox(width: 6),
      Text('CubeSat GS  v1.0.0',
        style: TextStyle(color: AppColors.textDim, fontSize: 9, fontFamily: 'monospace')),
      const Spacer(),
      if (beacon.alive)
        Text('PKT #${beacon.packetCount}',
          style: TextStyle(color: AppColors.textDim, fontSize: 9, fontFamily: 'monospace')),
    ]),
  );

  // ════════════════════════════════════════════════
  // PETITS WIDGETS RÉUTILISABLES
  // ════════════════════════════════════════════════
  Widget _lbl(String s) => Text(s, style: TextStyle(
    color: AppColors.textDim, fontSize: 9, letterSpacing: 1.4, fontFamily: 'monospace'));

  Widget _info(String k, String v) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(children: [
      Text('$k  ', style: TextStyle(color: AppColors.textDim, fontSize: 9, fontFamily: 'monospace')),
      Expanded(child: Text(v, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontFamily: 'monospace'))),
    ]),
  );

  Widget _pill(String label, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(.08),
      border: Border.all(color: color.withOpacity(.3)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 11),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontSize: 9,
        fontFamily: 'monospace', letterSpacing: .8)),
    ]),
  );

  Widget _tabBtn(String label, String tab) => GestureDetector(
    onTap: () => setState(() => _histTab = tab),
    child: Container(
      height: 30,
      decoration: BoxDecoration(
        color: _histTab == tab
            ? AppColors.accentBlue.withOpacity(.15)
            : AppColors.bg,
        border: Border.all(
          color: _histTab == tab ? AppColors.accentBlue : AppColors.border),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(child: Text(label, style: TextStyle(
        color: _histTab == tab ? AppColors.accentBlue : AppColors.textDim,
        fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.w700, letterSpacing: .8))),
    ),
  );

  Widget _btn(String label, IconData icon, Color color, VoidCallback? onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: onTap != null ? color.withOpacity(.1) : AppColors.border.withOpacity(.3),
          border: Border.all(
            color: onTap != null ? color.withOpacity(.5) : AppColors.border),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: onTap != null ? color : AppColors.textDim, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            color: onTap != null ? color : AppColors.textDim,
            fontSize: 10, fontFamily: 'monospace',
            fontWeight: FontWeight.w700, letterSpacing: 1)),
        ]),
      ),
    );

  Widget _confirmBtn({
    required String label, required String confirmLabel,
    required String topic, required String payload,
    required IconData icon, required Color color,
    required bool confirmed, required bool enabled,
    required VoidCallback onArm,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
  }) {
    if (confirmed) return Column(children: [
      Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(.06),
          border: Border.all(color: color.withOpacity(.3)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SERA PUBLIÉ :', style: TextStyle(
            color: AppColors.textDim, fontSize: 8, fontFamily: 'monospace', letterSpacing: 1)),
          const SizedBox(height: 2),
          Text('$topic → $payload',
            style: TextStyle(color: color, fontSize: 9, fontFamily: 'monospace')),
        ]),
      ),
      Row(children: [
        Expanded(child: _btn(confirmLabel, Icons.check_rounded, color, onConfirm)),
        const SizedBox(width: 6),
        Expanded(child: _btn('ANNULER', Icons.close_rounded, AppColors.textDim, onCancel)),
      ]),
    ]);
    return _btn(label, icon, color, enabled ? onArm : null);
  }

  Widget _field(TextEditingController ctrl, String label) => TextField(
    controller: ctrl,
    onChanged: (_) => setState(() {}),
    style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontFamily: 'monospace'),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppColors.textDim, fontSize: 9, fontFamily: 'monospace'),
      filled: true, fillColor: AppColors.bg, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: AppColors.accentBlue)),
    ),
  );

  Widget _dateRow(String label, DateTime d, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(children: [
          Text('$label  ', style: TextStyle(
            color: AppColors.textDim, fontSize: 9, fontFamily: 'monospace')),
          Expanded(child: Text(DateFormat('yyyy-MM-dd').format(d),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 10, fontFamily: 'monospace'))),
          Icon(Icons.calendar_today_rounded, color: AppColors.textDim, size: 12),
        ]),
      ),
    );

  Widget _sessionTile({
    required String id,
    required String label,
    required int    packetCount,
    required bool   isLive,
    required VoidCallback onTap,
  }) {
    final isLoaded = _loadedId == id;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isLoaded
              ? AppColors.accentPurple.withOpacity(.12)
              : AppColors.bg,
          border: Border.all(
            color: isLoaded ? AppColors.accentPurple.withOpacity(.5) : AppColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              color: AppColors.textPrimary, fontSize: 10, fontFamily: 'monospace')),
            const SizedBox(height: 2),
            Text('$packetCount paquets', style: TextStyle(
              color: AppColors.textDim, fontSize: 9, fontFamily: 'monospace')),
          ])),
          const SizedBox(width: 6),
          if (isLive)
            _badge('LIVE', AppColors.accentGreen)
          else if (isLoaded)
            _badge('CHARGÉ', AppColors.accentPurple),
        ]),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(.15),
      border: Border.all(color: color.withOpacity(.4)),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Text(text, style: TextStyle(
      color: color, fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
  );

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontFamily: 'monospace')),
        const Spacer(),
        Text(value.toStringAsFixed(0), style: TextStyle(
          color: AppColors.accentBlue, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
      ]),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 6,
          ),
          activeTrackColor: AppColors.accentBlue,
          inactiveTrackColor: AppColors.gridLine,
          thumbColor: AppColors.accentBlue,
          overlayColor: AppColors.accentBlue.withOpacity(.15),
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),  
    ]),
  );

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2024),
    lastDate: DateTime.now(),
    builder: (ctx, child) => Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accentBlue, onPrimary: Colors.white,
          surface: AppColors.panel,     onSurface: AppColors.textPrimary,
        ),
        dialogBackgroundColor: AppColors.panel,
      ),
      child: child!,
    ),
  );
}