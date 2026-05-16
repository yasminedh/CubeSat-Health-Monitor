// =============================================================================
// mission_control_page.dart  — Responsive (mobile portrait + landscape + desktop)
// Mobile portrait  : TabBar (Temp | Pressure | Altitude | Battery | Status)
// Mobile landscape : 2 graphiques côte à côte + colonne droite scrollable
// Desktop/tablet   : layout complet 2/3 + 1/3 avec side panel fixe
// Side panel       : Drawer sur mobile, colonne fixe sur desktop
// =============================================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../app_colors.dart';
import '../telemetry_service.dart';
import '../side_panel.dart';

typedef _C = AppColors;

// Breakpoints
const double _kTablet  = 600;
const double _kDesktop = 900;

class MissionControlPage extends ConsumerStatefulWidget {
  final MqttServerClient client;
  const MissionControlPage({super.key, required this.client});

  @override
  ConsumerState<MissionControlPage> createState() => _MissionControlPageState();
}

class _MissionControlPageState extends ConsumerState<MissionControlPage>
    with TickerProviderStateMixin {

  late AnimationController _blinkCtrl;
  late AnimationController _orbitCtrl;
  late TabController       _tabCtrl;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _orbitCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
    _tabCtrl   = TabController(length: 5, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mqttListenerProvider).attach(widget.client);
    });
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    _orbitCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Color _modeColor(BeaconState b) {
    if (b.isEmergency) return _C.accentRed;
    if (b.isSafe)      return _C.accentYellow;
    if (b.isNominal)   return _C.accentGreen;
    return _C.textDim;
  }

  @override
  Widget build(BuildContext context) {
    final telem     = ref.watch(telemetryProvider);
    final beacon    = ref.watch(beaconProvider);
    final alerts    = ref.watch(alertsProvider);
    final log       = ref.watch(logProvider);
    final width     = MediaQuery.of(context).size.width;
    final isDesktop = width >= _kDesktop;
    final isTablet  = width >= _kTablet;
    final mc        = _modeColor(beacon);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _C.bg,
      // ── Side panel comme Drawer sur mobile/tablet ───────────────────
      drawer: isDesktop ? null : const Drawer(child: SidePanel()),
      body: SafeArea(
        child: Column(children: [
          _TopBar(
            beacon:        beacon,
            modeColor:     mc,
            latest:        telem.latest,
            blinkCtrl:     _blinkCtrl,
            alertCount:    alerts.length,
            historyMode:   telem.historyMode,
            isDesktop:     isDesktop,
            onMenuTap:     () => _scaffoldKey.currentState?.openDrawer(),
          ),
          if (!isDesktop)
            _MobileTabBar(tabCtrl: _tabCtrl, beacon: beacon),
          Expanded(
            child: isDesktop
                ? _DesktopLayout(
                    telem: telem, beacon: beacon, alerts: alerts,
                    log: log, orbitCtrl: _orbitCtrl,
                  )
                : isTablet
                    ? _TabletLayout(
                        telem: telem, beacon: beacon, alerts: alerts,
                        log: log, orbitCtrl: _orbitCtrl, tabCtrl: _tabCtrl,
                      )
                    : _MobileLayout(
                        telem: telem, beacon: beacon, alerts: alerts,
                        log: log, orbitCtrl: _orbitCtrl, tabCtrl: _tabCtrl,
                      ),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════
// TOP BAR  (adaptive)
// ═════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  final BeaconState      beacon;
  final Color            modeColor;
  final TelemetryPacket? latest;
  final AnimationController blinkCtrl;
  final int              alertCount;
  final bool             historyMode, isDesktop;
  final VoidCallback     onMenuTap;

  const _TopBar({
    required this.beacon,     required this.modeColor,
    required this.latest,     required this.blinkCtrl,
    required this.alertCount, required this.historyMode,
    required this.isDesktop,  required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < _kTablet;
    return Container(
      height: 48,
      color: _C.header,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        // Hamburger (mobile/tablet) ou icône satellite (desktop)
        if (!isDesktop)
          IconButton(
            onPressed: onMenuTap,
            icon: Icon(Icons.menu_rounded, color: _C.textSecondary, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          )
        else
          Icon(Icons.satellite_alt, color: _C.accentBlue, size: 20),
        const SizedBox(width: 8),
        // Titre court sur mobile, long sur desktop
        Text(
          narrow ? 'CUBESAT GS' : 'CUBESAT  MISSION CONTROL',
          style: TextStyle(
            color: _C.textPrimary, fontSize: narrow ? 12 : 13,
            fontWeight: FontWeight.w700,
            letterSpacing: narrow ? 1.5 : 2.5,
            fontFamily: 'monospace',
          ),
        ),
        if (historyMode) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _C.accentPurple.withOpacity(.15),
              border: Border.all(color: _C.accentPurple.withOpacity(.5)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('HIST', style: TextStyle(
              color: _C.accentPurple, fontSize: 9,
              fontFamily: 'monospace', letterSpacing: 1)),
          ),
        ],
        const Spacer(),
        // Quick stats — seulement si la place le permet
        if (!narrow && latest != null) ...[
          _QS('T', '${latest!.temp.toStringAsFixed(1)}°',   _C.accentOrange),
          _QS('B', '${latest!.battery}%',                   _C.accentGreen),
          _QS('P', '${latest!.pressure}Pa',                 _C.accentBlue),
          const SizedBox(width: 8),
        ],
        // Alert badge
        if (alertCount > 0)
          AnimatedBuilder(
            animation: blinkCtrl,
            builder: (_, __) => Opacity(
              opacity: 0.4 + 0.6 * blinkCtrl.value,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _C.accentRed.withOpacity(.15),
                  border: Border.all(color: _C.accentRed),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('⚠ $alertCount',
                  style: const TextStyle(
                    color: _C.accentRed, fontSize: 11,
                    fontWeight: FontWeight.w700, fontFamily: 'monospace')),
              ),
            ),
          ),
        // Mode pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: modeColor.withOpacity(.12),
            border: Border.all(color: modeColor),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6,
              decoration: BoxDecoration(color: modeColor, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(beacon.isEmergency ? 'EMER' : beacon.mode,
              style: TextStyle(color: modeColor, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 1, fontFamily: 'monospace')),
          ]),
        ),
      ]),
    );
  }
}

