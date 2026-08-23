import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/wound_record.dart';
import 'storage_service.dart';

/// 真正寫入手機本機檔案系統的資料庫實作（SQLite，透過 sqflite）。
/// 不需要額外的 code generation 步驟，直接寫原生 SQL。
///
/// 資料庫檔案存放在 App 專屬的文件目錄，只有這個 App 自己讀得到，
/// 符合簡報「本地儲存，保護隱私」的設計。
class SqliteStorageService implements StorageService {
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'wound_app.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE wound_profiles (
            id TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE wound_records (
            id TEXT PRIMARY KEY,
            wound_profile_id TEXT NOT NULL,
            captured_at TEXT NOT NULL,
            image_path TEXT NOT NULL,
            area_cm2 REAL NOT NULL,
            area_change_pct REAL,
            tissue_json TEXT NOT NULL,
            status TEXT NOT NULL,
            infection_safety_net_triggered INTEGER NOT NULL,
            FOREIGN KEY (wound_profile_id) REFERENCES wound_profiles (id)
          )
        ''');
      },
    );
    return _db!;
  }

  @override
  Future<List<WoundProfile>> getProfiles() async {
    final db = await _database;
    final rows = await db.query('wound_profiles', orderBy: 'created_at DESC');
    return rows
        .map((r) => WoundProfile(
              id: r['id'] as String,
              label: r['label'] as String,
              createdAt: DateTime.parse(r['created_at'] as String),
            ))
        .toList();
  }

  @override
  Future<WoundProfile> createProfile(String label) async {
    final db = await _database;
    final profile = WoundProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      createdAt: DateTime.now(),
    );
    await db.insert('wound_profiles', {
      'id': profile.id,
      'label': profile.label,
      'created_at': profile.createdAt.toIso8601String(),
    });
    return profile;
  }

  @override
  Future<List<WoundRecord>> getRecords(String woundProfileId) async {
    final db = await _database;
    final rows = await db.query(
      'wound_records',
      where: 'wound_profile_id = ?',
      whereArgs: [woundProfileId],
      orderBy: 'captured_at ASC',
    );
    return rows.map(_rowToRecord).toList();
  }

  @override
  Future<WoundRecord?> getLatestRecord(String woundProfileId) async {
    final db = await _database;
    final rows = await db.query(
      'wound_records',
      where: 'wound_profile_id = ?',
      whereArgs: [woundProfileId],
      orderBy: 'captured_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToRecord(rows.first);
  }

  @override
  Future<void> saveRecord(WoundRecord record) async {
    final db = await _database;
    await db.insert('wound_records', {
      'id': record.id,
      'wound_profile_id': record.woundProfileId,
      'captured_at': record.capturedAt.toIso8601String(),
      'image_path': record.imagePath,
      'area_cm2': record.areaCm2,
      'area_change_pct': record.areaChangePct,
      'tissue_json': jsonEncode({
        'red': record.tissue.redGranulationPct,
        'yellow': record.tissue.yellowSloughPct,
        'black': record.tissue.blackNecrosisPct,
        'yellowGreen': record.tissue.yellowGreenPusPct,
      }),
      'status': record.status.name,
      'infection_safety_net_triggered': record.infectionSafetyNetTriggered ? 1 : 0,
    });
  }

  WoundRecord _rowToRecord(Map<String, Object?> r) {
    final tissueMap = jsonDecode(r['tissue_json'] as String) as Map<String, dynamic>;
    return WoundRecord(
      id: r['id'] as String,
      woundProfileId: r['wound_profile_id'] as String,
      capturedAt: DateTime.parse(r['captured_at'] as String),
      imagePath: r['image_path'] as String,
      areaCm2: r['area_cm2'] as double,
      areaChangePct: r['area_change_pct'] as double?,
      tissue: TissueComposition(
        redGranulationPct: (tissueMap['red'] as num).toDouble(),
        yellowSloughPct: (tissueMap['yellow'] as num).toDouble(),
        blackNecrosisPct: (tissueMap['black'] as num).toDouble(),
        yellowGreenPusPct: (tissueMap['yellowGreen'] as num).toDouble(),
      ),
      status: HealingStatus.values.byName(r['status'] as String),
      infectionSafetyNetTriggered: (r['infection_safety_net_triggered'] as int) == 1,
    );
  }
}
