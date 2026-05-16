import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../app_colors.dart';
import 'mission_control_page.dart';

typedef _C = AppColors;

const String _mqttHost = '9a49bca53d684a54b7315926c0d27f88.s1.eu.hivemq.cloud';
const int    _mqttPort = 8883;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool    _loading = false;
  bool    _obscure = true;
  String? _error;

  late AnimationController _orbitCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _orbitCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _fadeCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim  = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _orbitCtrl.dispose(); _fadeCtrl.dispose();
    _userCtrl.dispose();  _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() { _loading = true; _error = null; });

    final client = MqttServerClient(
      _mqttHost, 'flutter_${DateTime.now().millisecondsSinceEpoch}');
    client.port            = _mqttPort;
    client.secure          = true;
    client.keepAlivePeriod = 20;
    client.logging(on: false);
    client.connectionMessage = MqttConnectMessage()
        .authenticateAs(_userCtrl.text.trim(), _passCtrl.text)
        .withClientIdentifier('flutter_client')
        .startClean();

    try {
      await client.connect();
      if (client.connectionStatus!.state == MqttConnectionState.connected) {
        if (!mounted) return;
        Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => MissionControlPage(client: client)));
      } else {
        setState(() => _error = 'Connection failed: ${client.connectionStatus}');
        client.disconnect();
      }
    } catch (e) {
      setState(() => _error = 'Connection error: $e');
      client.disconnect();
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(children: [
        const Positioned.fill(child: _GridBackground()),
        Positioned(
          top: 0, left: 0, right: 0,
          height: MediaQuery.of(context).size.height * .55,
          child: AnimatedBuilder(
            animation: _orbitCtrl,
            builder: (_, __) => CustomPaint(
              painter: _LoginOrbitalPainter(progress: _orbitCtrl.value)),
          ),
        ),
        Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: _LoginCard(
              userCtrl: _userCtrl, passCtrl: _passCtrl,
              loading: _loading, obscure: _obscure, error: _error,
              onToggleObscure: () => setState(() => _obscure = !_obscure),
              onConnect: _connect,
            ),
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════
// GRID BACKGROUND
// ═════════════════════════════════════════════════
class _GridBackground extends StatelessWidget {
  const _GridBackground();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _GridPainter(), child: const SizedBox.expand());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.gridLine..strokeWidth = .5;
    for (double x = 0; x < size.width;  x += 32) canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    for (double y = 0; y < size.height; y += 32) canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }
  @override bool shouldRepaint(_) => false;
}

// ═════════════════════════════════════════════════
// LOGIN ORBITAL PAINTER
// ═════════════════════════════════════════════════
class _LoginOrbitalPainter extends CustomPainter {
  final double progress;
  const _LoginOrbitalPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final earthR = size.height * .22;

    canvas.drawCircle(Offset(cx, cy), earthR + 14,
      Paint()..color = const Color(0xFF1A4A6E).withOpacity(.22)
             ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    canvas.drawCircle(Offset(cx, cy), earthR, Paint()..color = const Color(0xFF1B4F8A));

    final land = Paint()..color = const Color(0xFF2D7A3A);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: earthR)));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - earthR * .2,  cy - earthR * .2),  width: earthR * .85, height: earthR * .5),  land);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + earthR * .28, cy + earthR * .1),  width: earthR * .6,  height: earthR * .38), land);
    canvas.restore();
    canvas.drawCircle(Offset(cx, cy), earthR,
      Paint()..color = const Color(0xFF5BB3FF).withOpacity(.14)
             ..style = PaintingStyle.stroke..strokeWidth = 7);

    final rx = size.width * .42, ry = size.height * .38;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      Paint()..color = AppColors.accentBlue.withOpacity(.14)
             ..style = PaintingStyle.stroke..strokeWidth = .8);

    final path = Path(); bool first = true;
    for (double t = progress - .18; t <= progress; t += 0.004) {
      final a = t * 2 * pi, x = cx + rx * cos(a), y = cy + ry * sin(a);
      if (first) { path.moveTo(x, y); first = false; } else path.lineTo(x, y);
    }
    canvas.drawPath(path,
      Paint()
        ..shader = LinearGradient(colors: [AppColors.accentBlue.withOpacity(0), AppColors.accentBlue.withOpacity(.55)])
            .createShader(Rect.fromLTWH(cx - rx, cy - ry, rx * 2, ry * 2))
        ..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round);

    final angle = progress * 2 * pi;
    final sx = cx + rx * cos(angle), sy = cy + ry * sin(angle);
    canvas.drawCircle(Offset(sx, sy), 9,
      Paint()..color = AppColors.accentBlue.withOpacity(.22)
             ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.save();
    canvas.translate(sx, sy); canvas.rotate(angle + pi / 4);
    canvas.drawRect(const Rect.fromLTWH(-4, -4, 8, 8),  Paint()..color = AppColors.textPrimary);
    canvas.drawRect(const Rect.fromLTWH(-13, -1.5, 7, 3), Paint()..color = const Color(0xFF3A6BBF));
    canvas.drawRect(const Rect.fromLTWH(6, -1.5, 7, 3),   Paint()..color = const Color(0xFF3A6BBF));
    canvas.restore();
  }

  @override bool shouldRepaint(_LoginOrbitalPainter o) => o.progress != progress;
}