class _QS extends StatelessWidget {
  final String l, v; final Color c;
  const _QS(this.l, this.v, this.c);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: RichText(text: TextSpan(children: [
      TextSpan(text: '$l ', style: TextStyle(color: _C.textDim, fontSize: 9, fontFamily: 'monospace')),
      TextSpan(text: v,   style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
    ])),
  );
}

// ═════════════════════════════════════════════════
// MOBILE TAB BAR
// ═════════════════════════════════════════════════
class _MobileTabBar extends StatelessWidget {
  final TabController tabCtrl;
  final BeaconState   beacon;
  const _MobileTabBar({required this.tabCtrl, required this.beacon});

  @override
  Widget build(BuildContext context) => Container(
    color: _C.header,
    height: 40,
    child: TabBar(
      controller: tabCtrl,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: _C.accentBlue,
      indicatorWeight: 2,
      labelColor: _C.accentBlue,
      unselectedLabelColor: _C.textDim,
      labelStyle: const TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
      tabs: const [
        Tab(text: 'TEMP'),
        Tab(text: 'PRESSURE'),
        Tab(text: 'ALTITUDE'),
        Tab(text: 'BATTERY'),
        Tab(text: 'STATUS'),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════
// MOBILE LAYOUT  (portrait < 600px)
// 5 tabs plein écran
// ═════════════════════════════════════════════════
class _MobileLayout extends StatelessWidget {
  final TelemetryState   telem;
  final BeaconState      beacon;
  final List<AlertEntry> alerts;
  final List<String>     log;
  final AnimationController orbitCtrl;
  final TabController    tabCtrl;

  const _MobileLayout({
    required this.telem,   required this.beacon,
    required this.alerts,  required this.log,
    required this.orbitCtrl, required this.tabCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: tabCtrl,
      children: [
        // ── TEMP ──
        _FullChart(
          title: 'Temperature', unit: '°C',
          series: [_Series('temp.', telem.tempHistory, _C.accentOrange)],
          latest: telem.latest?.temp.toStringAsFixed(1),
          latestColor: _C.accentOrange,
        ),
        // ── PRESSURE ──
        _FullChart(
          title: 'Pressure (BMP180)', unit: 'Pa',
          series: [_Series('pressure', telem.pressureHistory, _C.accentBlue)],
          latest: telem.latest?.pressure.toString(),
          latestColor: _C.accentBlue,
        ),
        // ── ALTITUDE ──
        _FullChart(
          title: 'Altitude (BMP180)', unit: 'm',
          series: [_Series('altitude', telem.altitudeHistory, _C.accentTeal)],
          latest: telem.latest?.altitude.toStringAsFixed(1),
          latestColor: _C.accentTeal,
        ),
        // ── BATTERY ──
        _FullChart(
          title: 'Battery Level', unit: '%',
          series: [_Series('battery', telem.batteryHistory, _C.accentGreen)],
          yMin: 0, yMax: 100,
          latest: '${telem.latest?.battery ?? '--'}',
          latestColor: _C.accentGreen,
        ),
        // ── STATUS ──
        _MobileStatusTab(
          telem: telem, beacon: beacon, alerts: alerts,
          log: log, orbitCtrl: orbitCtrl,
        ),
      ],
    );
  }
}

// ── Onglet plein écran pour un graphique + valeur courante ─────────────────────
class _FullChart extends StatelessWidget {
  final String        title, unit;
  final List<_Series> series;
  final double?       yMin, yMax;
  final String?       latest;
  final Color         latestColor;

  const _FullChart({
    required this.title,   required this.unit,
    required this.series,  required this.latestColor,
    this.yMin, this.yMax,  this.latest,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: _C.bg,
    child: Column(children: [
      // Valeur courante grande
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        color: _C.panel,
        child: Column(children: [
          Text(title, style: TextStyle(
            color: _C.textSecondary, fontSize: 11, fontFamily: 'monospace', letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(latest != null ? '$latest $unit' : '— $unit',
            style: TextStyle(color: latestColor, fontSize: 36,
              fontWeight: FontWeight.w800, fontFamily: 'monospace')),
        ]),
      ),
      Container(height: 1, color: _C.separator),
      // Graphique
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: series.every((s) => s.data.isEmpty)
              ? Center(child: Text('NO DATA',
                  style: TextStyle(color: _C.textDim, fontFamily: 'monospace', fontSize: 12)))
              : LineChart(_buildData()),
        ),
      ),
      // Légende
      Container(
        color: _C.panel,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: series.expand((s) {
          final st = _SeriesStat.of(s.data);
          return [
            Container(width: 12, height: 2, color: s.color),
            const SizedBox(width: 6),
            Text('min ${st.min.toStringAsFixed(1)}', style: TextStyle(color: _C.textSecondary, fontSize: 10, fontFamily: 'monospace')),
            const SizedBox(width: 12),
            Text('max ${st.max.toStringAsFixed(1)}', style: TextStyle(color: _C.textSecondary, fontSize: 10, fontFamily: 'monospace')),
            const SizedBox(width: 12),
            Text('avg ${st.avg.toStringAsFixed(1)}', style: TextStyle(color: _C.textSecondary, fontSize: 10, fontFamily: 'monospace')),
          ];
        }).toList()),
      ),
    ]),
  );

  LineChartData _buildData() {
    double lo = yMin ?? double.infinity, hi = yMax ?? double.negativeInfinity;
    for (final s in series) for (final v in s.data) {
      if (v < lo || lo == double.infinity)     lo = v;
      if (v > hi || hi == double.negativeInfinity) hi = v;
    }
    final pad = (hi - lo).abs() < 1e-6 ? 1.0 : (hi - lo) * .12;
    lo -= pad; hi += pad;

    return LineChartData(
      minY: lo, maxY: hi,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) => FlLine(color: _C.gridLine, strokeWidth: .5),
        getDrawingVerticalLine:   (_) => FlLine(color: _C.gridLine, strokeWidth: .5),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 44,
          getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
            style: TextStyle(color: _C.textDim, fontSize: 9, fontFamily: 'monospace')),
        )),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: _C.border, width: .5)),
      lineBarsData: series.map((s) => LineChartBarData(
        spots: s.data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
        isCurved: true, curveSmoothness: .25,
        color: s.color, barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [s.color.withOpacity(.2), s.color.withOpacity(0)])),
      )).toList(),
    );
  }
}

