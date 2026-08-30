import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/wound_record.dart';
import '../models/app_theme.dart';
import '../services/storage_service.dart';

/// App 內以折線圖呈現面積隨時間變化（簡報「趨勢顯示」功能）
class TrendChartScreen extends StatefulWidget {
  final WoundProfile profile;
  final StorageService storage;

  const TrendChartScreen({
    super.key,
    required this.profile,
    required this.storage,
  });

  @override
  State<TrendChartScreen> createState() => _TrendChartScreenState();
}

class _TrendChartScreenState extends State<TrendChartScreen> {
  List<WoundRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await widget.storage.getRecords(widget.profile.id);
    setState(() => _records = records);
  }

  /// fl_chart 在資料範圍很窄時（例如只有 3.96~4.66 這種不到 1 的區間），
  /// 自動計算的刻度間距容易跟最上面的資料點數字擠在一起重疊。這裡改成
  /// 自己算一個留有邊界緩衝、間距均勻、刻度落在「好看數字」（0.1／0.2／
  /// 0.5／1／2／5 的倍數）上的範圍，而不是任意小數。
  ({double minY, double maxY, double interval}) _computeYAxisRange() {
    if (_records.isEmpty) return (minY: 0, maxY: 10, interval: 2);
    final areas = _records.map((r) => r.areaCm2).toList();
    final minArea = areas.reduce((a, b) => a < b ? a : b);
    final maxArea = areas.reduce((a, b) => a > b ? a : b);
    final range = maxArea - minArea;
    final padding = range < 1 ? 0.5 : range * 0.15;
    final rawMin = (minArea - padding).clamp(0.0, double.infinity);
    final rawMax = maxArea + padding;

    // 從常見的「好看」間距裡，挑一個能把 (rawMax - rawMin) 切成
    // 4~6 段的最小值，刻度數字才會是 0.1 / 0.2 / 0.5 / 1 / 2 / 5 這種
    // 容易讀的倍數，而不是像 0.256 這種除出來的奇怪小數。
    // 注意：全部寫成 1.0、2.0 這種明確的 double 字面量，避免 Dart
    // 把整數項推斷成 int，導致整個 list 變成 List<num> 而型別不合。
    const niceSteps = <double>[0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0];
    final span = rawMax - rawMin;
    final double interval = niceSteps.firstWhere(
      (step) => span / step <= 6,
      orElse: () => niceSteps.last,
    );

    // 用選定的 interval 把上下限對齊到該倍數的整數格上，
    // 這樣軸線上顯示的每一個數字都會是乾淨的刻度值。
    // floor()/ceil() 回傳 int，乘回 interval 後要轉回 double。
    final double minY = ((rawMin / interval).floor() * interval).toDouble();
    final double maxY = ((rawMax / interval).ceil() * interval).toDouble();

    return (minY: minY, maxY: maxY, interval: interval);
  }

  @override
  Widget build(BuildContext context) {
    final yAxis = _computeYAxisRange();
    return Scaffold(
      appBar: AppBar(title: Text('${widget.profile.label} — 趨勢')),
      body: _records.isEmpty
          ? const Center(child: Text('尚無紀錄，先去拍照吧'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: LineChart(
                      LineChartData(
                        minY: yAxis.minY,
                        maxY: yAxis.maxY,
                        // 原本只關掉底部軸，但沒關掉頂部軸，fl_chart 對
                        // 未設定的軸會套用預設的 0~1 正規化刻度，這正是
                        // 畫面上方出現「0, 0.1, 0.2 ... 1」這排奇怪數字
                        // 的原因。這裡把頂部、右側都明確關閉，底部改成
                        // 顯示每筆紀錄實際拍攝的日期。
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                              interval: yAxis.interval,
                              getTitlesWidget: (value, meta) {
                                // 只在算好的刻度上顯示文字，避免自動產生
                                // 額外的密集刻度線跟資料點的數字重疊。
                                return Text(
                                  value.toStringAsFixed(1),
                                  style: AppTheme.mono(fontSize: 10, color: AppTheme.inkSoft),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= _records.length) {
                                  return const SizedBox.shrink();
                                }
                                final date = _records[index].capturedAt;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    '${date.month}/${date.day}',
                                    style: AppTheme.mono(fontSize: 9, color: AppTheme.inkSoft),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i < _records.length; i++)
                                FlSpot(i.toDouble(), _records[i].areaCm2),
                            ],
                            isCurved: true,
                            color: Theme.of(context).colorScheme.primary,
                            dotData: const FlDotData(show: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      final r = _records[_records.length - 1 - index];
                      final style = StatusStyle.of(r.status);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.line),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(color: style.bg, shape: BoxShape.circle),
                              child: Center(child: Text(style.emoji, style: const TextStyle(fontSize: 15))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${r.areaCm2.toStringAsFixed(2)} cm²',
                                      style: AppTheme.mono(fontSize: 14, fontWeight: FontWeight.w700)),
                                  Text(
                                    r.capturedAt.toLocal().toString().split('.').first,
                                    style: AppTheme.mono(fontSize: 10, color: AppTheme.inkSoft),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            _RecordThumbnail(imagePath: r.imagePath),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

/// 歷史紀錄列表用的小縮圖。因為模擬拍照（沒有相機時的測試路徑）
/// 產生的紀錄，imagePath 是假路徑、實際檔案不存在，這裡用
/// existsSync() 判斷，檔案不存在時顯示灰底相機圖示佔位，
/// 避免 Image.file 對不存在的檔案拋出例外把整個畫面弄壞。
class _RecordThumbnail extends StatelessWidget {
  final String imagePath;
  const _RecordThumbnail({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
    final exists = !imagePath.startsWith('mock_') && file.existsSync();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        color: AppTheme.bg,
        child: exists
            ? Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image_outlined,
                  size: 18,
                  color: AppTheme.inkSoft,
                ),
              )
            : const Icon(Icons.image_outlined, size: 18, color: AppTheme.inkSoft),
      ),
    );
  }
}