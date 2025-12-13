import '../scanner.dart';

class Snapshot {
  final String id;
  final DateTime scanDate;
  final int scanDurationInSeconds;
  final String rootPath;
  final FileNode rootNode;

  Snapshot({
    required this.id,
    required this.scanDate,
    required this.scanDurationInSeconds,
    required this.rootPath,
    required this.rootNode,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scanDate': scanDate.toIso8601String(),
      'scanDurationInSeconds': scanDurationInSeconds,
      'rootPath': rootPath,
      'rootNode': rootNode.toJson(),
    };
  }

  factory Snapshot.fromJson(Map<String, dynamic> json) {
    return Snapshot(
      id: json['id'],
      scanDate: DateTime.parse(json['scanDate']),
      scanDurationInSeconds: json['scanDurationInSeconds'],
      rootPath: json['rootPath'],
      rootNode: FileNode.fromJson(json['rootNode']),
    );
  }
}