// ── Mobile STATUS tab ──────────────────────────────────────────────────────────
class _MobileStatusTab extends StatelessWidget {
  final TelemetryState   telem;
  final BeaconState      beacon;
  final List<AlertEntry> alerts;
  final List<String>     log;
  final AnimationController orbitCtrl;

  const _MobileStatusTab({
    required this.telem,   required this.beacon,
    required this.alerts,  required this.log,
    required this.orbitCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return ListView(
      padding: EdgeInsets.zero,
      // ClampingScrollPhysics évite les rebonds qui aggravent parentDataDirty
      physics: const ClampingScrollPhysics(),
      children: [

        // ── Orbital — LayoutBuilder donne des contraintes finies à CustomPaint
        Container(
          height: screenH * .27,
          color: _C.panel,
          child: Column(children: [
            _PH(
              title: 'Orbital Track',
              trailing: Text(
                'ALT ${telem.latest?.altitude.toStringAsFixed(1) ?? '--'} m',
                style: TextStyle(color: _C.accentTeal, fontSize: 11,
                  fontFamily: 'monospace', fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (ctx, box) =>
                AnimatedBuilder(
                  animation: orbitCtrl,
                  builder: (_, __) => CustomPaint(
                    // Taille explicite = pas de SizedBox.expand() dans un scroll
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _OrbitalPainter(progress: orbitCtrl.value),
                  ),
                ),
              ),
            ),
          ]),
        ),

        Container(height: 1, color: _C.separator),

        // ── Gauges ──────────────────────────────────────────────────────────
        SizedBox(
          height: 110,
          child: Row(children: [
            Expanded(child: _GaugePanel(
              title: 'Battery',
              value: telem.latest?.battery.toDouble() ?? 0,
              max: 100, unit: '%',
              color: _battColor(telem.latest?.battery.toDouble() ?? 0),
            )),
            Container(width: 1, color: _C.separator),
            Expanded(child: _SystemGauge(beacon: beacon)),
          ]),
        ),

        Container(height: 1, color: _C.separator),

        // ── Metrics — liste fixe en Column, pas de Expanded/ListView ────────
        Container(
          color: _C.panel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PH(title: 'Telemetry'),
              _mRow('temperature',
                telem.latest != null ? '${telem.latest!.temp.toStringAsFixed(2)} °C' : '—',
                _SeriesStat.of(telem.tempHistory)),
              Container(height: .5, color: _C.gridLine),
              _mRow('battery',
                telem.latest != null ? '${telem.latest!.battery} %' : '—',
                _SeriesStat.of(telem.batteryHistory)),
              Container(height: .5, color: _C.gridLine),
              _mRow('pressure',
                telem.latest != null ? '${telem.latest!.pressure} Pa' : '—',
                _SeriesStat.of(telem.pressureHistory)),
              Container(height: .5, color: _C.gridLine),
              _mRow('altitude',
                telem.latest != null ? '${telem.latest!.altitude.toStringAsFixed(2)} m' : '—',
                _SeriesStat.of(telem.altitudeHistory)),
            ],
          ),
        ),

        Container(height: 1, color: _C.separator),

        // ── Alerts — liste statique avec NeverScrollableScrollPhysics ───────
        Container(
          color: _C.panel,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _PH(
              title: 'Alerts',
              trailing: Text('${alerts.length}', style: TextStyle(
                color: alerts.isEmpty ? _C.accentGreen : _C.accentRed,
                fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('0 alerts', style: TextStyle(
                  color: _C.accentGreen, fontFamily: 'monospace', fontSize: 12)),
              )
            else
              // Limiter à 5 entrées visibles, NeverScrollable pour ne pas nester
              ...alerts.reversed.take(5).map((a) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(children: [
                  Icon(a.isThreshold ? Icons.thermostat : Icons.warning_amber_rounded,
                    color: _C.accentRed, size: 13),
                  const SizedBox(width: 6),
                  Expanded(child: Text(a.message,
                    style: TextStyle(color: _C.accentRed, fontSize: 10, fontFamily: 'monospace'),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                ]),
              )),
          ]),
        ),

        Container(height: 1, color: _C.separator),

        // ── Log — idem, pas de ListView imbriqué ────────────────────────────
        Container(
          color: _C.bg,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(width: 3, height: 12,
                  color: telem.historyMode ? _C.accentPurple : _C.accentBlue),
                const SizedBox(width: 6),
                Text(telem.historyMode ? 'HISTORY LOG' : 'EVENT LOG',
                  style: TextStyle(color: _C.textSecondary, fontSize: 10,
                    letterSpacing: 1.5, fontFamily: 'monospace')),
              ]),
              const SizedBox(height: 8),
              if (log.isEmpty)
                Text('Waiting for data...', style: TextStyle(
                  color: _C.textDim, fontSize: 10, fontFamily: 'monospace'))
              else
                ...log.reversed.take(8).map((e) {
                  final isA = e.contains('ALERT') || e.contains('⚠');
                  final isH = e.contains('HISTORY');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('›  $e',
                      style: TextStyle(
                        color: isA ? _C.accentRed : isH ? _C.accentPurple : _C.textDim,
                        fontSize: 10, fontFamily: 'monospace'),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  );
                }),
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  // Ligne de métrique pour le status tab mobile (pas de ListView imbriqué)
  Widget _mRow(String metric, String current, _SeriesStat stat) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(children: [
      Expanded(flex: 3, child: Text(metric,
        style: TextStyle(color: _C.textPrimary, fontSize: 11, fontFamily: 'monospace'))),
      Expanded(flex: 2, child: Text(current,
        style: TextStyle(color: _C.textPrimary, fontSize: 11, fontFamily: 'monospace'))),
      Expanded(flex: 2, child: Text(stat.min.toStringAsFixed(1),
        style: TextStyle(color: _C.textSecondary, fontSize: 11, fontFamily: 'monospace'))),
      Expanded(flex: 2, child: Text(stat.max.toStringAsFixed(1),
        style: TextStyle(color: _C.textSecondary, fontSize: 11, fontFamily: 'monospace'))),
    ]),
  );

  Color _battColor(double v) {
    if (v < 20) return _C.accentRed;
    if (v < 40) return _C.accentYellow;
    return _C.accentGreen;
  }
}

// ═════════════════════════════════════════════════
// TABLET LAYOUT  (600–900px, souvent paysage)
// 2 graphiques côte à côte + status scrollable en bas
// ═════════════════════════════════════════════════
class _TabletLayout extends StatelessWidget {
  final TelemetryState   telem;
  final BeaconState      beacon;
  final List<AlertEntry> alerts;
  final List<String>     log;
  final AnimationController orbitCtrl;
  final TabController    tabCtrl;

  const _TabletLayout({
    required this.telem,   required this.beacon,
    required this.alerts,  required this.log,
    required this.orbitCtrl, required this.tabCtrl,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    // Top: 2 graphiques côte à côte
    Expanded(
      flex: 3,
      child: TabBarView(controller: tabCtrl, children: [
        _side2('Temperature', '°C', telem.tempHistory, _C.accentOrange,
               'Battery Level', '%', telem.batteryHistory, _C.accentGreen, yMin2: 0, yMax2: 100),
        _side2('Pressure', 'Pa', telem.pressureHistory, _C.accentBlue,
               'Altitude', 'm',  telem.altitudeHistory, _C.accentTeal),
        _side2('Temperature', '°C', telem.tempHistory, _C.accentOrange,
               'Altitude', 'm',    telem.altitudeHistory, _C.accentTeal),
        _side2('Battery Level', '%', telem.batteryHistory, _C.accentGreen,
               'Pressure', 'Pa', telem.pressureHistory, _C.accentBlue, yMin1: 0, yMax1: 100),
        _statusRow(),
      ]),
    ),
    Container(height: 1, color: _C.separator),
    // Bottom: log compact
    SizedBox(
      height: 80,
      child: _LogPanel(log: log, historyMode: telem.historyMode),
    ),
  ]);

  Widget _side2(
    String t1, String u1, List<double> d1, Color c1,
    String t2, String u2, List<double> d2, Color c2, {
    double? yMin1, double? yMax1, double? yMin2, double? yMax2,
  }) => Row(children: [
    Expanded(child: _GrafanaChart(title: t1, unit: u1,
      series: [_Series(t1.toLowerCase(), d1, c1)], yMin: yMin1, yMax: yMax1)),
    Container(width: 1, color: _C.separator),
    Expanded(child: _GrafanaChart(title: t2, unit: u2,
      series: [_Series(t2.toLowerCase(), d2, c2)], yMin: yMin2, yMax: yMax2)),
  ]);

  Widget _statusRow() => Row(children: [
    Expanded(child: _GaugePanel(
      title: 'Battery',
      value: telem.latest?.battery.toDouble() ?? 0,
      max: 100, unit: '%',
      color: telem.latest != null && telem.latest!.battery < 20
          ? _C.accentRed : _C.accentGreen,
    )),
    Container(width: 1, color: _C.separator),
    Expanded(child: _SystemGauge(beacon: beacon)),
    Container(width: 1, color: _C.separator),
    Expanded(child: _AlertsPanel(alerts: alerts)),
  ]);
}

// ═════════════════════════════════════════════════
// DESKTOP LAYOUT  (≥ 900px)  — layout original 2/3 + 1/3
// ═════════════════════════════════════════════════
class _DesktopLayout extends StatelessWidget {
  final TelemetryState   telem;
  final BeaconState      beacon;
  final List<AlertEntry> alerts;
  final List<String>     log;
  final AnimationController orbitCtrl;

  const _DesktopLayout({
    required this.telem,   required this.beacon,
    required this.alerts,  required this.log,
    required this.orbitCtrl,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    const SidePanel(),
    Container(width: 1, color: _C.separator),
    Expanded(
      flex: 2,
      child: Column(children: [
        Expanded(flex: 3, child: Row(children: [
          Expanded(child: _GrafanaChart(title: 'Temperature', unit: '°C',
            series: [_Series('temp.', telem.tempHistory, _C.accentOrange)])),
          _vSep(),
          Expanded(child: _GrafanaChart(title: 'Battery Level', unit: '%',
            series: [_Series('battery', telem.batteryHistory, _C.accentGreen)],
            yMin: 0, yMax: 100)),
        ])),
        _hSep(),
        Expanded(flex: 3, child: Row(children: [
          Expanded(child: _GrafanaChart(title: 'Pressure (BMP180)', unit: 'Pa',
            series: [_Series('pressure', telem.pressureHistory, _C.accentBlue)])),
          _vSep(),
          Expanded(child: _GrafanaChart(title: 'Altitude (BMP180)', unit: 'm',
            series: [_Series('altitude', telem.altitudeHistory, _C.accentTeal)])),
        ])),
        _hSep(),
        Expanded(flex: 2, child: _LogPanel(log: log, historyMode: telem.historyMode)),
      ]),
    ),
    _vSep(),
    Expanded(
      flex: 1,
      child: Column(children: [
        Expanded(flex: 3, child: _MetricsTable(telem: telem)),
        _hSep(),
        Expanded(flex: 3, child: _OrbitalPanel(
          orbitCtrl: orbitCtrl,
          altitude:  telem.altitudeHistory.isEmpty ? 0 : telem.altitudeHistory.last,
        )),
        _hSep(),
        Expanded(flex: 2, child: Row(children: [
          Expanded(child: _GaugePanel(
            title: 'Battery',
            value: telem.latest?.battery.toDouble() ?? 0,
            max: 100, unit: '%',
            color: _battColor(telem.latest?.battery.toDouble() ?? 0),
          )),
          _vSep(),
          Expanded(child: _SystemGauge(beacon: beacon)),
        ])),
        _hSep(),
        Expanded(flex: 2, child: _AlertsPanel(alerts: alerts)),
      ]),
    ),
  ]);

  Color _battColor(double v) {
    if (v < 20) return _C.accentRed;
    if (v < 40) return _C.accentYellow;
    return _C.accentGreen;
  }

  Widget _vSep() => Container(width: 1, color: _C.separator);
  Widget _hSep() => Container(height: 1, color: _C.separator);
}

// ═════════════════════════════════════════════════
// ORBITAL PANEL
// ═════════════════════════════════════════════════
class _OrbitalPanel extends StatelessWidget {
  final AnimationController orbitCtrl;
  final double altitude;
  const _OrbitalPanel({required this.orbitCtrl, required this.altitude});

  @override
  Widget build(BuildContext context) => Container(
    color: _C.panel,
    child: Column(children: [
      _PH(title: 'Orbital Track',
        trailing: Text('ALT ${altitude.toStringAsFixed(1)} m',
          style: TextStyle(color: _C.accentTeal, fontFamily: 'monospace',
            fontSize: 11, fontWeight: FontWeight.w700))),
      Expanded(child: AnimatedBuilder(
        animation: orbitCtrl,
        builder: (_, __) => CustomPaint(
          painter: _OrbitalPainter(progress: orbitCtrl.value),
          child: const SizedBox.expand()),
      )),
    ]),
  );
}

class _OrbitalPainter extends CustomPainter {
  final double progress;
  const _OrbitalPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width/2, cy = size.height/2;
    final er = size.height*.26;

    canvas.drawCircle(Offset(cx, cy), er+10,
      Paint()..color=const Color(0xFF1A4A6E).withOpacity(.3)
             ..maskFilter=const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawCircle(Offset(cx, cy), er, Paint()..color=const Color(0xFF1B4F8A));
    final land = Paint()..color=const Color(0xFF2D7A3A);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx,cy), radius: er)));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx-er*.18,cy-er*.22), width: er*.9, height: er*.55), land);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx+er*.28,cy+er*.08), width: er*.65,height: er*.4),  land);
    canvas.restore();
    canvas.drawCircle(Offset(cx,cy), er,
      Paint()..color=const Color(0xFF5BB3FF).withOpacity(.16)
             ..style=PaintingStyle.stroke..strokeWidth=6);

    final rx=size.width*.43, ry=size.height*.36;
    canvas.drawOval(Rect.fromCenter(center:Offset(cx,cy), width:rx*2, height:ry*2),
      Paint()..color=_C.accentBlue.withOpacity(.2)..style=PaintingStyle.stroke..strokeWidth=.8);

    final tp=Path(); bool first=true;
    for (double t=progress-.2; t<=progress; t+=.004) {
      final a=t*2*pi, x=cx+rx*cos(a), y=cy+ry*sin(a);
      if(first){tp.moveTo(x,y);first=false;}else{tp.lineTo(x,y);}
    }
    canvas.drawPath(tp, Paint()
      ..shader=LinearGradient(colors:[_C.accentBlue.withOpacity(0),_C.accentBlue.withOpacity(.7)])
          .createShader(Rect.fromLTWH(cx-rx,cy-ry,rx*2,ry*2))
      ..style=PaintingStyle.stroke..strokeWidth=1.5..strokeCap=StrokeCap.round);

    final a=progress*2*pi, sx=cx+rx*cos(a), sy=cy+ry*sin(a);
    canvas.drawCircle(Offset(sx,sy), 9,
      Paint()..color=_C.accentBlue.withOpacity(.25)..maskFilter=const MaskFilter.blur(BlurStyle.normal,7));
    canvas.save();
    canvas.translate(sx,sy); canvas.rotate(a+pi/4);
    canvas.drawRect(const Rect.fromLTWH(-4,-4,8,8), Paint()..color=_C.textPrimary);
    canvas.drawRect(const Rect.fromLTWH(-13,-1.5,7,3), Paint()..color=const Color(0xFF3A6BBF));
    canvas.drawRect(const Rect.fromLTWH(6,-1.5,7,3),   Paint()..color=const Color(0xFF3A6BBF));
    canvas.restore();
  }

  @override bool shouldRepaint(_OrbitalPainter o) => o.progress != progress;
}

