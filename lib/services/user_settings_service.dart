import 'package:shared_preferences/shared_preferences.dart';

/// 本機端的「使用者資料」——這個 App 走離線隱私優先設計，
/// 沒有伺服器帳號系統，這裡存的只是裝置本機的顯示名稱、通知開關等
/// 個人化設定，不會上傳到任何地方。
class UserSettingsService {
  static const _keyDisplayName = 'user_display_name';
  static const _keyNotificationsEnabled = 'notifications_enabled';

  Future<String> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDisplayName) ?? '';
  }

  Future<void> setDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDisplayName, name);
  }

  Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotificationsEnabled) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationsEnabled, enabled);
  }
}
