import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // généré par flutterfire configure
import 'app_colors.dart';
import 'pages/login_page.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientations autorisées
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Style barre système
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:                     Colors.transparent,
    statusBarIconBrightness:            Brightness.light,
    systemNavigationBarColor:           AppColors.bg,
    systemNavigationBarIconBrightness:  Brightness.light,
  ));

  // Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ProviderScope(child: OrionApp()));
}

class OrionApp extends StatelessWidget {
  const OrionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ── Nom de l'application ──────────────────────────────────────
      title: 'ORION Ground Station',
      debugShowCheckedModeBanner: false,

      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary:   AppColors.accentBlue,
          secondary: AppColors.accentGreen,
          surface:   AppColors.panel,
        ),
        splashColor:    AppColors.accentBlue.withOpacity(.08),
        highlightColor: AppColors.accentBlue.withOpacity(.04),
      ),
      home: const LoginPage(),
    );
  }
}