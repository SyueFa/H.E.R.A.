import 'package:flutter/material.dart';
import 'models/app_theme.dart';
import 'screens/root_shell.dart';

void main() {
  runApp(const WoundApp());
}

class WoundApp extends StatelessWidget {
  const WoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '邊緣運算傷口辨識系統',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      home: const RootShell(),
    );
  }
}
