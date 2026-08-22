import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../services/storage_service.dart';
import '../services/sqlite_storage_service.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// App 的根層外殼：在這裡建立「只有一份」的 StorageService 實例，
/// 往下傳給各個分頁共用，並提供底部導覽在「檔案」「我的」之間切換。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  // 真正寫入手機檔案系統的 SQLite 資料庫，取代先前的記憶體 stub，
  // 關掉 App 資料不會消失。
  final StorageService _storage = SqliteStorageService();
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(storage: _storage),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: AppTheme.card,
        indicatorColor: AppTheme.bluePale,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: '檔案'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
