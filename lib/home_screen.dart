import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart'; // For mouse events
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart'; // For right-click 'open in explorer'

import 'models/snapshot.dart';
import 'scanner.dart';
import 'services/recent_scans_service.dart';
import 'services/snapshot_service.dart';
import 'services/disk_service.dart';
import 'services/logger_service.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State variables

  FileNode? _liveRootNode; // Holds the result of a fresh scan
  FileNode? _snapshotRootNode; // Holds the loaded snapshot
  bool _isViewingSnapshot = false;
  
  // Interaction State
  int _hoveredIndex = -1;
  Offset _mousePos = Offset.zero;


  bool _isLoading = false;
  String? _scanStatusMessage; // "Scanning complete took X minutes"
  int _scannedCount = 0;
  
  final DiskScanner _scanner = DiskScanner();
  final DiskService _diskService = DiskService();
  final LoggerService _logger = LoggerService();

  final SnapshotService _snapshotService = SnapshotService();
  final RecentScansService _recentScansService = RecentScansService();

  DiskUsage? _currentDiskUsage;

  List<String> _recentScans = [];
  List<Snapshot> _recentSnapshots = [];



  // Timer
  Stopwatch? _scanTimer;

  // Helpers
  // Returns the node currently being displayed
  FileNode? get _displayRootNode => _isViewingSnapshot ? _snapshotRootNode : _liveRootNode;

  // Processed children for display (Files grouped)
  List<FileNode> get _processedChildren {
    final root = _displayRootNode;
    if (root == null) return [];

    final folders = root.children.where((c) => !c.isFile).toList();
    final files = root.children.where((c) => c.isFile && !c.name.startsWith("Others")).toList();
    final others = root.children.where((c) => c.isFile && c.name.startsWith("Others")).toList();
    folders.addAll(others);

    if (files.isNotEmpty) {
      final totalFileSize = files.fold<int>(0, (sum, item) => sum + item.size);
      final filesNode = FileNode(
        path: root.path, // Logical path
        name: "Files", // Group name
        size: totalFileSize,
        isFile: true, // Treat as file-like for icon
        children: [],
      );
      folders.add(filesNode);
    }

    folders.sort((a, b) => b.size.compareTo(a.size));
    return folders;
  }


  @override
  void initState() {
    super.initState();
    _refreshDashboardData();

  }

  Future<void> _pickDirectory() async {
    final String? directoryPath = await getDirectoryPath();
    if (directoryPath == null) return;

    setState(() {
      _isLoading = true;
      _scannedCount = 0;
      _isViewingSnapshot = false; // Switch back to live mode
      _snapshotRootNode = null;
      _scanStatusMessage = null;
    });

    _scanTimer = Stopwatch()..start();

    try {
      final node = await _scanner.scanDirectory(
        directoryPath, 
        onProgress: (count) {
          if (mounted) {
            setState(() {
               _scannedCount = count;
            });
          }
        }
      );
      await _recentScansService.addRecentScan(directoryPath);
      _refreshDashboardData();

      _scanTimer?.stop();

      // Fetch Disk Usage
      final usage = await _diskService.getDiskUsage(directoryPath);
      
      final elapsed = _scanTimer?.elapsed;
      String timeMsg = "";
      if (elapsed != null) {
        if (elapsed.inMinutes > 0) {
          timeMsg = "${elapsed.inMinutes} minutes and ${elapsed.inSeconds % 60} seconds";
        } else {
          timeMsg = "${elapsed.inSeconds} seconds";
        }
      }

      if (mounted) {
        setState(() {
          _liveRootNode = node;
          _currentDiskUsage = usage;
          _scanStatusMessage = "Scanning complete! Took $timeMsg.";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_scanStatusMessage!)),
        );
      }
      } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning: $e')),
        );
      }
      await _logger.logError("Error in _pickDirectory for path $directoryPath", e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSnapshot() async {
    if (_liveRootNode == null || _isViewingSnapshot) return;

    final name = await _showInputDialog("Snapshot Name", "Enter a name/ID for this snapshot");
    if (name == null || name.isEmpty) return;

    // Prune tree: Keep root and its immediate children (shallow copies)
    // This removes deep nesting to save space and satisfy "recover left side only"
    final prunedChildren = _liveRootNode!.children.map((c) => c.shallowCopy()).toList();
    final prunedRoot = FileNode(
      path: _liveRootNode!.path,
      name: _liveRootNode!.name,
      size: _liveRootNode!.size,
      isFile: _liveRootNode!.isFile,
      children: prunedChildren,
    );

    final snapshot = Snapshot(
      id: name, // Using user input as ID/filename for simplicity, or generate UUID
      scanDate: DateTime.now(),
      scanDurationInSeconds: _scanTimer?.elapsed.inSeconds ?? 0,
      rootPath: prunedRoot.path,
      rootNode: prunedRoot,
    );

    await _snapshotService.saveSnapshot(snapshot);
    _refreshDashboardData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Snapshot saved successfully!')),
      );
    }
  }

  Future<String?> _showInputDialog(String title, String hint) {
    String value = "Snapshot_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}";
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            controller: TextEditingController(text: value),
            onChanged: (v) => value = v,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            TextButton(
              onPressed: () => Navigator.pop(context, value), 
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  void _openSnapshotsList() async {
    final snapshots = await _snapshotService.loadAllSnapshots();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
            width: 600,
            height: 400,
            child: Column(
              children: [
                AppBar(
                  title: const Text("Snapshots"),
                  automaticallyImplyLeading: false,
                  actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: snapshots.length,
                    itemBuilder: (context, index) {
                      final s = snapshots[index];
                      return ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(s.id),
                        subtitle: Text(
                          "${s.rootPath}\n${DateFormat.yMMMd().add_jm().format(s.scanDate)} - Took ${s.scanDurationInSeconds}s",
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                             await _snapshotService.deleteSnapshot(s.id);
                             if (!mounted) return;
                             // ignore: use_build_context_synchronously
                             Navigator.pop(context); // Close to refresh (simple way)
                             _openSnapshotsList(); // Re-open
                          },
                        ),
                        onTap: () {
                          // Load snapshot
                          if (!mounted) return;
                          setState(() {
                            _snapshotRootNode = s.rootNode;
                            _isViewingSnapshot = true;
                            _scanStatusMessage = "Viewing Snapshot: ${s.id}";
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            )),
      ),
    );
  }

  void _showLogsDialog() async {
    final logs = await _logger.getLogs();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.bug_report, color: Colors.teal),
            const SizedBox(width: 8),
            const Text("Application Logs"),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_outline), 
              tooltip: "Clear Logs",
              onPressed: () async {
                 await _logger.clearLogs();
                 if (context.mounted) Navigator.pop(context);
              },
            )
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: logs.isEmpty 
              ? const Center(child: Text("No logs found."))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[logs.length - 1 - index]; // Show newest first
                    final isError = log.contains("[ERROR]");
                    return SelectableText(
                      log, 
                      style: TextStyle(
                        fontFamily: 'Consolas', 
                        fontSize: 12,
                        color: isError ? Colors.red.shade800 : Colors.black87
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  void _restoreLiveView() {
    setState(() {
      _isViewingSnapshot = false;
      _isViewingSnapshot = false;
      _snapshotRootNode = null;
      _currentDiskUsage = null; // Clear usage when returning from snapshot or resetting

      if (_liveRootNode != null) {
        _scanStatusMessage = "Returned to Live Scan";
      } else {
        _scanStatusMessage = null;
      }
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  void _startScanForPath(String path) {
    setState(() {
      _isLoading = true;
      _scannedCount = 0;
      _isViewingSnapshot = false;
      _snapshotRootNode = null;
      _currentDiskUsage = null;
      _scanStatusMessage = null;
    });
    _scanPath(path);
  }

  Future<void> _openFolderInExplorer(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else {
        await launchUrl(Uri.file(path));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open folder: $e')),
      );
      await _logger.logError("Could not open folder $path", e);
    }
  }

  Future<void> _showFolderOptions(FileNode node, Offset? globalPosition) async {
    if (node.isFile || node.name == "Files") return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position = globalPosition ??
        overlay?.localToGlobal(overlay.size.center(Offset.zero)) ??
        Offset.zero;

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(
          value: 'scan',
          child: Text('Scan this folder now'),
        ),
        PopupMenuItem(
          value: 'explorer',
          child: Text('Open in Windows Explorer'),
        ),
      ],
    );

    switch (choice) {
      case 'scan':
        _startScanForPath(node.path);
        break;
      case 'explorer':
        _openFolderInExplorer(node.path);
        break;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DiskPie'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Info',
            onPressed: () {
               showAboutDialog(context: context, applicationName: "DiskPie", applicationVersion: "1.0.0");
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Settings not implemented yet")));
            },
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Logs',
            onPressed: _showLogsDialog,
          ),
          if (_liveRootNode != null && !_isViewingSnapshot && !_isLoading)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save Snapshot',
              onPressed: _saveSnapshot,
            ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Snapshots',
            onPressed: _openSnapshotsList,
          ),
          if (_isViewingSnapshot)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton.icon(
                 onPressed: _restoreLiveView,
                 icon: const Icon(Icons.exit_to_app),
                 label: const Text("Exit Snapshot"),
                 style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              ),
            )
        ],
      ),
      body: _buildBody(),
      floatingActionButton: (!_isLoading && !_isViewingSnapshot) ? FloatingActionButton.extended(
        onPressed: _pickDirectory,
        label: const Text("Scan New Folder"),
        icon: const Icon(Icons.folder_open),
      ) : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text("Scanning directory... This may take a while for large disks."),
            if (_scannedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "Scanned $_scannedCount items...", 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              )
          ],
        ),
      );
    }

    if (_displayRootNode == null) {
      return _buildDashboard();
    }

    // Side-by-side Layout
    final displayList = _processedChildren;

    return Column(
      children: [
        // Info Header
        Container(
          padding: const EdgeInsets.all(12),
          color: _isViewingSnapshot ? Colors.amber.shade100 : Colors.grey.shade200,
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Path: ${_displayRootNode!.path}", style: const TextStyle(fontWeight: FontWeight.bold)),
              if (_scanStatusMessage != null)
                Text(_scanStatusMessage!, style: const TextStyle(color: Colors.blueGrey)),
            ],
          ),
        ),
        
        // Stats Header
        if (_currentDiskUsage != null && !_isViewingSnapshot)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                _buildStatItem("Disk Size", _formatBytes(_currentDiskUsage!.totalSpace)),
                const SizedBox(width: 24),
                _buildStatItem("Used", _formatBytes(_currentDiskUsage!.usedSpace)),
                const SizedBox(width: 24),
                _buildStatItem("Free", "${_currentDiskUsage!.freePercentage.toStringAsFixed(1)}%"),
              ],
            ),
          ),
        
        // Main Content
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Pie Chart with Tooltip and Listener
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Stack(
                    children: [
                      Listener(
                        onPointerDown: (event) {
                          if (event.buttons == kSecondaryMouseButton) {
                            if (_hoveredIndex >= 0 && _hoveredIndex < displayList.length) {
                              final node = displayList[_hoveredIndex];
                              _showFolderOptions(node, event.position);
                            }
                          }
                        },
                        onPointerHover: (event) {
                          setState(() {
                            _mousePos = event.localPosition;
                          });
                        },
                        child: _buildChart(displayList, _displayRootNode!.size),
                      ),
                      // Custom Tooltip Overlay
                      if (_hoveredIndex >= 0 && _hoveredIndex < displayList.length)
                        Positioned(
                          left: _mousePos.dx + 10,
                          top: _mousePos.dy + 10,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "${displayList[_hoveredIndex].name}\n${_formatBytes(displayList[_hoveredIndex].size)}",
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              // Right: Folder List
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.grey.shade100,
                      width: double.infinity,
                      child: const Text("Details (Grouped)", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          final node = displayList[index];
                          final isGroupedFiles = node.name == "Files" && node.isFile;
                          Offset? tapPosition;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) {
                              tapPosition = details.globalPosition;
                            },
                            onSecondaryTapDown: (details) {
                              tapPosition = details.globalPosition;
                              _showFolderOptions(node, tapPosition);
                            },
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                isGroupedFiles 
                                    ? Icons.file_copy 
                                    : (node.isFile 
                                        ? (node.name.startsWith("Others") ? Icons.more_horiz : Icons.insert_drive_file) 
                                        : Icons.folder), 
                                size: 20
                              ),
                              title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_displayRootNode!.size > 0 ? "${(node.size / _displayRootNode!.size * 100).toStringAsFixed(1)}%" : ""),
                                  const SizedBox(width: 8),
                                  Text(_formatBytes(node.size)),
                                ],
                              ),
                              onTap: () {
                                if (!isGroupedFiles && !node.isFile) {
                                  _showFolderOptions(node, tapPosition);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

  }

  Future<void> _refreshDashboardData() async {
    final scans = await _recentScansService.getRecentScans();
    final snapshots = await _snapshotService.loadAllSnapshots();
    if (mounted) {
      setState(() {
        _recentScans = scans;
        _recentSnapshots = snapshots.take(10).toList();
      });
    }
  }

  Widget _buildDashboard() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Image.asset(
              'assets/logo.png',
              height: 150,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.pie_chart, size: 100, color: Colors.teal),
            ),
            const SizedBox(height: 16),
             const Text(
              "DiskPie",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
             const SizedBox(height: 8),
            const Text(
              "Analyze your disk usage with style",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 48),

            // Lists Row
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Recent Locations
                  Expanded(
                    child: Card(
                      elevation: 4,
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            color: Colors.teal.shade50,
                            child: Row(
                              children: const [
                                Icon(Icons.folder_open, color: Colors.teal),
                                SizedBox(width: 8),
                                Text("Recent Locations", style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _recentScans.isEmpty
                                ? const Center(child: Text("No recent scans"))
                                : ListView.separated(
                                    itemCount: _recentScans.length,
                                    separatorBuilder: (c, i) => const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final path = _recentScans[index];
                                      return ListTile(
                                        title: Text(path),
                                        leading: const Icon(Icons.history, size: 18),
                                        dense: true,
                                        onTap: () async {
                                           // Rescan this path
                                           _startScanForPath(path);
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Recent Snapshots
                  Expanded(
                    child: Card(
                      elevation: 4,
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            color: Colors.amber.shade50,
                            child: Row(
                              children: const [
                                Icon(Icons.camera_alt, color: Colors.amber),
                                SizedBox(width: 8),
                                Text("Recent Snapshots", style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _recentSnapshots.isEmpty
                                ? const Center(child: Text("No saved snapshots"))
                                : ListView.separated(
                                    itemCount: _recentSnapshots.length,
                                    separatorBuilder: (c, i) => const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final s = _recentSnapshots[index];
                                      return ListTile(
                                        title: Text(s.id),
                                        subtitle: Text(DateFormat.yMMMd().format(s.scanDate)),
                                        leading: const Icon(Icons.pie_chart_outline, size: 18),
                                        dense: true,
                                        onTap: () {
                                          setState(() {
                                            _snapshotRootNode = s.rootNode;
                                            _isViewingSnapshot = true;
                                            _scanStatusMessage = "Viewing Snapshot: ${s.id}";
                                          });
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanPath(String path) async {
      _scanTimer = Stopwatch()..start();
      try {
        final node = await _scanner.scanDirectory(
          path,
          onProgress: (count) {
             if (mounted) {
               setState(() {
                 _scannedCount = count;
               });
             }
          }
        );
        
        // Fetch stats
        final usage = await _diskService.getDiskUsage(path);

        _scanTimer?.stop();
        
        // Update recent scans (moves to top)
        await _recentScansService.addRecentScan(path);
        _refreshDashboardData();


        final elapsed = _scanTimer?.elapsed;
        String timeMsg = "";
        if (elapsed != null) {
          if (elapsed.inMinutes > 0) {
            timeMsg = "${elapsed.inMinutes} minutes and ${elapsed.inSeconds % 60} seconds";
          } else {
            timeMsg = "${elapsed.inSeconds} seconds";
          }
        }
  
        if (mounted) {
          setState(() {
            _liveRootNode = node;
            _currentDiskUsage = usage;
            _scanStatusMessage = "Scanning complete! Took $timeMsg.";
            _isLoading = false;
          });
        }
      } catch (e) {
        await _logger.logError("Error scanning path $path", e);
      } finally {
        if(mounted) {
           setState(() {
             _isLoading = false;
           });
        }
      }
  }


  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildChart(List<FileNode> entries, int totalSize) {

    if (entries.isEmpty) {
      return const Center(child: Text("No data"));
    }
    
    // We already have specific entries (grouped), so we can just use them.
    // If the list is huge, we might still want to limit slices, but 'entries' here is _processedChildren which groups files.
    // Folder count can still be high.
    final chartEntries = entries.take(30).toList(); // Limit for performance/visuals
    
    return LayoutBuilder(
      builder: (context, constraints) {
        return PieChart(
          PieChartData(
            pieTouchData: PieTouchData(
              touchCallback: (FlTouchEvent event, pieTouchResponse) {
                setState(() {
                  if (!event.isInterestedForInteractions ||
                      pieTouchResponse == null ||
                      pieTouchResponse.touchedSection == null) {
                    _hoveredIndex = -1;
                    return;
                  }
                  _hoveredIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                });
              },
            ),
            sections: List.generate(chartEntries.length, (i) {
              final node = chartEntries[i];
              final isLarge = node.size / totalSize > 0.05;
              final value = node.size.toDouble();
              final isHovered = i == _hoveredIndex;
             
              return PieChartSectionData(
                value: value,
                title: (isLarge && isHovered) || (node.size / totalSize > 1/16) 
                    ? "${node.name}\n${_formatBytes(node.size)}" 
                    : "",
                radius: isHovered ? (min(constraints.maxWidth, constraints.maxHeight) / 2.3) : min(constraints.maxWidth, constraints.maxHeight) / 2.5,
                titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                color: Colors.primaries[i % Colors.primaries.length].withValues(alpha: isHovered ? 0.8 : 1.0),
                showTitle: true,
              );
            }),
            sectionsSpace: 1,
            centerSpaceRadius: 20,
          ),
        );
      }
    );
  }
}
