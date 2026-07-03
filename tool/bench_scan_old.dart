// Dev tool: the pre-rewrite scan algorithm (async IO on the calling isolate,
// canonical-path cycle detection), kept only to benchmark against the new one.
// Usage: dart run tool/bench_scan_old.dart <path>
// ignore_for_file: avoid_print
import 'dart:io';

Future<void> main(List<String> args) async {
  final path = args.first;
  final visitedPaths = <String>{};
  int files = 0, folders = 0;

  Future<int> scanRecursive(String currentPath) async {
    String canonicalPath;
    try {
      canonicalPath = Directory(currentPath).resolveSymbolicLinksSync();
    } catch (e) {
      canonicalPath = currentPath;
    }
    if (visitedPaths.contains(canonicalPath)) return 0;
    visitedPaths.add(canonicalPath);

    int totalSize = 0;
    try {
      await for (final entity in Directory(currentPath).list(followLinks: false)) {
        try {
          if (entity is File) {
            files++;
            final stat = await entity.stat();
            totalSize += stat.size;
          } else if (entity is Directory) {
            if (await FileSystemEntity.isLink(entity.path)) continue;
            folders++;
            totalSize += await scanRecursive(entity.path);
          }
        } catch (e) {
          // skip
        }
      }
    } catch (e) {
      // skip
    }
    return totalSize;
  }

  final sw = Stopwatch()..start();
  final total = await scanRecursive(path);
  sw.stop();
  print('OLD algorithm — Elapsed: ${sw.elapsedMilliseconds} ms, '
      'bytes: $total, files: $files, folders: $folders '
      '(${((files + folders) / (sw.elapsedMilliseconds / 1000)).round()} entries/sec)');
}
