// Dev tool: scan a folder with DiskPie's scanner and print timing + totals.
// Usage: dart run tool/bench_scan.dart <path>
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:diskpie/format_bytes.dart';
import 'package:diskpie/scanner.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/bench_scan.dart <path>');
    exit(64);
  }
  final path = args.first;
  final sw = Stopwatch()..start();
  int lastCount = 0;

  final result = await DiskScanner().scanDirectory(path, onProgress: (p) {
    lastCount = p.itemCount;
  });
  sw.stop();

  if (result == null) {
    print('Scan cancelled');
    return;
  }

  final total = result.fileCount + result.folderCount;
  print('Scanned:   $path');
  print('Elapsed:   ${sw.elapsedMilliseconds} ms '
      '(${(total / (sw.elapsedMilliseconds / 1000)).round()} entries/sec)');
  print('Bytes:     ${result.rootNode.size}');
  print('Display:   ${formatBytes(result.rootNode.size, base: 1000)} (Finder-style) / '
      '${formatBytes(result.rootNode.size, base: 1024)} (Explorer-style)');
  print('Files:     ${result.fileCount}, folders: ${result.folderCount}, '
      'skipped: ${result.skippedCount}, last progress count: $lastCount');
}
