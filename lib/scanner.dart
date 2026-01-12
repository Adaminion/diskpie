import 'dart:io';

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

class DiskScanner {
  Future<FileNode> scanDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw Exception("Directory does not exist");
    }

    int totalSize = 0;
    List<FileNode> children = [];

    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          if (entity is File) {
            final stat = await entity.stat();
            totalSize += stat.size;
            children.add(FileNode(
              path: entity.path,
              name: entity.uri.pathSegments.last,
              size: stat.size,
              isFile: true,
            ));
          } else if (entity is Directory) {
            // Skip symbolic links/junctions that mimic Directories to avoid loops
            if (await FileSystemEntity.isLink(entity.path)) continue;
            
            // Recursive call
            // Note: For deep trees, this might need optimization or isolation, 
            // but for a start, direct recursion is fine.
            final node = await scanDirectory(entity.path);
            totalSize += node.size;
            children.add(node);
          }
        } catch (e) {
          // debugPrint("Error processing entity ${entity.path}: $e");
          // Skip files/dirs we can't access
        }
      }
    } catch (e) {
      // debugPrint("Error listing directory $path: $e");
    }

    // Sort children by size descending
    children.sort((a, b) => b.size.compareTo(a.size));

    // Collapse small items if too many
    const int maxItems = 20;
    if (children.length > maxItems) {
      final topChildren = children.take(maxItems).toList();
      final otherChildren = children.skip(maxItems);
      
      int othersSize = 0;
      for (final c in otherChildren) {
        othersSize += c.size;
      }
      
      if (othersSize > 0) {
        topChildren.add(FileNode(
          path: "", 
          name: "Others (${children.length - maxItems} items)",
          size: othersSize,
          isFile: true, // Treated as file (leaf)
          children: [],
        ));
      }
      children = topChildren;
    }

    return FileNode(
      path: path,
      name: dir.uri.pathSegments.isNotEmpty 
          ? dir.uri.pathSegments.where((s) => s.isNotEmpty).last 
          : path,
      size: totalSize,
      isFile: false,
      children: children,
    );
  }
}
