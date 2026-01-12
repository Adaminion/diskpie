import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  File? _logFile;

  Future<File> get _file async {
    if (_logFile != null) return _logFile!;
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File(p.join(dir.path, 'diskpie_logs.txt'));
    return _logFile!;
  }

  Future<void> logInfo(String message) async {
    await _writeLog("INFO", message);
  }

  Future<void> logError(String message, [Object? error, StackTrace? stackTrace]) async {
    String fullMsg = message;
    if (error != null) fullMsg += " | Error: $error";
    if (stackTrace != null) fullMsg += "\nStackTrace: $stackTrace";
    await _writeLog("ERROR", fullMsg);
  }

  Future<void> _writeLog(String level, String message) async {
    try {
      final file = await _file;
      final timestamp = DateTime.now().toIso8601String();
      final line = "[$timestamp] [$level] $message\n";
      await file.writeAsString(line, mode: FileMode.append);
      // ignore: avoid_print
      print(line.trim()); // Also print to console
    } catch (e) {
      // ignore: avoid_print
      print("Failed to write to log: $e");
    }
  }

  Future<List<String>> getLogs() async {
    try {
      final file = await _file;
      if (!await file.exists()) return [];
      return await file.readAsLines();
    } catch (e) {
      return ["Error reading logs: $e"];
    }
  }

  Future<void> clearLogs() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        await file.writeAsString("");
      }
    } catch (e) {
      // ignore: avoid_print
      print("Error clearing logs: $e");
    }
  }
}
