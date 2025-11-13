import 'dart:async';
import 'dart:math' as math;
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
import '../widgets/beacon_tile.dart';


class BeaconScannerScreen extends StatefulWidget {
  const BeaconScannerScreen({super.key});

  @override
  State<BeaconScannerScreen> createState() => _BeaconScannerScreenState();
}

class _BeaconScannerScreenState extends State<BeaconScannerScreen> {
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
    // 🔹 First, check if permissions are already granted
    final bluetoothGranted = await Permission.bluetooth.isGranted;
    final scanGranted = await Permission.bluetoothScan.isGranted;
    final connectGranted = await Permission.bluetoothConnect.isGranted;
    final locationGranted = await Permission.locationWhenInUse.isGranted;
    final locationOn = await Geolocator.isLocationServiceEnabled();

    // ✅ All good — no need to show dialog again
    if (bluetoothGranted && scanGranted && connectGranted && locationGranted && locationOn) {
      debugPrint('✅ Permissions already granted.');
      return true;
    }

    // 🔹 If not granted and allowed to show rationale
    if (showRationaleIfNeeded) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
            'This app needs Bluetooth and Location permissions to detect nearby beacons.\n\n'
                '• Bluetooth is required to scan BLE advertisements (iBeacon & Eddystone)\n'
                '• Location is required by Android to allow BLE scanning\n\n'
                'Without these, the app cannot detect beacons around you.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Continue')),
          ],
        ),
      );
    }

    // 🔹 Now actually request permissions
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final denied = statuses.values.any((p) => p.isDenied);
    final permanentlyDenied = statuses.values.any((p) => p.isPermanentlyDenied);

    if (permanentlyDenied || !locationOn) {
      setState(() => _isScanning = false);
      await _showRationale(permanentlyDenied: permanentlyDenied, locationOn: locationOn);
      _snack('Bluetooth or Location is not enabled. Please enable them to start scanning.');
      return false;
    }

    if (denied) {
      setState(() => _isScanning = false);
      _snack('Bluetooth & Location permissions are required to start scanning.');
      return false;
    }

    debugPrint('✅ Permissions granted after request.');
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
    // calculate raw distance from RSSI using your helper
    final rawDist = estimateDistanceFromRssi(obs.rssi, txPower: txPower);

    // store or update BeaconState
    final existing = _beaconStates[obs.id];
    if (existing == null) {
      // new beacon
      final kalman = KalmanFilter1D(estimate: rawDist);
      final bs = BeaconState(
        id: obs.id,
        rawDistance: rawDist,
        filteredDistance: rawDist,
        rssi: obs.rssi,
        lastSeen: DateTime.now(),
      );
      // attach extras on your model (if available fields)
      try {
        // attempt to set optional fields if they exist
        bs.kalman = kalman;
        bs.bearing = aoa;
      } catch (_) {}
      _beaconStates[obs.id] = bs;

      // Auto assign a demo position if you haven't assigned physical coordinates for that id
      if (!mockBeaconPositions.containsKey(obs.id) && _assignedDemoCount < _demoPositions.length) {
        mockBeaconPositions[obs.id] = _demoPositions[_assignedDemoCount];
        _assignedDemoCount++;
      }

      debugPrint('New beacon detected: ${obs.id} | RSSI: ${obs.rssi} | rawDist: ${rawDist.toStringAsFixed(2)}m AoA:${aoa?.toStringAsFixed(1) ?? "—"}');
    } else {
      double filtered;
      if (useKalman) {
        try {
          existing.kalman ??= KalmanFilter1D(estimate: existing.filteredDistance);
          filtered = existing.kalman!.update(rawDist);
        } catch (_) {
          filtered = ewma(existing.filteredDistance, rawDist, alpha);
        }
      } else {
        filtered = ewma(existing.filteredDistance, rawDist, alpha);
      }

      // clamp jumps
      filtered = clampJump(existing.filteredDistance, filtered, maxJump);

      // update fields
      existing.update(obs.rssi, rawDist);
      existing.filteredDistance = filtered;
      // overwrite AoA if present (beacon advert AoA is authoritative)
      if (aoa != null) {
        existing.bearing = aoa;
      }
      existing.lastSeen = DateTime.now();

      debugPrint(
          '[${useKalman ? "Kalman" : "EWMA"}] '
              '${obs.type} ${obs.id}: '
              'RSSI ${obs.rssi}dBm → '
              'raw ${rawDist.toStringAsFixed(2)}m → '
              'filtered ${filtered.toStringAsFixed(2)}m '
              '${aoa != null ? "AoA ${aoa.toStringAsFixed(1)}°" : ""}'
      );
    }

    // keep observation map for UI display (distance in list should reflect filtered distance later)
    _found[obs.id] = _found[obs.id] != null
        ? _found[obs.id]!.copyUpdated(rssi: obs.rssi, seenAt: obs.seenAt)
        : obs;
  }

  // -------------------------
  // Position update (use only best 3 beacons for trilateration)
  // -------------------------
  void _updateUserPosition() {
    final now = DateTime.now();
    final fixes = <BeaconFix>[];

    // 1️⃣ Collect valid, non-stale, non-weak beacons
    for (final entry in _beaconStates.entries) {
      final id = entry.key;
      final state = entry.value;
      final pos = mockBeaconPositions[id];
      if (pos == null) continue;

      final age = now.difference(state.lastSeen).inSeconds;
      if (age > staleAfterSeconds || state.rssi < -95) continue;

      fixes.add(BeaconFix(pos, state.filteredDistance));
    }

    // 2️⃣ Sort beacons by distance
    fixes.sort((a, b) => a.dist.compareTo(b.dist));

    // 3️⃣ Handle cases by beacon count
    if (fixes.isEmpty) {
      _userPosition = null;
      _accuracy = "No beacons detected";
      _beaconsUsed = 0;
      debugPrint('No valid beacons found for triangulation.');
    } else if (fixes.length == 1) {
      _userPosition = null;
      _accuracy = "Very poorly accurate (1 beacon)";
      _beaconsUsed = 1;
      debugPrint('Only 1 beacon available, cannot trilaterate.');
    } else if (fixes.length == 2) {
      // Use helper → estimate midpoint projection
      _userPosition = estimateFromTwo(fixes[0], fixes[1]);
      _accuracy = "Medium accuracy (2 beacons)";
      _beaconsUsed = 2;
      debugPrint('Estimated position (2 beacons): $_userPosition');
    } else {
      //  Use trilateration from your utils
      final best = fixes.take(3).toList();
      final trilaterated = trilaterate(best[0], best[1], best[2]);

      //  Optional AoA refinement (use combineDistanceAndBearing)
      final withAoA = _beaconStates.values
          .where((b) => b.bearing != null && mockBeaconPositions[b.id] != null)
          .take(3)
          .toList();

      if (withAoA.length >= 2) {
        final refined = combineDistanceAndBearing(
          {for (var b in withAoA) b.id: BeaconFix(mockBeaconPositions[b.id]!, b.filteredDistance)},
          {for (var b in withAoA) b.id: b.bearing!},
        );

        if (refined != null) {
          _userPosition = trilaterated != null
              ? Offset(
            (trilaterated.dx + refined.dx) / 2,
            (trilaterated.dy + refined.dy) / 2,
          )
              : refined;
          debugPrint(" AoA refined position → $_userPosition");
        } else {
          _userPosition = trilaterated;
        }
      } else {
        _userPosition = trilaterated;
      }

      _accuracy = "Highly accurate (3+ beacons)";
      _beaconsUsed = fixes.length;
      debugPrint(' Trilaterated using ${best.length} beacons → Pos: $_userPosition');
    }

    // 6️⃣ Always refresh UI
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

    debugPrint('Dummy simulation interval: ${updateInterval.inMilliseconds}ms');

    // Create periodic timer — it auto-stops when _isScanning becomes false
    Timer.periodic(updateInterval, (timer) {
      if (!_isScanning) {
        timer.cancel(); // ✅ stop the periodic loop
        debugPrint('Dummy simulation stopped.');
        return;
      }

      for (final entry in _beaconStates.entries) {
        final beacon = entry.value;

        // Simulate ±5 dBm fluctuation
        final noise = (random.nextDouble() * 10) - 5;
        final newRssi = (beacon.rssi + noise).round();
        final newDistance = estimateDistanceFromRssi(newRssi, txPower: -59);

        // Update observation
        final obs = Observation(
          id: beacon.id,
          type: _found[beacon.id]?.type ?? 'Eddystone',
          info: _found[beacon.id]?.info ?? '',
          rssi: newRssi,
          seenAt: DateTime.now(),
        );

        _processObservation(obs, aoa: beacon.bearing);
      }

      _updateUserPosition();
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

    // 🟡 Step 1: Ensure permissions first
    final ok = await _ensurePermissions();
    if (!ok) return; // ❌ Stop immediately if not allowed

    // 🟢 Step 2: Prepare scanning state
    _found.clear();
    _list.clear();
    _beaconStates.clear();
    mockBeaconPositions.clear();
    _assignedDemoCount = 0;

    setState(() => _isScanning = true);
    debugPrint('Starting scan mode: $_scanMode');

    // 🕓 Step 3: Periodic UI refresh for position updates
    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(_uiTick, (_) {
      if (!mounted || !_isScanning) return;
      _updateUserPosition();
      setState(() {
        _list
          ..clear()
          ..addAll(_found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
      });
    });

    // 🔹 Step 4: Use dummy data for mock scanning
    const bool useDummyBeacons = true;

    if (useDummyBeacons) {
      debugPrint('Using dummy beacons instead of real BLE scan');
      _loadDummyBeacons();
      return;
    }

    // 🟣 Step 5: Real BLE scan (kept commented for later)
    // try {
    //   _scanSub = _ble.scanForDevices(withServices: [], scanMode: _scanMode).listen(
    //     (d) {
    //       final obs = _parseAdvertisement(
    //         id: d.id,
    //         rssi: d.rssi,
    //         manufacturerData: (d.manufacturerData is Uint8List)
    //             ? d.manufacturerData as Uint8List
    //             : (d.manufacturerData != null
    //                 ? Uint8List.fromList(List<int>.from(d.manufacturerData as List<int>))
    //                 : null),
    //         serviceData: (d.serviceData is Map<Uuid, Uint8List>)
    //             ? Map<Uuid, Uint8List>.from(d.serviceData as Map<Uuid, Uint8List>)
    //             : (d.serviceData != null
    //                 ? Map<Uuid, Uint8List>.from(
    //                     (d.serviceData as Map).map((k, v) => MapEntry(
    //                           k as Uuid,
    //                           Uint8List.fromList(List<int>.from(v as List<int>)),
    //                         )),
    //                   )
    //                 : null),
    //       );

    //       if (obs != null) {
    //         double? aoa;
    //         try {
    //           if (d.manufacturerData != null && (d.manufacturerData as Uint8List).isNotEmpty) {
    //             aoa = _tryExtractAoAFromBytes(List<int>.from(d.manufacturerData as Uint8List));
    //           }
    //         } catch (_) {}

    //         if (aoa == null && d.serviceData != null) {
    //           for (final e in d.serviceData.entries) {
    //             aoa ??= _tryExtractAoAFromBytes(List<int>.from(e.value));
    //             if (aoa != null) break;
    //           }
    //         }

    //         final existing = _found[d.id];
    //         _found[d.id] = existing != null
    //             ? existing.copyUpdated(rssi: obs.rssi, seenAt: obs.seenAt)
    //             : obs;

    //         _processObservation(obs, aoa: aoa);
    //       } else {
    //         final unk = Observation(
    //             id: d.id, type: 'BLE', info: '(raw)', rssi: d.rssi, seenAt: DateTime.now());
    //         final existing = _found[d.id];
    //         _found[d.id] = existing != null
    //             ? existing.copyUpdated(rssi: unk.rssi, seenAt: unk.seenAt)
    //             : unk;
    //       }
    //     },
    //     onError: (e) => debugPrint(' Scan error: $e'),
    //   );
    // } catch (e) {
    //   _snack('Error: $e');
    // }
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

        ],
      ),
      body: Column(
        children: [
          SizedBox(height: 100,child: Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children: [
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
            DropdownButtonHideUnderline(
              child: DropdownButton<bool>(
                dropdownColor: Colors.grey[900],
                value: useKalman,
                icon: const Icon(Icons.filter_alt, color: Colors.white),
                items: const [
                  DropdownMenuItem(value: false, child: Text('EWMA', style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: true, child: Text('Kalman', style: TextStyle(color: Colors.white))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => useKalman = v);
                  debugPrint('Filter changed → ${useKalman ? "Kalman" : "EWMA"}');
                },
              ),
            ),
          ],),),
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