// ═════════════════════════════════════════════════
// LOGIN CARD
// ═════════════════════════════════════════════════
class _LoginCard extends StatelessWidget {
  final TextEditingController userCtrl, passCtrl;
  final bool loading, obscure; final String? error;
  final VoidCallback onToggleObscure, onConnect;

  const _LoginCard({
    required this.userCtrl,  required this.passCtrl,
    required this.loading,   required this.obscure,
    required this.error,     required this.onToggleObscure,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: _C.panel,
        border: Border.all(color: _C.border),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: _C.accentBlue.withOpacity(.06),
          blurRadius: 40, spreadRadius: 4)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _C.header,
            border: Border(bottom: BorderSide(color: _C.border)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          child: Row(children: [
            Icon(Icons.satellite_alt, color: _C.accentBlue, size: 18),
            const SizedBox(width: 10),
            Text('GROUND STATION  /  AUTHENTICATE',
              style: TextStyle(color: _C.textSecondary, fontSize: 11,
                letterSpacing: 1.8, fontFamily: 'monospace')),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('CUBESAT\nMISSION CONTROL',
              style: TextStyle(color: _C.textPrimary, fontSize: 22,
                fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.2, fontFamily: 'monospace')),
            const SizedBox(height: 6),
            Text('MQTT secure connection required',
              style: TextStyle(color: _C.textDim, fontSize: 10,
                letterSpacing: 1.2, fontFamily: 'monospace')),
            const SizedBox(height: 28),

            _GrafanaField(controller: userCtrl, label: 'MQTT USERNAME', icon: Icons.person_outline),
            const SizedBox(height: 14),
            _GrafanaField(
              controller: passCtrl, label: 'MQTT PASSWORD',
              icon: Icons.lock_outline, obscure: obscure,
              suffix: IconButton(
                icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: _C.textDim, size: 16),
                onPressed: onToggleObscure,
              ),
            ),
            const SizedBox(height: 20),

            if (error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _C.accentRed.withOpacity(.08),
                  border: Border.all(color: _C.accentRed.withOpacity(.4)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: _C.accentRed, size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error!,
                    style: TextStyle(color: _C.accentRed, fontSize: 10, fontFamily: 'monospace'))),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: loading ? null : onConnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.accentBlue,
                  disabledBackgroundColor: _C.accentBlue.withOpacity(.4),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                ),
                child: loading
                    ? SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white.withOpacity(.8)))
                    : Text('ESTABLISH CONNECTION',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          letterSpacing: 2, fontFamily: 'monospace')),
              ),
            ),

            const SizedBox(height: 20),
            Row(children: [
              Container(width: 6, height: 6,
                decoration: BoxDecoration(
                  color: loading ? _C.accentBlue : _C.accentGreen,
                  shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(loading ? 'CONNECTING...' : 'READY',
                style: TextStyle(
                  color: loading ? _C.accentBlue : _C.accentGreen,
                  fontSize: 10, fontFamily: 'monospace', letterSpacing: 1.5)),
              const Spacer(),
              Text('TLS 8883', style: TextStyle(color: _C.textDim, fontSize: 9, fontFamily: 'monospace')),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════
// GRAFANA TEXT FIELD
// ═════════════════════════════════════════════════
class _GrafanaField extends StatelessWidget {
  final TextEditingController controller;
  final String label; final IconData icon;
  final bool obscure; final Widget? suffix;

  const _GrafanaField({
    required this.controller, required this.label, required this.icon,
    this.obscure = false, this.suffix,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: _C.textDim, fontSize: 9, letterSpacing: 1.5, fontFamily: 'monospace')),
      const SizedBox(height: 6),
      TextField(
        controller: controller, obscureText: obscure,
        style: TextStyle(color: _C.textPrimary, fontSize: 13, fontFamily: 'monospace'),
        decoration: InputDecoration(
          filled: true, fillColor: _C.bg,
          prefixIcon: Icon(icon, color: _C.textDim, size: 16),
          suffixIcon: suffix,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: _C.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: _C.accentBlue)),
        ),
      ),
    ],
  );
}