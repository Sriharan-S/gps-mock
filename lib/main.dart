import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/splash_screen.dart';

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
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
