import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../services/user_settings_service.dart';

/// 「我的」頁面：本機端的個人化設定（不是雲端帳號系統，
/// 這個 App 走離線優先設計，所有資料只存在裝置本機）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = UserSettingsService();
  final _nameController = TextEditingController();
  bool _notificationsEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await _settings.getDisplayName();
    final notif = await _settings.getNotificationsEnabled();
    setState(() {
      _nameController.text = name;
      _notificationsEnabled = notif;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('顯示名稱', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: '例如：小明（僅顯示於本機，不會上傳）',
                          filled: true,
                          fillColor: AppTheme.bg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: _settings.setDisplayName,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: SwitchListTile(
                    title: const Text('就醫提醒推播'),
                    subtitle: const Text(
                      '連續判定為觀察或惡化時提醒回診',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
                    ),
                    activeThumbColor: AppTheme.blue,
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      setState(() => _notificationsEnabled = value);
                      _settings.setNotificationsEnabled(value);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '關於',
                    style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('邊緣運算傷口辨識系統', style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 6),
                      Text(
                        '這是一個概念驗證（proof of concept）應用，'
                        '判讀邏輯參考 PUSH Tool 概念自行設計，非官方醫療量表。'
                        '所有資料僅儲存於本機裝置，不會上傳雲端。',
                        style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
