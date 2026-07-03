import 'dart:io';
import 'dart:convert';
import 'logger_service.dart';

class DiskUsage {
  final int totalSpace;
  final int freeSpace;

  /// The volume root this usage belongs to (e.g. "/Volumes/MyDisk" or "C:").
  /// Lets callers tell whether a scanned path covers the whole volume.
  final String? mountedOn;

  DiskUsage({required this.totalSpace, required this.freeSpace, this.mountedOn});

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
      if (Platform.isMacOS || Platform.isLinux) {
        return _getUnixDiskUsage(path);
      }
      return null;
    } catch (e, stack) {
      await _logger.logError("Error getting disk usage for path: $path", e, stack);
      return null;
    }
  }

  Future<DiskUsage?> _getUnixDiskUsage(String path) async {
    // POSIX-format df: Filesystem 1024-blocks Used Available Capacity Mounted on
    final result = await Process.run('df', ['-P', '-k', path]);
    if (result.exitCode != 0) {
      await _logger.logError("df failed for $path: ${result.stderr}");
      return null;
    }

    final lines = result.stdout.toString().trim().split('\n');
    if (lines.length < 2) return null;
    final tokens = lines.last.split(RegExp(r'\s+'));
    if (tokens.length < 6) return null;

    final blocks = int.tryParse(tokens[1]);
    final available = int.tryParse(tokens[3]);
    if (blocks == null || available == null) return null;

    // The mount point is everything after the Capacity column ("41%") —
    // rejoin because volume names may contain spaces ("/Volumes/NO NAME").
    final capacityIndex = tokens.indexWhere((t) => t.endsWith('%'));
    final mountedOn = capacityIndex >= 0 && capacityIndex + 1 < tokens.length
        ? tokens.sublist(capacityIndex + 1).join(' ')
        : null;

    return DiskUsage(
      totalSpace: blocks * 1024,
      freeSpace: available * 1024,
      mountedOn: mountedOn,
    );
  }

  Future<DiskUsage?> _getWindowsDiskUsage(String path) async {
    // Extract drive letter (e.g., "C:")
    final match = RegExp(r'^([a-zA-Z]:)').firstMatch(path);
    if (match == null) return null;
    final drive = match.group(1)!;

    // Use PowerShell instead of WMIC (WMIC is deprecated/optional)
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
        return DiskUsage(totalSpace: totalSize, freeSpace: freeSpace, mountedOn: drive);
      }
    } catch (e) {
      // Fallback or specific logging
      await _logger.logError("Failed to parse disk stats", e);
    }
    return null;
  }
}
