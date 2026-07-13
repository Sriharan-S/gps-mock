import 'package:flutter/material.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/splash_screen.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MockGpsApp());
}

class MockGpsApp extends StatelessWidget {
  const MockGpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppState())],
      child: MaterialApp(
        title: 'Mock GPS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const SplashScreen(),
      ),
    );
  }
}