// ═════════════════════════════════════════════════
// SYSTEM GAUGE
// ═════════════════════════════════════════════════
class _SystemGauge extends StatelessWidget {
  final BeaconState beacon;
  const _SystemGauge({required this.beacon});

  @override
  Widget build(BuildContext context) => _GaugePanel(
    title: 'System',
    value: beacon.isEmergency ? 10 : beacon.isSafe ? 50 : beacon.isNominal ? 100 : 0,
    max: 100, unit: '',
    label: beacon.isEmergency ? 'CRITICAL' : beacon.isSafe ? 'SAFE MODE' :
           beacon.isNominal   ? 'NOMINAL'  : 'NO SIGNAL',
    color: beacon.isEmergency ? _C.accentRed    : beacon.isSafe ? _C.accentYellow :
           beacon.isNominal   ? _C.accentGreen  : _C.textDim,
  );
}

// ═════════════════════════════════════════════════
// GRAFANA CHART (desktop / tablet use)
// ═════════════════════════════════════════════════
class _GrafanaChart extends StatelessWidget {
  final String title, unit; final List<_Series> series;
  final double? yMin, yMax;
  const _GrafanaChart({required this.title, required this.series, required this.unit, this.yMin, this.yMax});

  @override
  Widget build(BuildContext context) => Container(
    color: _C.panel,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _PH(title: title),
      Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: series.every((s) => s.data.isEmpty)
            ? const _ND()
            : LineChart(_data()),
      )),
      _Legend(series: series, unit: unit),
    ]),
  );

  LineChartData _data() {
    double lo=yMin??double.infinity, hi=yMax??double.negativeInfinity;
    for (final s in series) for (final v in s.data) {
      if(v<lo||lo==double.infinity) lo=v;
      if(v>hi||hi==double.negativeInfinity) hi=v;
    }
    final pad=(hi-lo).abs()<1e-6?1.0:(hi-lo)*.12;
    lo-=pad; hi+=pad;
    return LineChartData(
      minY: lo, maxY: hi, clipData: const FlClipData.all(),
      gridData: FlGridData(show: true,
        getDrawingHorizontalLine: (_)=>FlLine(color:_C.gridLine,strokeWidth:.5),
        getDrawingVerticalLine:   (_)=>FlLine(color:_C.gridLine,strokeWidth:.5)),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles:true, reservedSize:40,
          getTitlesWidget:(v,_)=>Text(v.toStringAsFixed(1),
            style:TextStyle(color:_C.textDim,fontSize:9,fontFamily:'monospace')))),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles:false)),
        rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles:false)),
        topTitles:    AxisTitles(sideTitles: SideTitles(showTitles:false))),
      borderData: FlBorderData(show:true, border:Border.all(color:_C.border,width:.5)),
      lineBarsData: series.map((s) => LineChartBarData(
        spots: s.data.asMap().entries.map((e)=>FlSpot(e.key.toDouble(),e.value)).toList(),
        isCurved:true, curveSmoothness:.25, color:s.color, barWidth:1.5,
        dotData:const FlDotData(show:false),
        belowBarData: BarAreaData(show:true, gradient:LinearGradient(
          begin:Alignment.topCenter, end:Alignment.bottomCenter,
          colors:[s.color.withOpacity(.18),s.color.withOpacity(0)])),
      )).toList(),
    );
  }
}

