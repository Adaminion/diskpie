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
  Future<FileNode> scanDirectory(String path, {void Function(int count)? onProgress}) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw Exception("Directory does not exist");
    }

    int count = 0;
    final Set<String> visitedPaths = {};
    
    Future<FileNode> scanRecursive(String currentPath) async {
       // Resolve canonical path to detect loops
       String canonicalPath;
       try {
         canonicalPath = Directory(currentPath).resolveSymbolicLinksSync();
       } catch (e) {
         // Fallback if resolution fails (e.g. perms), just use raw path
         // but strictly speaking if we can't resolve, we might risk loop, 
         // so we proceed with caution or skip. We'll proceed with raw.
         canonicalPath = currentPath;
       }

       if (visitedPaths.contains(canonicalPath)) {
         // Loop detected or already visited
         return FileNode(
           path: currentPath, 
           name: "${currentPath.split(Platform.pathSeparator).last} (Link/Loop)", 
           size: 0, 
           isFile: true, // Treat as file to stop recursion
           children: []
         );
       }
       visitedPaths.add(canonicalPath);

       final currentDir = Directory(currentPath);
       int totalSize = 0;
       List<FileNode> children = [];

       try {
         await for (final entity in currentDir.list(followLinks: false)) {
           count++;
           if (count % 50 == 0) {
             onProgress?.call(count);
           }
           
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
                // Double check for raw link (though resolveSymbolicLinksSync handles the real loop check)
                if (await FileSystemEntity.isLink(entity.path)) continue;
                
                final node = await scanRecursive(entity.path);
                totalSize += node.size;
                
                // If it was a loop/link return we might want to still add it but not add size? 
                // Currently size 0 so it's fine.
                children.add(node);
             }
           } catch (e) {
             // skip
           }
         }
       } catch (e) {
         // skip
       }
       
       children.sort((a, b) => b.size.compareTo(a.size));
       
       // Collapse small items
       const int maxItems = 20;
       if (children.length > maxItems) {
         final topChildren = children.take(maxItems).toList();
         final otherChildren = children.skip(maxItems);
         int othersSize = otherChildren.fold(0, (sum, item) => sum + item.size);
         
         if (othersSize > 0) {
           topChildren.add(FileNode(
             path: "", 
             name: "Others (${children.length - maxItems} items)",
             size: othersSize,
             isFile: true, 
             children: [],
           ));
         }
         children = topChildren;
       }

       return FileNode(
         path: currentPath,
         name: currentDir.uri.pathSegments.isNotEmpty 
            ? currentDir.uri.pathSegments.where((s) => s.isNotEmpty).last 
            : currentPath,
         size: totalSize,
         isFile: false,
         children: children,
       );
    }

    return await scanRecursive(path);
  }
}
