import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/helpers/filters.dart';
import '../core/helpers/trilateration.dart';
import '../core/models/beacon_fix.dart';
import '../core/models/beacon_observation_model.dart';
import '../core/models/beacon_state.dart';
import '../core/models/kalman_filter.dart';
import '../core/utils/beacon_math.dart';
import '../core/utils/beacon_parser.dart';
import '../widgets/beacon_tile.dart';


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
  final Map<String, BeaconState> _beaconStates = {};
  final List<Observation> _list = [];

  // constants
  static const double alpha = 0.35; // EWMA alpha
  static const double maxJump = 4.0; // max meters jump per update
  static const int staleAfterSeconds = 6;
  static const int txPower = -59;

  bool useKalman = false; // toggle filter type

  // auto-assign demo positions only (positions are mocked - AoA comes from advertisement)
  final Map<String, Offset> mockBeaconPositions = {};
  final List<Offset> _demoPositions = [
    const Offset(0, 0),
    const Offset(4, 0),
    const Offset(2, 3),
    const Offset(5, 2),
  ];
  int _assignedDemoCount = 0;

  Offset? _userPosition;
  String _accuracy = "No beacons detected";
  int _beaconsUsed = 0;

  ScanMode _scanMode = ScanMode.balanced;
  Duration _uiTick = const Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePermissions(showRationaleIfNeeded: false));
  }
  Future<bool> _ensurePermissions({bool showRationaleIfNeeded = true}) async {
    // =====================================================
    // 1️⃣ CHECK PERMISSIONS FIRST
    // =====================================================
    final bluetoothScan = await Permission.bluetoothScan.isGranted;
    final bluetoothConnect = await Permission.bluetoothConnect.isGranted;
    final locationGranted = await Permission.locationWhenInUse.isGranted;

    final permsOk = bluetoothScan && bluetoothConnect && locationGranted;

    if (!permsOk) {
      if (showRationaleIfNeeded) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Permissions Required"),
            content: const Text(
              "This app needs:\n"
                  "• Bluetooth permission to scan nearby beacons\n"
                  "• Location permission (required by Android for BLE scanning)\n\n"
                  "These permissions are different from the ON/OFF toggles.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Continue"),
              )
            ],
          ),
        );
      }

      final result = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      if (result.values.any((e) => e.isPermanentlyDenied)) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Permissions Blocked"),
            content: const Text(
              "Bluetooth or Location permissions are permanently denied.\n"
                  "Please enable them manually from Settings.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                child: const Text("Open Settings"),
              ),
            ],
          ),
        );
        return false;
      }

      if (result.values.any((e) => e.isDenied)) {
        _snack("Bluetooth & Location permissions required.");
        return false;
      }
    }

    // =====================================================
    // 2️⃣ CHECK LOCATION TOGGLE (ON/OFF)
    // =====================================================
    final locationOn = await Geolocator.isLocationServiceEnabled();
    if (!locationOn) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Location Required"),
          content: const Text(
            "Location Services are turned OFF.\n\n"
                "Android requires Location Services to be ON to scan BLE beacons "
                "(even if the app does not use GPS).",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Geolocator.openLocationSettings();
              },
              child: const Text("Open Location Settings"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
          ],
        ),
      );
      return false;
    }

    // =====================================================
    // 3️⃣ CHECK BLUETOOTH TOGGLE (ON/OFF)
    // =====================================================
    final bleState = await _ble.statusStream.first;
    if (bleState != BleStatus.ready) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Bluetooth Required"),
          content: const Text(
            "Bluetooth is currently turned OFF.\n"
                "Please turn ON Bluetooth to scan for beacons.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                FlutterReactiveBle().logLevel;
                // (no cross-platform BT settings opener available in Flutter)
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return false;
    }

    // Everything OK
    debugPrint("✅ Permissions + Toggles OK");
    return true;
  }



  Future<void> _showRationale({required bool permanentlyDenied, required bool locationOn}) async {
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
            TextButton(onPressed: () => Geolocator.openLocationSettings(), child: const Text('Open Location Settings')),
          if (permanentlyDenied)
            TextButton(onPressed: () => openAppSettings(), child: const Text('Open App Settings')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }


  // -------------------------
  // Main processing of observation with smoothing/clamping/outlier filtering
  // -------------------------
  void _processObservation(Observation obs, {double? aoa}) {
    final rawDist = estimateDistanceFromRssi(obs.rssi);

    final existing = _beaconStates[obs.id];

    // First time → create new state
    if (existing == null) {
      _beaconStates[obs.id] = BeaconState(
        id: obs.id,
        rawDistance: rawDist,
        filteredDistance: rawDist,
        rssi: obs.rssi,
        lastSeen: DateTime.now(),
        bearing: aoa,
        ewmaDistance: rawDist,
        kalmanDistance: rawDist,
        kalman: KalmanFilter1D(estimate: rawDist),
      );
      return;
    }

    // EWMA
    final ewmaValue = ewma(existing.ewmaDistance, rawDist, alpha);

    // Kalman
    existing.kalman ??= KalmanFilter1D(estimate: existing.kalmanDistance);
    final kalmanValue = existing.kalman!.update(rawDist);

    // Clamp
    final ewmaClamped = clampJump(existing.ewmaDistance, ewmaValue, maxJump);
    final kalmanClamped = clampJump(existing.kalmanDistance, kalmanValue, maxJump);

    // 🔥 FIX: CREATE A NEW INSTANCE (DO NOT MUTATE EXISTING)
    _beaconStates[obs.id] = BeaconState(
      id: existing.id,
      rawDistance: rawDist,
      filteredDistance: useKalman ? kalmanClamped : ewmaClamped,
      rssi: obs.rssi,
      lastSeen: DateTime.now(),
      bearing: aoa ?? existing.bearing,
      ewmaDistance: ewmaClamped,
      kalmanDistance: kalmanClamped,
      kalman: existing.kalman, // keep filter instance
    );
  }


  // -------------------------
  // Position update (use only best 3 beacons for trilateration)
  // -------------------------
  void _updateUserPosition() {
    final now = DateTime.now();
    final fixes = <BeaconFix>[];

    // --------------------------------------------------
    // 1️⃣ COLLECT VALID BEACONS
    // --------------------------------------------------
    for (final entry in _beaconStates.entries) {
      final id = entry.key;
      final state = entry.value;
      final pos = mockBeaconPositions[id];
      if (pos == null) continue;

      final age = now.difference(state.lastSeen).inSeconds;
      if (age > staleAfterSeconds || state.rssi < -95) continue;

      fixes.add(BeaconFix(pos, state.filteredDistance));
    }

    // Sort beacons by closeness (best distances first)
    fixes.sort((a, b) => a.dist.compareTo(b.dist));

    debugPrint("---- Valid fixes (${fixes.length}) ----");
    for (var f in fixes) {
      debugPrint("Beacon @ ${f.pos} dist=${f.dist.toStringAsFixed(3)}m");
    }

    // --------------------------------------------------
    // 2️⃣ HANDLE CASES
    // --------------------------------------------------

    if (fixes.isEmpty) {
      _userPosition = null;
      _accuracy = "No beacons detected";
      _beaconsUsed = 0;
      setState(() {});
      return;
    }

    if (fixes.length == 1) {
      _userPosition = null;
      _accuracy = "Very poorly accurate (1 beacon)";
      _beaconsUsed = 1;
      setState(() {});
      return;
    }

    if (fixes.length == 2) {
      _userPosition = estimateFromTwo(fixes[0], fixes[1]);
      _accuracy = "Medium accuracy (2 beacons)";
      _beaconsUsed = 2;
      setState(() {});
      return;
    }

    // --------------------------------------------------
    // 3️⃣ TRILATERATION (PRIMARY SOURCE)
    // --------------------------------------------------
    final best = fixes.take(3).toList();
    debugPrint("Using 3 beacons for trilateration:");

    for (var b in best) {
      debugPrint("  pos=${b.pos} dist=${b.dist.toStringAsFixed(3)}");
    }

    Offset? trilaterated = trilaterate(best[0], best[1], best[2]);

    if (trilaterated == null) {
      debugPrint("❌ Trilateration failed — using only AoA solution if possible");
    } else {
      debugPrint("🎯 Trilateration → $trilaterated");
    }

    // --------------------------------------------------
    // 4️⃣ AoA IMPROVEMENT (SECONDARY REFINEMENT)
    // --------------------------------------------------
    final aoaBeacons = _beaconStates.values
        .where((b) => b.bearing != null && mockBeaconPositions[b.id] != null)
        .toList();

    if (aoaBeacons.isEmpty) {
      // No AoA — return trilateration only
      _userPosition = trilaterated;
      _accuracy = "Highly accurate (3+ distance beacons)";
      _beaconsUsed = fixes.length;
      setState(() {});
      return;
    }

    debugPrint("🔧 Refining using AoA (${aoaBeacons.length} beacons)…");

    // --------------------------------------------------
    // 4A: Convert each AoA to a point estimation
    // --------------------------------------------------
    final aoaPoints = <Offset>[];

    for (final b in aoaBeacons) {
      final origin = mockBeaconPositions[b.id]!;
      final point = bearingToPoint(origin, b.bearing!, b.filteredDistance);

      debugPrint("🧭 AoA→Point | origin:$origin  bearing:${b.bearing}°  "
          "dist:${b.filteredDistance.toStringAsFixed(3)} → point:$point");

      aoaPoints.add(point);
    }

    // --------------------------------------------------
    // 4B: Compute AoA average (centroid)
    // --------------------------------------------------
    Offset aoaAvg = Offset.zero;
    for (final p in aoaPoints) {
      aoaAvg = Offset(aoaAvg.dx + p.dx, aoaAvg.dy + p.dy);
    }
    aoaAvg = Offset(aoaAvg.dx / aoaPoints.length, aoaAvg.dy / aoaPoints.length);

    debugPrint("📍 AoA average point → $aoaAvg");

    // --------------------------------------------------
    // 5️⃣ FUSION (SUPERIOR ACCURACY)
    // --------------------------------------------------

    // If trilateration exists → combine both using weighted fusion:
    // Trilateration = 70% weight (more reliable)
    // AoA = 30% weight (direction improvement)
    Offset finalPos;

    if (trilaterated != null) {
      finalPos = Offset(
        trilaterated.dx * 0.7 + aoaAvg.dx * 0.3,
        trilaterated.dy * 0.7 + aoaAvg.dy * 0.3,
      );
    } else {
      // Trilateration failed → use purely AoA
      finalPos = aoaAvg;
    }

    // --------------------------------------------------
    // 6️⃣ FINAL UPDATE
    // --------------------------------------------------
    _userPosition = finalPos;
    _accuracy = "Highly accurate (Distance + AoA fused)";
    _beaconsUsed = fixes.length;

    debugPrint("🎯 FINAL USER POSITION → $_userPosition");

    setState(() {});
  }


  bool useDummyBeacons = true;
  void _simulateRssiFluctuation() {
    final random = math.Random();

    Duration updateInterval;
    switch (_scanMode) {
      case ScanMode.lowPower:
        updateInterval = const Duration(seconds: 3);
        break;
      case ScanMode.lowLatency:
        updateInterval = const Duration(milliseconds: 500);
        break;
      default:
        updateInterval = const Duration(seconds: 1);
    }

    Timer.periodic(updateInterval, (timer) {
      if (!_isScanning) {
        timer.cancel();
        return;
      }

      for (final entry in _beaconStates.entries) {
        final beacon = entry.value;

        // ------------------------------------------------
        // REALISTIC BLE NOISE: ±3 dBm random fluctuation
        // ------------------------------------------------
        final noise = (random.nextDouble() * 6) - 3; // -3 to +3
        final newRssi = (beacon.rssi + noise).round();

        // Update observation used by UI
        _found[beacon.id] = _found[beacon.id]?.copyUpdated(
          rssi: newRssi,
          seenAt: DateTime.now(),
        ) ??
            Observation(
              id: beacon.id,
              type: 'Eddystone',
              info: '',
              rssi: newRssi,
              seenAt: DateTime.now(),
            );

        // Refresh list for UI sorting
        _list
          ..clear()
          ..addAll(_found.values.toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi)));

        // Filter the distance
        _processObservation(_found[beacon.id]!, aoa: beacon.bearing);
      }

      // Recalculate user position
      _updateUserPosition();

      // Update UI
      setState(() {});
    });
  }






  void _loadDummyBeacons() {
    _beaconStates.clear();
    mockBeaconPositions.clear();
    _found.clear();
    _list.clear();

    final now = DateTime.now();

    final dummyBeacons = [
      BeaconState(
        id: 'AA:BB:CC:DD:EE:01', // Eddystone
        rawDistance: 1.2,
        filteredDistance: 1.2,
        rssi: -60,
        lastSeen: now,
      )..bearing = 45.0,
      BeaconState(
        id: 'AA:BB:CC:DD:EE:02', // iBeacon
        rawDistance: 2.0,
        filteredDistance: 2.0,
        rssi: -65,
        lastSeen: now,
      ),
      BeaconState(
        id: 'AA:BB:CC:DD:EE:03', // Eddystone with AoA
        rawDistance: 3.0,
        filteredDistance: 3.0,
        rssi: -70,
        lastSeen: now,
      )..bearing = 120.0,
    ];

    // Mock positions (like a triangle layout)
    mockBeaconPositions['AA:BB:CC:DD:EE:01'] = const Offset(0, 0);
    mockBeaconPositions['AA:BB:CC:DD:EE:02'] = const Offset(4, 0);
    mockBeaconPositions['AA:BB:CC:DD:EE:03'] = const Offset(2, 3);

    // Populate beacon states + found list (for UI)
    for (var b in dummyBeacons) {
      _beaconStates[b.id] = b;

      // Create a fake Observation for UI display
      _found[b.id] = Observation(
        id: b.id,
        type: b.id.endsWith('01') || b.id.endsWith('03') ? 'Eddystone' : 'iBeacon',
        info: b.id.endsWith('01')
            ? '(010203040506 / 0001)'
            : (b.id.endsWith('02') ? '(2f23... / 1 / 1)' : '(010203040506 / 0002)'),
        rssi: b.rssi,
        seenAt: b.lastSeen,
      );
    }

    // Update UI and calculate trilateration
    setState(() {
      _list
        ..clear()
        ..addAll(_found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
    });

    debugPrint('Dummy beacons loaded: ${_beaconStates.length}');
    _updateUserPosition();
    _simulateRssiFluctuation();

  }


  // -------------------------
  // scanning pipeline
  // - parse advertisement properly (iBeacon/Eddystone)
  // - pass AoA and observation into _processObservation
  // -------------------------
  Future<void> _startScan() async {
    if (_isScanning) return;

    // Step 1 — Check permissions (no dialog spam)
    final ok = await _ensurePermissions(showRationaleIfNeeded: true);
    if (!ok) return;

    // Step 2 — Reset scanning data
    _found.clear();
    _list.clear();
    _beaconStates.clear();
    mockBeaconPositions.clear();
    _assignedDemoCount = 0;

    setState(() => _isScanning = true);
    debugPrint("🚀 Scan started | Mode: $_scanMode");

    // Step 3 — Start periodic UI updater
    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(_uiTick, (_) {
      if (!mounted || !_isScanning) return;
      _updateUserPosition();
      setState(() {
        _list
          ..clear()
          ..addAll(_found.values.toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi)));
      });
    });

    // Step 4 — Dummy mode ON
    const bool useDummyBeacons = true;
    if (useDummyBeacons) {
      debugPrint("🧪 Using dummy beacons...");
      _loadDummyBeacons();
      return;
    }

    // Step 5 — Real BLE scan (disabled for now)
    try {
      _scanSub = _ble
          .scanForDevices(withServices: [], scanMode: _scanMode)
          .listen((d) {
        final obs = parseAdvertisement(
          id: d.id,
          rssi: d.rssi,
          manufacturerData: d.manufacturerData is Uint8List
              ? d.manufacturerData as Uint8List
              : (d.manufacturerData != null
              ? Uint8List.fromList(
              List<int>.from(d.manufacturerData as List<int>))
              : null),
          serviceData: d.serviceData is Map<Uuid, Uint8List>
              ? Map<Uuid, Uint8List>.from(d.serviceData)
              : (d.serviceData != null
              ? Map<Uuid, Uint8List>.from(
            (d.serviceData as Map).map(
                  (k, v) => MapEntry(
                k as Uuid,
                Uint8List.fromList(List<int>.from(v)),
              ),
            ),
          )
              : null),
        );

        if (obs == null) {
          // Unknown BLE device
          final unk = Observation(
            id: d.id,
            type: "BLE",
            info: "(raw)",
            rssi: d.rssi,
            seenAt: DateTime.now(),
          );

          _found[d.id] =
              _found[d.id]?.copyUpdated(rssi: unk.rssi, seenAt: unk.seenAt) ??
                  unk;

          return;
        }

        // AoA extraction
        double? aoa;
        try {
          if (d.manufacturerData != null &&
              (d.manufacturerData as Uint8List).isNotEmpty) {
            aoa = tryExtractAoAFromBytes(
              List<int>.from(d.manufacturerData as Uint8List),
            );
          }
        } catch (_) {}

        if (aoa == null && d.serviceData != null) {
          for (var e in d.serviceData.entries) {
            aoa = tryExtractAoAFromBytes(List<int>.from(e.value));
            if (aoa != null) break;
          }
        }

        // Update UI list
        final existing = _found[d.id];
        _found[d.id] = existing != null
            ? existing.copyUpdated(rssi: obs.rssi, seenAt: obs.seenAt)
            : obs;

        // Process distance filtering
        _processObservation(obs, aoa: aoa);
      }, onError: (e) {
        debugPrint("❌ Scan error: $e");
      });
    } catch (e) {
      _snack("Error: $e");
    }
  }




  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _uiTicker?.cancel();
    if (mounted) setState(() => _isScanning = false);
    debugPrint('Scan stopped.');
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // -------------------------
  // UI
  // -------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Beacon Scanner'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<ScanMode>(
              dropdownColor: Colors.grey[900],
              value: _scanMode,
              icon: const Icon(Icons.tune, color: Colors.white),
              items: const [
                DropdownMenuItem(value: ScanMode.lowPower, child: Text('Low Power', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: ScanMode.balanced, child: Text('Balanced', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: ScanMode.lowLatency, child: Text('Aggressive', style: TextStyle(color: Colors.white))),
              ],
              onChanged: (mode) async {
                if (mode == null) return;
                setState(() => _scanMode = mode);
                debugPrint('Scan mode changed to: $_scanMode');
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
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.grey[900],
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text('Accuracy: $_accuracy', style: const TextStyle(color: Colors.orangeAccent)),
                Text(
                  _userPosition != null ? 'Position: (${_userPosition!.dx.toStringAsFixed(2)}, ${_userPosition!.dy.toStringAsFixed(2)})' : 'Position: — (No beacons or calculating...)',
                  style: TextStyle(color: _userPosition != null ? Colors.lightGreenAccent : Colors.redAccent),
                ),
                Text('Beacons used: $_beaconsUsed', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          Expanded(
            child: _list.isEmpty
                ? const Center(
              child: Text('No beacons detected yet.\nTap “Scan” to start.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
            )
                : ListView.builder(
              itemCount: _list.length,
              itemBuilder: (_, i) {
                final o = _list[i];
                final state = _beaconStates[o.id];
                return BeaconTile(
                  position: mockBeaconPositions[o.id],
                  observation: o,
                  state: state,
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _isScanning ? Colors.redAccent : Colors.greenAccent,
        onPressed: _isScanning ? _stopScan : _startScan,
        icon: Icon(_isScanning ? Icons.stop : Icons.search, color: Colors.black),
        label: Text(_isScanning ? 'Stop' : 'Scan', style: const TextStyle(color: Colors.black)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}