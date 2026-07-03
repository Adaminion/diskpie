import 'package:flutter_test/flutter_test.dart';
import 'package:diskpie/format_bytes.dart';

void main() {
  test('decimal base matches Finder-style display', () {
    expect(formatBytes(47560117712, base: 1000), '47.56 GB');
    expect(formatBytes(4450953842655, base: 1000), '4.45 TB');
    expect(formatBytes(999, base: 1000), '999.00 B');
  });

  test('binary base matches Explorer-style display', () {
    expect(formatBytes(47560117712, base: 1024), '44.29 GB');
    expect(formatBytes(1048576, base: 1024), '1.00 MB');
  });

  test('zero and negative byte counts', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(-5), '0 B');
  });
}
