import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/models/beacon_observation_model.dart';


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

enum BeaconScanMode { balanced, lowPower, aggressive }
class BeaconScannerScreen extends StatefulWidget {
  const BeaconScannerScreen({super.key});

  @override
  State<BeaconScannerScreen> createState() => _BeaconScannerScreenState();
}

class _BeaconScannerScreenState extends State<BeaconScannerScreen> {
  final _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSub;
  Timer? _uiTicker;

  bool _isScanning = false;
  final Map<String, Observation> _found = {};
  final List<Observation> _list = [];

  // Power-safe scan modes (Low Power / Balanced / Aggressive)
  ScanMode _scanMode = ScanMode.balanced;

  // Refresh rate (1 Hz configurable)
  Duration _uiTick = const Duration(seconds: 1);
  final Map<String, Duration> _hzPresets = const {
    "0.5 Hz (every 2s)": Duration(seconds: 2),
    "1 Hz (every 1s)": Duration(seconds: 1),
    "2 Hz (every 0.5s)": Duration(milliseconds: 500),
  };

  @override
  void initState() {
    super.initState();
    _ensurePermissions();
  }

  // Permissions handling

  Future<void> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final denied = statuses.values.any((p) => p.isDenied);
    final permanentlyDenied = statuses.values.any((p) => p.isPermanentlyDenied);
    final locationOn = await Geolocator.isLocationServiceEnabled();

