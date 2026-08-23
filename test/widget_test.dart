// 基本 smoke test：確認 App 能正常建置起來，不會一啟動就崩潰。
//
// 這裡刻意只用 tester.pump() 而不是 pumpAndSettle()：App 啟動後
// RootShell → HomeScreen 會去讀本機 SQLite 資料庫、CameraCaptureScreen
// 會嘗試初始化相機，這些非同步操作在純 widget test 環境下不會真的
// 完成（沒有真實裝置的相機/檔案系統），用 pumpAndSettle() 會卡住等到
// timeout。單次 pump() 只確認第一幀能正常畫出來即可。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hera/main.dart';

void main() {
  testWidgets('App 啟動時應能正常建置畫面', (WidgetTester tester) async {
    await tester.pumpWidget(const WoundApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}