class _Legend extends StatelessWidget {
  final List<_Series> series; final String unit;
  const _Legend({required this.series, required this.unit});
  @override
  Widget build(BuildContext context) => Container(
    color: _C.bg,
    padding: const EdgeInsets.symmetric(horizontal:8, vertical:4),
    child: Row(children: series.expand((s){
      final st=_SeriesStat.of(s.data);
      return [
        Container(width:10,height:2,color:s.color), const SizedBox(width:5),
        Text(s.label,style:TextStyle(color:s.color,fontSize:10,fontFamily:'monospace')),
        const SizedBox(width:8),
        _SL('min',st.min.toStringAsFixed(2),s.color),
        _SL('max',st.max.toStringAsFixed(2),s.color),
        _SL('avg',st.avg.toStringAsFixed(2),s.color),
        const SizedBox(width:12),
      ];
    }).toList()),
  );
}

class _SL extends StatelessWidget {
  final String k,v; final Color c;
  const _SL(this.k,this.v,this.c);
  @override
  Widget build(BuildContext ctx) => Padding(padding:const EdgeInsets.only(right:6),
    child:RichText(text:TextSpan(children:[
      TextSpan(text:'$k ',style:TextStyle(color:_C.textDim,fontSize:9,fontFamily:'monospace')),
      TextSpan(text:v,   style:TextStyle(color:c,fontSize:9,fontFamily:'monospace',fontWeight:FontWeight.w700)),
    ])));
}