    if (permanentlyDenied || !locationOn) {
      await _showRationale(permanentlyDenied: permanentlyDenied, locationOn: locationOn);
    } else if (denied) {
      _snack('Bluetooth & Location permissions are required.');
    } else {
      debugPrint('✅ Permissions granted.');
    }
  }

  Future<void> _showRationale({
    required bool permanentlyDenied,
    required bool locationOn,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permissions & Location needed'),
        content: Text(
          '${!locationOn ? '• Turn on Location Services\n' : ''}'
              '${permanentlyDenied ? '• Enable Bluetooth & Location in Settings.\n' : '• Allow Bluetooth & Location to scan for beacons.\n'}'
              'Scanning uses Bluetooth LE advertisements (no pairing).',
        ),
        actions: [
          if (!locationOn)
            TextButton(
              onPressed: () => Geolocator.openLocationSettings(),
              child: const Text('Open Location Settings'),
            ),
          if (permanentlyDenied)
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('Open App Settings'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  //  Beacon Parsing Logic (iBeacon / Eddystone)

  Observation? _parseBeacon(String id, int rssi, List<int> data, {Uuid? serviceUuid}) {
    if (data.isEmpty) return null;

    // --- Detect iBeacon packets ---
    for (int i = 0; i <= data.length - 22; i++) {
      final applePrefix =
          i + 3 < data.length && data[i] == 0x4C && data[i + 1] == 0x00 && data[i + 2] == 0x02 && data[i + 3] == 0x15;
      final barePrefix = i + 1 < data.length && data[i] == 0x02 && data[i + 1] == 0x15;

      if (applePrefix || barePrefix) {
        final offset = applePrefix ? i + 4 : i + 2;
        if (offset + 20 <= data.length) {
          final uuidBytes = data.sublist(offset, offset + 16);
          final major = (data[offset + 16] << 8) | data[offset + 17];
          final minor = (data[offset + 18] << 8) | data[offset + 19];
          final uuid = _bytesToUuid(uuidBytes);

          return Observation(
            id: id,
            type: 'iBeacon',
            info: '($uuid / $major / $minor)',
            rssi: rssi,
            seenAt: DateTime.now(),
          );
        }
      }
    }

    // --- Detect Eddystone UID (FrameType = 0x00, UUID FEAA) ---
    if (serviceUuid != null &&
        serviceUuid.toString().toUpperCase().contains('FEAA') &&
        data.isNotEmpty &&
        data[0] == 0x00 &&
        data.length >= 18) {
      final namespace = data.sublist(2, 12).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
      final instance = data.sublist(12, 18).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
      return Observation(
        id: id,
        type: 'Eddystone',
        info: '($namespace / $instance)',
        rssi: rssi,
        seenAt: DateTime.now(),
      );
    }

    return null;
  }

  String _bytesToUuid(List<int> bytes) {
    final hex = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // ------------------------------------------------------------
  // 3️⃣ BLE Scanning Logic
  // ------------------------------------------------------------

  Future<void> _startScan() async {
    if (_isScanning) return;

    _found.clear();
    _list.clear();
    setState(() => _isScanning = true);
    _snack('Scanning (${_labelForMode(_scanMode)})');

    // Update UI list at chosen frequency (1 Hz default)
    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(_uiTick, (_) {
      if (!mounted) return;
      setState(() {
        _list
          ..clear()
          ..addAll(_found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
      });
    });

    try {
      _scanSub = _ble
          .scanForDevices(withServices: [], scanMode: _scanMode)
          .listen((d) {
        Observation? obs;

        // Try manufacturer data first (iBeacon)
        if (d.manufacturerData.isNotEmpty) {
          obs = _parseBeacon(d.id, d.rssi, d.manufacturerData);
        }

        // Try service data (Eddystone)
        if (obs == null && d.serviceData.isNotEmpty) {
          for (final entry in d.serviceData.entries) {
            obs ??= _parseBeacon(d.id, d.rssi, entry.value, serviceUuid: entry.key);
          }
        }

        // Update if found
        if (obs != null) {
          final existing = _found[d.id];
          _found[d.id] = existing != null
              ? existing.copyUpdated(rssi: obs.rssi, seenAt: obs.seenAt)
              : obs;
        }
      }, onError: (e) => _snack('Scan error: $e'));
    } catch (e) {
      _snack('Exception: $e');
      await _stopScan();
    }
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _uiTicker?.cancel();
    if (mounted) setState(() => _isScanning = false);
  }

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  // ------------------------------------------------------------
  // 4️⃣ UI
  // ------------------------------------------------------------

  String _labelForMode(ScanMode m) {
    switch (m) {
      case ScanMode.lowPower:
        return 'Low Power';
      case ScanMode.balanced:
        return 'Balanced';
      case ScanMode.lowLatency:
        return 'Aggressive';
      default:
        return m.name;
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Beacon Scanner'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // Scan Mode Selector
          DropdownButtonHideUnderline(
            child: DropdownButton<ScanMode>(
              dropdownColor: Colors.grey[900],
              value: _scanMode,
              icon: const Icon(Icons.tune, color: Colors.white),
              items: const [
                DropdownMenuItem(
                    value: ScanMode.lowPower,
                    child: Text('Low Power', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(
                    value: ScanMode.balanced,
                    child: Text('Balanced', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(
                    value: ScanMode.lowLatency,
                    child: Text('Aggressive', style: TextStyle(color: Colors.white))),
              ],
              onChanged: (mode) async {
                if (mode == null) return;
                setState(() => _scanMode = mode);
                if (_isScanning) {
                  await _stopScan();
                  await Future.delayed(const Duration(milliseconds: 200));
                  await _startScan();
                }
              },
            ),
          ),
        ],
      ),
      body: _list.isEmpty
          ? const Center(
        child: Text(
          'No beacons detected yet.\nTap “Scan” to start.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      )
          : ListView.builder(
        itemCount: _list.length,
        itemBuilder: (_, i) {
          final o = _list[i];
          return ListTile(
            leading: Icon(
              o.type == 'iBeacon' ? Icons.bluetooth_searching : Icons.radio,
              color: o.type == 'iBeacon' ? Colors.blueAccent : Colors.orangeAccent,
            ),
            title: Text(
              '${o.type} ${o.info}',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Device: ${o.id}\nMode: ${_labelForMode(_scanMode)}',
              style: const TextStyle(color: Colors.white54),
            ),
            trailing: Text(
              '${o.rssi} dBm',
              style: const TextStyle(color: Colors.greenAccent),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _isScanning ? Colors.redAccent : Colors.greenAccent,
        onPressed: _isScanning ? _stopScan : _startScan,
        icon: Icon(_isScanning ? Icons.stop : Icons.search, color: Colors.black),
        label: Text(_isScanning ? 'Stop' : 'Scan',
            style: const TextStyle(color: Colors.black)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}