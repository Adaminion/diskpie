import '../scanner.dart';

class Snapshot {
  final String id;
  final DateTime scanDate;
  final int scanDurationInSeconds;
  final String rootPath;
  final FileNode rootNode;
  final int totalFiles;
  final int totalFolders;
  final int totalSize;

  Snapshot({
    required this.id,
    required this.scanDate,
    required this.scanDurationInSeconds,
    required this.rootPath,
    required this.rootNode,
    this.totalFiles = 0,
    this.totalFolders = 0,
    this.totalSize = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scanDate': scanDate.toIso8601String(),
      'scanDurationInSeconds': scanDurationInSeconds,
      'rootPath': rootPath,
      'rootNode': rootNode.toJson(),
      'totalFiles': totalFiles,
      'totalFolders': totalFolders,
      'totalSize': totalSize,
    };
  }

  factory Snapshot.fromJson(Map<String, dynamic> json) {
    return Snapshot(
      id: json['id'],
      scanDate: DateTime.parse(json['scanDate']),
      scanDurationInSeconds: json['scanDurationInSeconds'],
      rootPath: json['rootPath'],
      rootNode: FileNode.fromJson(json['rootNode']),
      totalFiles: json['totalFiles'] ?? 0,
      totalFolders: json['totalFolders'] ?? 0,
      totalSize: json['totalSize'] ?? 0,
    );
  }
}
