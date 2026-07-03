import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

class FileNode {
  final String path;
  final String name;
  final int size;
  final bool isFile;
  final List<FileNode> children;

  FileNode({
    required this.path,
    required this.name,
    required this.size,
    required this.isFile,
    this.children = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'size': size,
      'isFile': isFile,
      'children': children.map((child) => child.toJson()).toList(),
    };
  }

  factory FileNode.fromJson(Map<String, dynamic> json) {
    return FileNode(
      path: json['path'],
      name: json['name'],
      size: json['size'],
      isFile: json['isFile'],
      children: (json['children'] as List<dynamic>?)
          ?.map((child) => FileNode.fromJson(child))
          .toList() ?? [],
    );
  }
  FileNode shallowCopy() {
    return FileNode(
      path: path,
      name: name,
      size: size,
      isFile: isFile,
      children: [], // No children
    );
  }
}

class ScanProgress {
  final int itemCount;
  final String currentPath;

  ScanProgress({required this.itemCount, required this.currentPath});
}

class ScanResult {
  final FileNode rootNode;
  final int fileCount;
  final int folderCount;

  /// Entities that could not be read (permission errors, vanished files).
  /// Their sizes are missing from [rootNode.size].
  final int skippedCount;

  ScanResult({
    required this.rootNode,
    required this.fileCount,
    required this.folderCount,
    this.skippedCount = 0,
  });
}

class ScanException implements Exception {
  final String message;
  ScanException(this.message);

  @override
  String toString() => message;
}

/// Internal: carries an error message out of the scan isolate.
class _ScanError {
  final String message;
  _ScanError(this.message);
}

class DiskScanner {
  Isolate? _isolate;

  bool get isScanning => _isolate != null;

  /// Scans [path] on a background isolate so the UI never blocks.
  ///
  /// Returns null if the scan was cancelled via [cancel].
  Future<ScanResult?> scanDirectory(
    String path, {
    void Function(ScanProgress progress)? onProgress,
  }) async {
    if (_isolate != null) {
      throw StateError("A scan is already in progress");
    }

    final port = ReceivePort();
    final completer = Completer<ScanResult?>();

    try {
      _isolate = await Isolate.spawn(
        _scanIsolateEntry,
        (path, port.sendPort),
        onExit: port.sendPort,
      );
    } catch (e) {
      port.close();
      rethrow;
    }

    port.listen((message) {
      if (message is ScanProgress) {
        onProgress?.call(message);
      } else if (message is ScanResult) {
        if (!completer.isCompleted) completer.complete(message);
      } else if (message is _ScanError) {
        if (!completer.isCompleted) {
          completer.completeError(ScanException(message.message));
        }
      } else {
        // onExit message: the isolate died (cancelled or crashed) without
        // producing a result.
        if (!completer.isCompleted) completer.complete(null);
      }
    });

    try {
      return await completer.future;
    } finally {
      port.close();
      _isolate = null;
    }
  }

  /// Stops a running scan. The pending [scanDirectory] future completes
  /// with null.
  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
  }
}

void _scanIsolateEntry((String, SendPort) args) {
  final (path, port) = args;
  try {
    final result = _scanSync(path, port);
    // Isolate.exit hands the result to the main isolate without copying.
    Isolate.exit(port, result);
  } catch (e) {
    port.send(_ScanError(e.toString()));
  }
}

ScanResult _scanSync(String rootPath, SendPort port) {
  if (!Directory(rootPath).existsSync()) {
    throw ScanException("Directory does not exist: $rootPath");
  }

  const maxItemsPerFolder = 20;
  const progressIntervalMs = 100;

  int itemCount = 0;
  int fileCount = 0;
  int folderCount = 0;
  int skippedCount = 0;

  final throttle = Stopwatch()..start();
  // Negative start so the very first entity reports immediately.
  int lastProgressMs = -progressIntervalMs;

  void reportProgress(String currentPath) {
    if (throttle.elapsedMilliseconds - lastProgressMs < progressIntervalMs) {
      return;
    }
    lastProgressMs = throttle.elapsedMilliseconds;
    port.send(ScanProgress(itemCount: itemCount, currentPath: currentPath));
  }

  FileNode scanDir(String dirPath) {
    int totalSize = 0;
    List<FileNode> children = [];

    List<FileSystemEntity> entities;
    try {
      entities = Directory(dirPath).listSync(followLinks: false);
    } on FileSystemException {
      skippedCount++;
      entities = const [];
    }

    for (final entity in entities) {
      itemCount++;
      reportProgress(dirPath);

      if (entity is File) {
        final stat = entity.statSync();
        if (stat.type == FileSystemEntityType.notFound) {
          skippedCount++;
          continue;
        }
        fileCount++;
        totalSize += stat.size;
        children.add(FileNode(
          path: entity.path,
          name: p.basename(entity.path),
          size: stat.size,
          isFile: true,
        ));
      } else if (entity is Directory) {
        folderCount++;
        final node = scanDir(entity.path);
        totalSize += node.size;
        children.add(node);
      }
      // Symlinks come back as Link (followLinks: false) and are skipped:
      // we never traverse them, so directory cycles are impossible.
    }

    children.sort((a, b) => b.size.compareTo(a.size));

    // Collapse small items
    if (children.length > maxItemsPerFolder) {
      final topChildren = children.take(maxItemsPerFolder).toList();
      final othersSize = children
          .skip(maxItemsPerFolder)
          .fold<int>(0, (sum, item) => sum + item.size);

      if (othersSize > 0) {
        topChildren.add(FileNode(
          path: "",
          name: "Others (${children.length - maxItemsPerFolder} items)",
          size: othersSize,
          isFile: true,
          children: [],
        ));
      }
      children = topChildren;
    }

    final baseName = p.basename(dirPath);
    return FileNode(
      path: dirPath,
      name: baseName.isNotEmpty ? baseName : dirPath,
      size: totalSize,
      isFile: false,
      children: children,
    );
  }

  final rootNode = scanDir(rootPath);
  return ScanResult(
    rootNode: rootNode,
    fileCount: fileCount,
    folderCount: folderCount,
    skippedCount: skippedCount,
  );
}
