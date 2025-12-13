import 'package:shared_preferences/shared_preferences.dart';

class RecentScansService {
  static const String _keyRecentScans = 'recent_scans';
  static const int _maxRecents = 10;

  Future<List<String>> getRecentScans() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyRecentScans) ?? [];
  }

  Future<void> addRecentScan(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final recents = prefs.getStringList(_keyRecentScans) ?? [];

    // Remove if already exists to move it to the top
    recents.remove(path);
    
    // Add to front
    recents.insert(0, path);

    // Trim
    if (recents.length > _maxRecents) {
      recents.removeRange(_maxRecents, recents.length);
    }

    await prefs.setStringList(_keyRecentScans, recents);
  }

  Future<void> clearRecents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRecentScans);
  }
}
