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

  @override
  Widget build(BuildContext context) {
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
                        titlesData: const FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
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