// ═════════════════════════════════════════════════
// METRICS TABLE
// ═════════════════════════════════════════════════
class _MetricsTable extends StatelessWidget {
  final TelemetryState telem;
  const _MetricsTable({required this.telem});
  @override
  Widget build(BuildContext context) {
    final p = telem.latest;
    final rows = [
      _MR('temperature', p!=null?'${p.temp.toStringAsFixed(2)} °C':'—', _SeriesStat.of(telem.tempHistory)),
      _MR('battery',     p!=null?'${p.battery} %':'—',                  _SeriesStat.of(telem.batteryHistory)),
      _MR('pressure',    p!=null?'${p.pressure} Pa':'—',                 _SeriesStat.of(telem.pressureHistory)),
      _MR('altitude',    p!=null?'${p.altitude.toStringAsFixed(2)} m':'—',_SeriesStat.of(telem.altitudeHistory)),
    ];
    return Container(color:_C.panel, child:Column(children:[
      _PH(title:'Telemetry'),
      _TR(isHeader:true, metric:'Metric', current:'Current', mn:'Min', mx:'Max'),
      Container(height:.5, color:_C.border),
      Expanded(child:ListView.separated(
        itemCount:rows.length,
        separatorBuilder:(_,__)=>Container(height:.5,color:_C.gridLine),
        itemBuilder:(_,i)=>_TR(
          metric:rows[i].metric, current:rows[i].current,
          mn:rows[i].stat.min.toStringAsFixed(2),
          mx:rows[i].stat.max.toStringAsFixed(2)),
      )),
    ]));
  }
}

