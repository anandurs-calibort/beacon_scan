import 'package:flutter/material.dart';
import '../screens/beacon_scanner_screen.dart';


class BeaconTrackApp extends StatelessWidget {
  const BeaconTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BeaconTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const BeaconScannerScreen(),
    );
  }
}

