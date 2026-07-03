import 'dart:io';
import 'dart:math';

/// Formats a byte count the way the platform's file manager displays sizes,
/// so DiskPie's numbers match what the user sees there:
/// - macOS Finder and Linux file managers use decimal units (1 GB = 10^9 bytes)
/// - Windows Explorer uses binary units labeled with SI suffixes (1 GB = 2^30)
///
/// [base] overrides the platform default (for tests).
String formatBytes(int bytes, {int? base}) {
  if (bytes <= 0) return "0 B";
  final b = base ?? (Platform.isWindows ? 1024 : 1000);
  const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
  var i = (log(bytes) / log(b)).floor();
  if (i >= suffixes.length) i = suffixes.length - 1;
  return '${(bytes / pow(b, i)).toStringAsFixed(2)} ${suffixes[i]}';
}
