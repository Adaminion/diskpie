import 'package:flutter/material.dart';
import 'home_screen.dart';

import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(400, 300), // Min width 400 as requested
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    // Setting aspect ratio is not directly supported as a hard constraint in window_manager 
    // for all platforms in a way that prevents resizing, but we start with 16:9.
    // To strictly enforce ratio during resize would require a listener and manual resize, 
    // which can be janky. We'll stick to initial size and min dimensions for now.
  });

  runApp(const DiskPieApp());
}

class DiskPieApp extends StatelessWidget {
  const DiskPieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiskPie 0.2.0',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