class _MR{final String metric,current;final _SeriesStat stat;_MR(this.metric,this.current,this.stat);}
class _TR extends StatelessWidget {
  final String metric,current,mn,mx;final bool isHeader;
  const _TR({required this.metric,required this.current,required this.mn,required this.mx,this.isHeader=false});
  @override
  Widget build(BuildContext ctx){
    final s=TextStyle(color:isHeader?_C.accentBlue:_C.textPrimary,fontSize:11,fontFamily:'monospace',fontWeight:isHeader?FontWeight.w700:FontWeight.normal);
    final d=s.copyWith(color:isHeader?_C.accentBlue:_C.textSecondary);
    return Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
      child:Row(children:[
        Expanded(flex:3,child:Text(metric, style:s)),
        Expanded(flex:2,child:Text(current,style:s)),
        Expanded(flex:2,child:Text(mn,     style:d)),
        Expanded(flex:2,child:Text(mx,     style:d)),
      ]));
  }
}

// ═════════════════════════════════════════════════
// GAUGE PANEL
// ═════════════════════════════════════════════════
class _GaugePanel extends StatelessWidget {
  final String title,unit;final double value,max;final Color color;final String? label;
  const _GaugePanel({required this.title,required this.value,required this.max,required this.unit,required this.color,this.label});
  @override
  Widget build(BuildContext ctx)=>Container(color:_C.panel,child:Column(children:[
    _PH(title:title),
    Expanded(child:Center(child:CustomPaint(
      size:const Size(100,60),
      painter:_GaugePainter(value:value,max:max,color:color),
      child:SizedBox(width:100,height:60,child:Align(alignment:const Alignment(0,1.1),
        child:Text(label??'${value.toStringAsFixed(0)}$unit',
          style:TextStyle(color:color,fontSize:12,fontWeight:FontWeight.w700,fontFamily:'monospace')))),
    ))),
  ]));
}

