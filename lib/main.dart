import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const DiskPieApp());
}

class DiskPieApp extends StatelessWidget {
  const DiskPieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiskPie',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
