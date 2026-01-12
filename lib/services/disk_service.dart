import 'dart:io';
import 'dart:convert';
import 'logger_service.dart';

class DiskUsage {
  final int totalSpace;
  final int freeSpace;

  DiskUsage({required this.totalSpace, required this.freeSpace});

  int get usedSpace => totalSpace - freeSpace;
  double get freePercentage => totalSpace > 0 ? (freeSpace / totalSpace) * 100 : 0;
  double get usedPercentage => totalSpace > 0 ? (usedSpace / totalSpace) * 100 : 0;
}

class DiskService {
  final LoggerService _logger = LoggerService();

  Future<DiskUsage?> getDiskUsage(String path) async {
    try {
      if (Platform.isWindows) {
        return _getWindowsDiskUsage(path);
      } 
      // Add other platforms if needed
      return null;
    } catch (e, stack) {
      await _logger.logError("Error getting disk usage for path: $path", e, stack);
      return null;
    }
  }

  Future<DiskUsage?> _getWindowsDiskUsage(String path) async {
    // Extract drive letter (e.g., "C:")
    final match = RegExp(r'^([a-zA-Z]:)').firstMatch(path);
    if (match == null) return null;
    final drive = match.group(1)!;

    // Use PowerShell instead of WMIC (WMIC is deprecated/optional)
    // Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq 'C:' } | Select-Object FreeSpace, Size
    try {
      final result = await Process.run('powershell', [
        '-Command',
        "Get-CimInstance Win32_LogicalDisk | Where-Object { \$_.DeviceID -eq '$drive' } | Select-Object -Property FreeSpace, Size | ConvertTo-Json"
      ]);

      if (result.exitCode != 0) {
        await _logger.logError("PowerShell failed: ${result.stderr}");
        return null;
      }

      // Parse JSON output
      // { "FreeSpace": 12345, "Size": 67890 }
      final Map<String, dynamic> data = jsonDecode(result.stdout.toString());
      
      final freeSpace = data['FreeSpace'] as int? ?? 0;
      final totalSize = data['Size'] as int? ?? 0;

      if (totalSize > 0) {
        return DiskUsage(totalSpace: totalSize, freeSpace: freeSpace);
      }
    } catch (e) {
      // Fallback or specific logging
       await _logger.logError("Failed to parse disk stats", e);
    }
    return null;
  }
}
