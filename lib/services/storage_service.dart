import '../models/wound_record.dart';

/// 本地儲存介面：面積、組織比例、燈號歷史紀錄存於本機資料庫，保護隱私。
/// 對應簡報 App 開發 Step 4「本地儲存」。
///
/// 目前先用記憶體實作讓 UI 可以先跑起來；
/// TODO: 換成 drift（見 pubspec.yaml），schema 大致對應
/// WoundProfile / WoundRecord 這兩個 model。
abstract class StorageService {
  Future<List<WoundProfile>> getProfiles();
  Future<WoundProfile> createProfile(String label);

  Future<List<WoundRecord>> getRecords(String woundProfileId);
  Future<WoundRecord?> getLatestRecord(String woundProfileId);
  Future<void> saveRecord(WoundRecord record);
}

class InMemoryStorageService implements StorageService {
  final List<WoundProfile> _profiles = [];
  final List<WoundRecord> _records = [];

  @override
  Future<List<WoundProfile>> getProfiles() async => List.unmodifiable(_profiles);

  @override
  Future<WoundProfile> createProfile(String label) async {
    final profile = WoundProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      createdAt: DateTime.now(),
    );
    _profiles.add(profile);
    return profile;
  }

  @override
  Future<List<WoundRecord>> getRecords(String woundProfileId) async {
    final list = _records.where((r) => r.woundProfileId == woundProfileId).toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return list;
  }

  @override
  Future<WoundRecord?> getLatestRecord(String woundProfileId) async {
    final records = await getRecords(woundProfileId);
    return records.isEmpty ? null : records.last;
  }

  @override
  Future<void> saveRecord(WoundRecord record) async {
    _records.add(record);
  }
}
