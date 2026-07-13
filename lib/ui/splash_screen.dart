import 'package:flutter/material.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/home_screen.dart';
import 'package:provider/provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Shows the splash while the app state restores (last session, service
  /// status, real location) — with a short minimum so the logo doesn't flash.
  Future<void> _start() async {
    await Future.wait([
      context.read<AppState>().init(),
      Future.delayed(const Duration(milliseconds: 1200)),
    ]);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: Image.asset(
          'assets/images/logo.png',
          width: 200,
          height: 200,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.location_on, size: 100, color: Colors.white);
          },
        ),
      ),
    );
  }
}
