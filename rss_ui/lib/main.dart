import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'screens/home_page.dart';
import 'theme/app_colors.dart';
import 'web/web_gate.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'W.O.F',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ),
        splashColor: AppColors.accent.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
      ),
      // Platforma göre ayrı arayüz: web (PC) için sol menülü düzen,
      // mobil uygulamalar için alt menülü düzen.
      home: kIsWeb ? const WebGate() : const HomePage(),
    );
  }
}