class _GaugePainter extends CustomPainter {
  final double value,max;final Color color;
  const _GaugePainter({required this.value,required this.max,required this.color});
  @override
  void paint(Canvas canvas,Size size){
    final cx=size.width/2,cy=size.height*.9,r=size.width/2-6;
    canvas.drawArc(Rect.fromCircle(center:Offset(cx,cy),radius:r),pi,pi,false,
      Paint()..color=_C.gridLine..strokeWidth=8..style=PaintingStyle.stroke..strokeCap=StrokeCap.round);
    final frac=(value/max).clamp(0.0,1.0);
    if(frac>0)canvas.drawArc(Rect.fromCircle(center:Offset(cx,cy),radius:r),pi,pi*frac,false,
      Paint()
        ..shader=SweepGradient(startAngle:pi,endAngle:pi+pi*frac,colors:[color.withOpacity(.4),color])
            .createShader(Rect.fromCircle(center:Offset(cx,cy),radius:r))
        ..strokeWidth=8..style=PaintingStyle.stroke..strokeCap=StrokeCap.round);
  }
  @override bool shouldRepaint(_GaugePainter o)=>o.value!=value||o.color!=color;
}

// ═════════════════════════════════════════════════
// ALERTS PANEL
// ═════════════════════════════════════════════════
class _AlertsPanel extends StatelessWidget {
  final List<AlertEntry> alerts;
  const _AlertsPanel({required this.alerts});
  @override
  Widget build(BuildContext ctx)=>Container(color:_C.panel,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    _PH(title:'Alerts',trailing:Text('${alerts.length}',style:TextStyle(
      color:alerts.isEmpty?_C.accentGreen:_C.accentRed,fontFamily:'monospace',fontSize:18,fontWeight:FontWeight.w700))),
    Expanded(child:alerts.isEmpty
      ?Center(child:Text('0 alerts',style:TextStyle(color:_C.accentGreen,fontFamily:'monospace',fontSize:12)))
      :ListView.builder(padding:const EdgeInsets.all(6),itemCount:alerts.length,itemBuilder:(_,i){
        final a=alerts.reversed.toList()[i];
        return Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Row(children:[
          Icon(a.isThreshold?Icons.thermostat:Icons.warning_amber_rounded,color:_C.accentRed,size:13),
          const SizedBox(width:6),
          Expanded(child:Text(a.message,style:TextStyle(color:_C.accentRed,fontSize:10,fontFamily:'monospace'))),
        ]));
      })),
  ]));
}

// ═════════════════════════════════════════════════
// LOG PANEL
// ═════════════════════════════════════════════════
class _LogPanel extends StatelessWidget {
  final List<String> log;final bool historyMode;
  const _LogPanel({required this.log,required this.historyMode});
  @override
  Widget build(BuildContext ctx)=>Container(color:_C.bg,padding:const EdgeInsets.all(8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[
      Container(width:3,height:12,color:historyMode?_C.accentPurple:_C.accentBlue),
      const SizedBox(width:6),
      Text(historyMode?'HISTORY LOG':'EVENT LOG',style:TextStyle(color:_C.textSecondary,fontSize:10,letterSpacing:1.5,fontFamily:'monospace')),
    ]),
    const SizedBox(height:4),
    Expanded(child:log.isEmpty
      ?Text('Waiting for data...',style:TextStyle(color:_C.textDim,fontSize:10,fontFamily:'monospace'))
      :ListView.builder(reverse:true,itemCount:log.length>20?20:log.length,itemBuilder:(_,i){
        final e=log.reversed.toList()[i];
        final isA=e.contains('ALERT')||e.contains('⚠');
        final isH=e.contains('HISTORY');
        return Padding(padding:const EdgeInsets.symmetric(vertical:1),
          child:Text('›  $e',style:TextStyle(
            color:isA?_C.accentRed:isH?_C.accentPurple:_C.textDim,
            fontSize:10,fontFamily:'monospace')));
      })),
  ]));
}

// ═════════════════════════════════════════════════
// SHARED
// ═════════════════════════════════════════════════
class _PH extends StatelessWidget {
  final String title;final Widget? trailing;
  const _PH({required this.title,this.trailing});
  @override
  Widget build(BuildContext ctx)=>Container(height:28,padding:const EdgeInsets.symmetric(horizontal:10),
    decoration:BoxDecoration(border:Border(bottom:BorderSide(color:_C.border,width:.5))),
    child:Row(children:[
      Text(title,style:TextStyle(color:_C.textSecondary,fontSize:11,fontWeight:FontWeight.w600,letterSpacing:.5)),
      const Spacer(),
      if(trailing!=null)trailing!,
    ]));
}

class _ND extends StatelessWidget {
  const _ND();
  @override
  Widget build(BuildContext ctx)=>Center(child:Text('NO DATA',
    style:TextStyle(color:_C.textDim,fontSize:11,fontFamily:'monospace',letterSpacing:2)));
}

class _Series{final String label;final List<double> data;final Color color;const _Series(this.label,this.data,this.color);}

class _SeriesStat{
  final double min,max,avg;
  const _SeriesStat(this.min,this.max,this.avg);
  static _SeriesStat of(List<double> d){
    if(d.isEmpty)return const _SeriesStat(0,0,0);
    return _SeriesStat(d.reduce((a,b)=>a<b?a:b),d.reduce((a,b)=>a>b?a:b),d.reduce((a,b)=>a+b)/d.length);
  }
}