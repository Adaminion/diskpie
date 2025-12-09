import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'scanner.dart';
import 'package:intl/intl.dart';
import 'dart:math';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedPath;
  FileNode? _rootNode;
  bool _isLoading = false;
  final DiskScanner _scanner = DiskScanner();

  Future<void> _pickDirectory() async {
    final String? directoryPath = await getDirectoryPath();
    if (directoryPath == null) {
      // User canceled the picker
      return;
    }

    setState(() {
      _selectedPath = directoryPath;
      _isLoading = true;
    });

    try {
      final node = await _scanner.scanDirectory(directoryPath);
      setState(() {
        _rootNode = node;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DiskPie'),
        actions: [
          if (_selectedPath != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _pickDirectory(), // Re-pick/Re-scan
              tooltip: 'Scan again',
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _selectedPath == null 
          ? FloatingActionButton.extended(
              onPressed: _pickDirectory,
              label: const Text("Select Folder"),
              icon: const Icon(Icons.folder_open),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Scanning directory..."),
          ],
        ),
      );
    }

    if (_rootNode == null) {
      return const Center(
        child: Text("Select a folder to analyze disk usage."),
      );
    }

    return Column(
      children: [
        // Path Header
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            "Path: ${_rootNode!.path}",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        // Chart Section (Placeholder for now)
        SizedBox(
          height: 300,
          child: _buildChart(),
        ),
        const Divider(),
        // List Section
        Expanded(
          child: ListView.builder(
            itemCount: _rootNode!.children.length,
            itemBuilder: (context, index) {
              final node = _rootNode!.children[index];
              return ListTile(
                leading: Icon(node.isFile ? Icons.insert_drive_file : Icons.folder),
                title: Text(node.name),
                subtitle: Text(node.isFile ? "File" : "Directory"),
                trailing: Text(_formatBytes(node.size)),
                onTap: () {
                  // TODO: Navigate into directory
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChart() {
    if (_rootNode == null || _rootNode!.children.isEmpty) {
      return const Center(child: Text("No data"));
    }
    
    // Simple top 5 + others logic
    final totalSize = _rootNode!.size;
    final entries = _rootNode!.children.take(10).toList();
    
    return PieChart(
      PieChartData(
        sections: entries.map((node) {
          final isLarge = node.size / totalSize > 0.05;
          final value = node.size.toDouble();
          return PieChartSectionData(
            value: value,
            title: isLarge ? node.name : "",
            radius: 100,
            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
            // Random-ish colors or based on type
            color: Colors.primaries[entries.indexOf(node) % Colors.primaries.length],
            showTitle: true,
          );
        }).toList(),
        sectionsSpace: 2,
        centerSpaceRadius: 40,
      ),
    );
  }
}
