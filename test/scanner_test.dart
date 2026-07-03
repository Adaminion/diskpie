import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:diskpie/scanner.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('diskpie_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('sums sizes and counts files/folders correctly', () async {
    File('${tmp.path}/a.bin').writeAsBytesSync(List.filled(1000, 0));
    Directory('${tmp.path}/sub').createSync();
    File('${tmp.path}/sub/b.bin').writeAsBytesSync(List.filled(2500, 0));

    final result = await DiskScanner().scanDirectory(tmp.path);

    expect(result, isNotNull);
    expect(result!.rootNode.size, 3500);
    expect(result.fileCount, 2);
    expect(result.folderCount, 1);
    expect(result.skippedCount, 0);

    final sub = result.rootNode.children.firstWhere((c) => c.name == 'sub');
    expect(sub.size, 2500);
    expect(sub.isFile, false);
  });

  test('collapses more than 20 children into an Others node, preserving total size', () async {
    for (var i = 0; i < 25; i++) {
      File('${tmp.path}/f$i.bin').writeAsBytesSync(List.filled(100 + i, 0));
    }

    final result = await DiskScanner().scanDirectory(tmp.path);
    final children = result!.rootNode.children;

    expect(children.length, 21); // top 20 + Others
    final others = children.firstWhere((c) => c.name.startsWith('Others'));
    expect(others.name, 'Others (5 items)');

    final expectedTotal = List.generate(25, (i) => 100 + i).reduce((a, b) => a + b);
    expect(result.rootNode.size, expectedTotal);
  });

  test('does not follow symlinked directories (no cycles, no double counting)', () async {
    final real = Directory('${tmp.path}/real')..createSync();
    File('${real.path}/x.bin').writeAsBytesSync(List.filled(100, 0));
    await Link('${tmp.path}/loop').create(tmp.path); // points back at the root

    final result = await DiskScanner().scanDirectory(tmp.path);

    expect(result!.rootNode.size, 100);
    expect(result.fileCount, 1);
    expect(result.folderCount, 1);
  });

  test('throws ScanException for a missing directory', () async {
    expect(
      () => DiskScanner().scanDirectory('${tmp.path}/does_not_exist'),
      throwsA(isA<ScanException>()),
    );
  });

  test('cancel makes scanDirectory return null', () async {
    for (var d = 0; d < 20; d++) {
      final dir = Directory('${tmp.path}/d$d')..createSync();
      for (var i = 0; i < 200; i++) {
        File('${dir.path}/f$i').writeAsBytesSync(const [1]);
      }
    }

    final scanner = DiskScanner();
    // The first progress message arrives on the first scanned entity,
    // so cancelling from the callback aborts mid-scan deterministically.
    final result = await scanner.scanDirectory(
      tmp.path,
      onProgress: (_) => scanner.cancel(),
    );

    expect(result, isNull);
    expect(scanner.isScanning, false);
  });
}
