import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/snapshot.dart';
import 'package:path/path.dart' as p;

class SnapshotService {
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final snapshotDir = Directory(p.join(directory.path, 'diskpie_snapshots'));
    if (!await snapshotDir.exists()) {
      await snapshotDir.create(recursive: true);
    }
    return snapshotDir.path;
  }

  Future<void> saveSnapshot(Snapshot snapshot) async {
    final path = await _localPath;
    final file = File(p.join(path, '${snapshot.id}.json'));
    // Pretty print JSON
    final jsonString = const JsonEncoder.withIndent('  ').convert(snapshot.toJson());
    await file.writeAsString(jsonString);
  }

  Future<List<Snapshot>> loadAllSnapshots() async {
    final path = await _localPath;
    final dir = Directory(path);
    List<Snapshot> snapshots = [];

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content);
            snapshots.add(Snapshot.fromJson(json));
          } catch (e) {
            // debugPrint("Error loading snapshot ${entity.path}: $e");
          }
        }
      }
    }
    // Sort by date descending
    snapshots.sort((a, b) => b.scanDate.compareTo(a.scanDate));
    return snapshots;
  }
  
  Future<void> deleteSnapshot(String id) async {
    final path = await _localPath;
    final file = File(p.join(path, '$id.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
