import 'package:flutter/material.dart';
import '../models/wound_record.dart';
import '../models/app_theme.dart';
import '../services/storage_service.dart';
import 'camera_capture_screen.dart';
import 'trend_chart_screen.dart';

/// 首頁：傷口檔案列表（對應簡報「傷口檔案功能」）
class HomeScreen extends StatefulWidget {
  final StorageService storage;

  const HomeScreen({super.key, required this.storage});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<WoundProfile> _profiles = [];
  // 每個檔案最新一筆紀錄的燈號，從資料庫真實讀取；
  // 還沒拍過任何照片的檔案不會出現在這個 map 裡，畫面上就不顯示燈號 chip。
  final Map<String, HealingStatus> _latestStatus = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final profiles = await widget.storage.getProfiles();
    final statusMap = <String, HealingStatus>{};
    for (final profile in profiles) {
      final latest = await widget.storage.getLatestRecord(profile.id);
      if (latest != null) statusMap[profile.id] = latest.status;
    }
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _latestStatus
        ..clear()
        ..addAll(statusMap);
      _loading = false;
    });
  }

  Future<void> _createProfile() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('新增傷口檔案'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '例如：左腳跟壓瘡',
            filled: true,
            fillColor: AppTheme.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.blue),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('建立'),
          ),
        ],
      ),
    );
    if (label != null && label.trim().isNotEmpty) {
      await widget.storage.createProfile(label.trim());
      _loadProfiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('傷口追蹤', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? Center(
                  child: Text(
                    '尚未建立傷口檔案，點右下角新增',
                    style: TextStyle(color: AppTheme.inkSoft, fontSize: 13),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadProfiles,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _profiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final profile = _profiles[index];
                      final status = _latestStatus[profile.id];
                      final style = status == null ? null : StatusStyle.of(status);

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.line),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [AppTheme.tealPale, AppTheme.bluePale],
                                ),
                              ),
                              child: const Center(child: Text('🩹', style: TextStyle(fontSize: 20))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(profile.label,
                                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text(
                                    '建立於 ${profile.createdAt.toLocal().toString().split(' ').first}',
                                    style: AppTheme.mono(fontSize: 10.5, color: AppTheme.inkSoft),
                                  ),
                                ],
                              ),
                            ),
                            if (style != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: style.bg,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  '${style.emoji} ${style.label}',
                                  style: AppTheme.mono(fontSize: 10.5, fontWeight: FontWeight.w700, color: style.color),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            IconButton(
                              icon: Icon(Icons.show_chart, color: AppTheme.inkSoft, size: 20),
                              tooltip: '查看趨勢',
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TrendChartScreen(profile: profile, storage: widget.storage),
                                  ),
                                );
                                _loadProfiles();
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.camera_alt, color: AppTheme.blue, size: 20),
                              tooltip: '拍攝新紀錄',
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CameraCaptureScreen(profile: profile, storage: widget.storage),
                                  ),
                                );
                                _loadProfiles();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createProfile,
        child: const Icon(Icons.add),
      ),
    );
  }
}
