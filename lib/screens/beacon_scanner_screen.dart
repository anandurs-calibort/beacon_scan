import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/helpers/filters.dart';
import '../core/models/beacon_fix.dart';
import '../core/models/beacon_observation_model.dart';
import '../core/models/beacon_state.dart';
import '../core/models/kalman_filter.dart';
import '../core/utils/beacon_math.dart';
import 'dart:typed_data';

import '../core/utils/beacon_mock.dart';


//todo below shows the scanned and distnce
// class BeaconScannerScreen extends StatefulWidget {
//   const BeaconScannerScreen({super.key});
//
//   @override
//   State<BeaconScannerScreen> createState() => _BeaconScannerScreenState();
// }
//
// class _BeaconScannerScreenState extends State<BeaconScannerScreen> {
//   final _ble = FlutterReactiveBle();
//   StreamSubscription<DiscoveredDevice>? _scanSub;
//   Timer? _uiTicker;
//
//   bool _isScanning = false;
//   final Map<String, Observation> _found = {};
//   final List<Observation> _list = [];
//
//   // Default mode and refresh rate
//   ScanMode _scanMode = ScanMode.balanced;
//   Duration _uiTick = const Duration(seconds: 1);
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
//       _ensurePermissions();
//     },);
//   }
//
//   // ------------------------------------------------------------
//   // Permissions
//   // ------------------------------------------------------------
//   Future<void> _ensurePermissions() async {
//     // 🟢 Step 1: Show user-friendly rationale before system prompt
//     await showDialog(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         title: const Text('Permission Required'),
//         content: const Text(
//           'This app needs Bluetooth and Location permissions to detect nearby beacons.\n\n'
//               '• Bluetooth is required to scan BLE advertisements (iBeacon & Eddystone)\n'
//               '• Location is required by Android to allow BLE scanning\n\n'
//               'Without these, the app cannot detect beacons around you.',
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(ctx),
//             child: const Text('Continue'),
//           ),
//         ],
//       ),
//     );
//
//     // 🟢 Step 2: Request the actual permissions
//     final statuses = await [
//       Permission.bluetooth,
//       Permission.bluetoothScan,
//       Permission.bluetoothConnect,
//       Permission.locationWhenInUse,
//     ].request();
//
//     final denied = statuses.values.any((p) => p.isDenied);
//     final permanentlyDenied = statuses.values.any((p) => p.isPermanentlyDenied);
//     final locationOn = await Geolocator.isLocationServiceEnabled();
//
//     // 🟢 Step 3: Handle permission outcomes
//     if (permanentlyDenied || !locationOn) {
//       await _showRationale(
//         permanentlyDenied: permanentlyDenied,
//         locationOn: locationOn,
//       );
//     } else if (denied) {
//       _snack('Bluetooth & Location permissions are required to start scanning.');
//     } else {
//       debugPrint('✅ Permissions granted.');
//     }
//   }
//
//
//   Future<void> _showRationale({
//     required bool permanentlyDenied,
//     required bool locationOn,
//   }) async {
//     await showDialog(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         title: const Text('Permissions & Location needed'),
//         content: Text(
//           '${!locationOn ? '• Turn on Location Services\n' : ''}'
//               '${permanentlyDenied ? '• Enable Bluetooth & Location in Settings.\n' : '• Allow Bluetooth & Location to scan for beacons.\n'}'
//               'Scanning uses Bluetooth LE advertisements (no pairing).',
//         ),
//         actions: [
//           if (!locationOn)
//             TextButton(
//               onPressed: () => Geolocator.openLocationSettings(),
//               child: const Text('Open Location Settings'),
//             ),
//           if (permanentlyDenied)
//             TextButton(
//               onPressed: () => openAppSettings(),
//               child: const Text('Open App Settings'),
//             ),
//           TextButton(
//             onPressed: () => Navigator.pop(ctx),
//             child: const Text('OK'),
//           ),
//         ],
//       ),
//     );
//   }
//
//   List<BeaconFix> _pickBest3(List<BeaconFix> fixes) {
//     fixes.sort((a, b) => a.dist.compareTo(b.dist));
//     return fixes.take(3).toList();
//   }
//
//   Offset? _trilaterate(BeaconFix a, BeaconFix b, BeaconFix c) {
//     final x1 = 0.0, y1 = 0.0, r1 = a.dist;
//     final x2 = b.pos.dx - a.pos.dx;
//     final y2 = b.pos.dy - a.pos.dy;
//     final r2 = b.dist;
//     final x3 = c.pos.dx - a.pos.dx;
//     final y3 = c.pos.dy - a.pos.dy;
//     final r3 = c.dist;
//
//     final A11 = -2 * x2;
//     final A12 = -2 * y2;
//     final A21 = -2 * x3;
//     final A22 = -2 * y3;
//
//     final B1 = r1 * r1 - r2 * r2 + x2 * x2 + y2 * y2;
//     final B2 = r1 * r1 - r3 * r3 + x3 * x3 + y3 * y3;
//
//     final det = A11 * A22 - A12 * A21;
//     if (det.abs() < 1e-6) return null;
//
//     final px = (A22 * B1 - A12 * B2) / det;
//     final py = (-A21 * B1 + A11 * B2) / det;
//
//     return Offset(px + a.pos.dx, py + a.pos.dy);
//   }
//   //demo constant values
//   final Map<String, Offset> beaconPositions = {
//     'BEACON_A': Offset(0, 0),
//     'BEACON_B': Offset(4, 0),
//     'BEACON_C': Offset(2, 3),
//   };
//   Offset _estimateFromTwo(BeaconFix a, BeaconFix b) {
//     final dx = b.pos.dx - a.pos.dx;
//     final dy = b.pos.dy - a.pos.dy;
//     final d = math.sqrt(dx * dx + dy * dy).clamp(1e-6, double.infinity);
//     final ux = dx / d;
//     final uy = dy / d;
//     return Offset(a.pos.dx + ux * a.dist, a.pos.dy + uy * a.dist);
//   }
//
//   String _accuracyFromCount(int n) {
//     if (n >= 3) return 'Highly accurate';
//     if (n == 2) return 'Low accurate';
//     if (n == 1) return 'Very poorly accurate';
//     return 'Unknown';
//   }
//
//   // ------------------------------------------------------------
//   // Beacon Parsing (iBeacon / Eddystone)
//   // ------------------------------------------------------------
//   Observation? _parseBeacon(String id, int rssi, List<int> data, {Uuid? serviceUuid}) {
//     if (data.isEmpty) return null;
//
//     // Convert data bytes to hex for optional debugging
//     final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
//     debugPrint('📡 Raw advertisement from $id (${data.length} bytes): $hexData');
//     debugPrint('➡️ RSSI: $rssi  ServiceUUID: ${serviceUuid?.toString() ?? "N/A"}');
//
//     // --- Detect iBeacon packets ---
//     for (int i = 0; i <= data.length - 22; i++) {
//       final applePrefix = i + 3 < data.length &&
//           data[i] == 0x4C &&
//           data[i + 1] == 0x00 &&
//           data[i + 2] == 0x02 &&
//           data[i + 3] == 0x15;
//
//       final barePrefix =
//           i + 1 < data.length && data[i] == 0x02 && data[i + 1] == 0x15;
//
//       if (applePrefix || barePrefix) {
//         final offset = applePrefix ? i + 4 : i + 2;
//         if (offset + 20 <= data.length) {
//           final uuidBytes = data.sublist(offset, offset + 16);
//           final major = (data[offset + 16] << 8) | data[offset + 17];
//           final minor = (data[offset + 18] << 8) | data[offset + 19];
//           final uuid = _bytesToUuid(uuidBytes);
//
//           debugPrint('✅ [iBeacon Detected]');
//           debugPrint('   ↳ UUID: $uuid');
//           debugPrint('   ↳ Major: $major | Minor: $minor');
//           debugPrint('   ↳ RSSI: $rssi dBm');
//
//           return Observation(
//             id: id,
//             type: 'iBeacon',
//             info: '($uuid / $major / $minor)',
//             rssi: rssi,
//             seenAt: DateTime.now(),
//           );
//         }
//       }
//     }
//
//     // --- Detect Eddystone UID ---
//     if (serviceUuid != null &&
//         serviceUuid.toString().toUpperCase().contains('FEAA') &&
//         data.isNotEmpty &&
//         data[0] == 0x00 &&
//         data.length >= 18) {
//       final namespace = data
//           .sublist(2, 12)
//           .map((b) => b.toRadixString(16).padLeft(2, '0'))
//           .join()
//           .toUpperCase();
//       final instance = data
//           .sublist(12, 18)
//           .map((b) => b.toRadixString(16).padLeft(2, '0'))
//           .join()
//           .toUpperCase();
//
//       debugPrint('✅ [Eddystone Detected]');
//       debugPrint('   ↳ Namespace: $namespace');
//       debugPrint('   ↳ Instance: $instance');
//       debugPrint('   ↳ RSSI: $rssi dBm');
//
//       return Observation(
//         id: id,
//         type: 'Eddystone',
//         info: '($namespace / $instance)',
//         rssi: rssi,
//         seenAt: DateTime.now(),
//       );
//     }
//
//     debugPrint('❌ No known beacon pattern detected for device: $id\n');
//     return null;
//   }
//
//
//   String _bytesToUuid(List<int> bytes) {
//     final hex = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
//     return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
//   }
//
//   // ------------------------------------------------------------
//   // Update refresh rate based on scan mode
//   // ------------------------------------------------------------
//   void _updateTickForMode(ScanMode mode) {
//     switch (mode) {
//       case ScanMode.lowPower:
//         _uiTick = const Duration(seconds: 3); // ~0.33 Hz
//         break;
//       case ScanMode.balanced:
//         _uiTick = const Duration(seconds: 1); // 1 Hz
//         break;
//       case ScanMode.lowLatency:
//         _uiTick = const Duration(milliseconds: 500); // 2 Hz
//         break;
//       default:
//         _uiTick = const Duration(seconds: 1);
//     }
//   }
//
//   // ------------------------------------------------------------
//   // BLE Scanning Logic
//   // ------------------------------------------------------------
//   Future<void> _startScan() async {
//     if (_isScanning) return;
//
//     _found.clear();
//     _list.clear();
//     setState(() => _isScanning = true);
//     _snack('Scanning (${_labelForMode(_scanMode)})');
//
//     // Update refresh rate dynamically
//     _updateTickForMode(_scanMode);
//
//     // Refresh UI periodically
//     _uiTicker?.cancel();
//     _uiTicker = Timer.periodic(_uiTick, (_) {
//       if (!mounted) return;
//       setState(() {
//         _list
//           ..clear()
//           ..addAll(_found.values.toList()
//             ..sort((a, b) => b.rssi.compareTo(a.rssi)));
//       });
//     });
//
//     try {
//       _scanSub = _ble
//           .scanForDevices(withServices: [], scanMode: _scanMode)
//           .listen((d) {
//         Observation? obs;
//
//         // iBeacon detection
//         if (d.manufacturerData.isNotEmpty) {
//           obs = _parseBeacon(d.id, d.rssi, d.manufacturerData);
//         }
//
//         // Eddystone detection
//         if (obs == null && d.serviceData.isNotEmpty) {
//           for (final entry in d.serviceData.entries) {
//             obs ??=
//                 _parseBeacon(d.id, d.rssi, entry.value, serviceUuid: entry.key);
//           }
//         }
//
//         // Update observation map
//         if (obs != null) {
//           final existing = _found[d.id];
//           _found[d.id] = existing != null
//               ? existing.copyUpdated(rssi: obs.rssi, seenAt: obs.seenAt)
//               : obs;
//         }
//       }, onError: (e) => _snack('Scan error: $e'));
//     } catch (e) {
//       _snack('Exception: $e');
//       await _stopScan();
//     }
//   }
//
//   Future<void> _stopScan() async {
//     await _scanSub?.cancel();
//     _uiTicker?.cancel();
//     if (mounted) setState(() => _isScanning = false);
//   }
//
//   @override
//   void dispose() {
//     _stopScan();
//     super.dispose();
//   }
//
//   // ------------------------------------------------------------
//   // UI
//   // ------------------------------------------------------------
//   String _labelForMode(ScanMode m) {
//     switch (m) {
//       case ScanMode.lowPower:
//         return 'Low Power';
//       case ScanMode.balanced:
//         return 'Balanced';
//       case ScanMode.lowLatency:
//         return 'Aggressive';
//       default:
//         return m.name;
//     }
//   }
//
//   void _snack(String msg) =>
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         title: const Text('Beacon Scanner'),
//         backgroundColor: Colors.black,
//         foregroundColor: Colors.white,
//         actions: [
//           // Scan Mode Selector
//           DropdownButtonHideUnderline(
//             child: DropdownButton<ScanMode>(
//               dropdownColor: Colors.grey[900],
//               value: _scanMode,
//               icon: const Icon(Icons.tune, color: Colors.white),
//               items: const [
//                 DropdownMenuItem(
//                     value: ScanMode.lowPower,
//                     child: Text('Low Power',
//                         style: TextStyle(color: Colors.white))),
//                 DropdownMenuItem(
//                     value: ScanMode.balanced,
//                     child: Text('Balanced',
//                         style: TextStyle(color: Colors.white))),
//                 DropdownMenuItem(
//                     value: ScanMode.lowLatency,
//                     child: Text('Aggressive',
//                         style: TextStyle(color: Colors.white))),
//               ],
//               onChanged: (mode) async {
//                 if (mode == null) return;
//                 setState(() => _scanMode = mode);
//                 if (_isScanning) {
//                   await _stopScan();
//                   await Future.delayed(const Duration(milliseconds: 200));
//                   await _startScan();
//                 }
//               },
//             ),
//           ),
//         ],
//       ),
//       body: _list.isEmpty
//           ? const Center(
//         child: Text(
//           'No beacons detected yet.\nTap “Scan” to start.',
//           textAlign: TextAlign.center,
//           style: TextStyle(color: Colors.white54),
//         ),
//       )
//           : ListView.builder(
//         itemCount: _list.length,
//         itemBuilder: (_, i) {
//           final o = _list[i];
//           return ListTile(
//             leading: Icon(
//               o.type == 'iBeacon'
//                   ? Icons.bluetooth_searching
//                   : Icons.radio,
//               color: o.type == 'iBeacon'
//                   ? Colors.blueAccent
//                   : Colors.orangeAccent,
//             ),
//             title: Text(
//               '${o.type} ${o.info}',
//               style: const TextStyle(color: Colors.white),
//             ),
//             subtitle: Text(
//               'Device: ${o.id}\nMode: ${_labelForMode(_scanMode)}',
//               style: const TextStyle(color: Colors.white54),
//             ),
//             trailing: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               crossAxisAlignment: CrossAxisAlignment.end,
//               children: [
//                 Text(
//                   '${o.rssi} dBm',
//                   style: const TextStyle(color: Colors.greenAccent),
//                 ),
//                 Text(
//                   '~${o.distance.toStringAsFixed(2)} m',
//                   style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
//                 ),
//               ],
//             ),
//
//           );
//         },
//       ),
//       floatingActionButton:
//       FloatingActionButton.extended(
//         backgroundColor:
//         _isScanning ? Colors.redAccent : Colors.greenAccent,
//         onPressed: _isScanning ? _stopScan : _startScan,
//         icon:
//         Icon(_isScanning ? Icons.stop : Icons.search, color: Colors.black),
//         label: Text(_isScanning ? 'Stop' : 'Scan',
//             style: const TextStyle(color: Colors.black)),
//       ),
//       floatingActionButtonLocation:
//       FloatingActionButtonLocation.centerFloat,
//     );
//   }
// }
//

//todo above _ show the list of scanned items with distance and rssi

// class BeaconScannerScreen extends StatefulWidget {
//   const BeaconScannerScreen({super.key});
//
//   @override
//   State<BeaconScannerScreen> createState() => _BeaconScannerScreenState();
// }
//
// class _BeaconScannerScreenState extends State<BeaconScannerScreen> {
//   final _ble = FlutterReactiveBle();
//   StreamSubscription<DiscoveredDevice>? _scanSub;
//   Timer? _uiTicker;
//
//   bool _isScanning = false;
//   final Map<String, Observation> _found = {};
//   final List<Observation> _list = [];
//
//   Offset? _userPosition;
//   String _accuracy = "No beacons detected";
//   int _beaconsUsed = 0;
//
//   ScanMode _scanMode = ScanMode.balanced;
//   Duration _uiTick = const Duration(seconds: 1);
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePermissions());
//   }
//
//   Future<void> _ensurePermissions() async {
//     await [
//       Permission.bluetooth,
//       Permission.bluetoothScan,
//       Permission.bluetoothConnect,
//       Permission.locationWhenInUse,
//     ].request();
//   }
//
//   // Trilateration logic (reuses imported helpers)
//   void _updateUserPosition() {
//     final fixes = <BeaconFix>[];
//
//     for (final obs in _found.values) {
//       final pos = mockBeaconPositions[obs.id];
//       if (pos != null) {
//         fixes.add(BeaconFix(pos, obs.distance.toDouble()));
//       }
//     }
//
//     fixes.sort((a, b) => a.dist.compareTo(b.dist));
//
//     if (fixes.isEmpty) {
//       _userPosition = null;
//       _accuracy = "No beacons detected";
//       _beaconsUsed = 0;
//     } else if (fixes.length == 1) {
//       _userPosition = null;
//       _accuracy = "Low accuracy (1 beacon considered)";
//       _beaconsUsed = 1;
//     } else if (fixes.length == 2) {
//       _userPosition = estimateFromTwo(fixes[0], fixes[1]);
//       _accuracy = "Medium accuracy (2 beacons considered)";
//       _beaconsUsed = 2;
//     } else {
//       final used = fixes.take(3).toList();
//       _userPosition = trilaterate(used[0], used[1], used[2]);
//       _accuracy = "High accuracy (3 beacons considered)";
//       _beaconsUsed = 3;
//     }
//
//     setState(() {});
//   }
//
//   Future<void> _startScan() async {
//     if (_isScanning) return;
//     _found.clear();
//     _list.clear();
//     setState(() => _isScanning = true);
//
//     _uiTicker?.cancel();
//     _uiTicker = Timer.periodic(_uiTick, (_) {
//       if (!mounted) return;
//       _updateUserPosition();
//       setState(() {
//         _list
//           ..clear()
//           ..addAll(_found.values.toList()
//             ..sort((a, b) => b.rssi.compareTo(a.rssi)));
//       });
//     });
//
//     try {
//       _scanSub = _ble.scanForDevices(withServices: [], scanMode: _scanMode).listen((d) {
//         Observation? obs;
//         if (d.manufacturerData.isNotEmpty) {
//           obs = Observation(
//             id: d.id,
//             type: 'iBeacon',
//             info: '(iBeacon)',
//             rssi: d.rssi,
//             seenAt: DateTime.now(),
//           );
//         }
//         if (obs != null) {
//           final existing = _found[d.id];
//           _found[d.id] = existing != null
//               ? existing.copyUpdated(rssi: obs.rssi, seenAt: obs.seenAt)
//               : obs;
//         }
//       });
//     } catch (e) {
//       _snack('Error: $e');
//     }
//   }
//
//   Future<void> _stopScan() async {
//     await _scanSub?.cancel();
//     _uiTicker?.cancel();
//     if (mounted) setState(() => _isScanning = false);
//   }
//
//   void _snack(String msg) =>
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         title: const Text('Beacon Scanner'),
//         backgroundColor: Colors.black,
//         foregroundColor: Colors.white,
//       ),
//       body: Column(
//         children: [
//           Container(
//             width: double.infinity,
//             color: Colors.grey[900],
//             padding: const EdgeInsets.all(12),
//             child: Column(
//               children: [
//                 Text('Accuracy: $_accuracy',
//                     style: const TextStyle(color: Colors.orangeAccent)),
//                 Text(
//                   _userPosition != null
//                       ? 'Position: (${_userPosition!.dx.toStringAsFixed(2)}, ${_userPosition!.dy.toStringAsFixed(2)})'
//                       : 'Position: — (No beacons or calculating...)',
//                   style: TextStyle(
//                       color: _userPosition != null
//                           ? Colors.lightGreenAccent
//                           : Colors.redAccent),
//                 ),
//                 Text('Beacons used: $_beaconsUsed',
//                     style: const TextStyle(color: Colors.white70)),
//               ],
//             ),
//           ),
//           Expanded(
//             child: _list.isEmpty
//                 ? const Center(
//               child: Text(
//                 'No beacons detected yet.\nTap “Scan” to start.',
//                 textAlign: TextAlign.center,
//                 style: TextStyle(color: Colors.white54),
//               ),
//             )
//                 : ListView.builder(
//               itemCount: _list.length,
//               itemBuilder: (_, i) {
//                 final o = _list[i];
//                 return ListTile(
//                   leading: Icon(
//                     o.type == 'iBeacon'
//                         ? Icons.bluetooth_searching
//                         : Icons.radio,
//                     color: o.type == 'iBeacon'
//                         ? Colors.blueAccent
//                         : Colors.orangeAccent,
//                   ),
//                   title: Text('${o.type} ${o.info}',
//                       style: const TextStyle(color: Colors.white)),
//                   subtitle: Text('Device: ${o.id}',
//                       style: const TextStyle(color: Colors.white54)),
//                   trailing: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     crossAxisAlignment: CrossAxisAlignment.end,
//                     children: [
//                       Text('${o.rssi} dBm',
//                           style:
//                           const TextStyle(color: Colors.greenAccent)),
//                       Text('~${o.distance.toStringAsFixed(2)} m',
//                           style: const TextStyle(
//                               color: Colors.orangeAccent, fontSize: 12)),
//                     ],
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//       floatingActionButton: FloatingActionButton.extended(
//         backgroundColor:
//         _isScanning ? Colors.redAccent : Colors.greenAccent,
//         onPressed: _isScanning ? _stopScan : _startScan,
//         icon: Icon(_isScanning ? Icons.stop : Icons.search,
//             color: Colors.black),
//         label: Text(_isScanning ? 'Stop' : 'Scan',
//             style: const TextStyle(color: Colors.black)),
//       ),
//       floatingActionButtonLocation:
//       FloatingActionButtonLocation.centerFloat,
//     );
//   }
// }

//todo filtering
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePermissions());
  }

  // Keep permission dialog behaviour like your original flow.
  Future<void> _ensurePermissions() async {
    // show rationale first
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
      _snack('Bluetooth & Location permissions are required to start scanning.');
    } else {
      debugPrint('✅ Permissions granted.');
    }
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
  // Helper filters & math
  // -------------------------
  double ewma(double prev, double sample, double a) => prev * (1 - a) + sample * a;

  double clampJump(double prev, double candidate, double maxJumpMeters) {
    final jump = (candidate - prev).abs();
    if (jump > maxJumpMeters) {
      // clamp to prev +/- maxJumpMeters (avoid unrealistic teleport jumps)
      return prev + (candidate > prev ? maxJumpMeters : -maxJumpMeters);
    }
    return candidate;
  }

  // -------------------------
  // Advertisement parsing
  // - handles Uint8List manufacturerData and Map<Uuid,Uint8List> serviceData
  // - returns an Observation if iBeacon or Eddystone found, otherwise null
  // - also extracts AoA angle when embedded
  // -------------------------
  Observation? _parseAdvertisement({
    required String id,
    required int rssi,
    required Uint8List? manufacturerData,
    required Map<Uuid, Uint8List>? serviceData,
  }) {
    // convert to List<int> defensively
    final manu = manufacturerData != null ? List<int>.from(manufacturerData) : <int>[];
    // debug hex
    if (manu.isNotEmpty) {
      final hex = manu.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
      debugPrint('📡 Manu($id): $hex');
    }
    if (serviceData != null && serviceData.isNotEmpty) {
      for (final e in serviceData.entries) {
        final hex = List<int>.from(e.value).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
        debugPrint('📡 Service ${e.key} ($id): $hex');
      }
    }

    // Try iBeacon pattern in manufacturer data
    // Apple iBeacon packet is: companyID 0x004C (0x4C 0x00) followed by 0x02 0x15, then 16 byte UUID, 2 byte major, 2 byte minor, 1 byte tx
    if (manu.length >= 25) {
      // search for sequence 0x4C 0x00 0x02 0x15 (Apple) or the short 0x02 0x15 sequence at some offset
      for (int i = 0; i <= manu.length - 22; i++) {
        final applePrefix = i + 3 < manu.length &&
            manu[i] == 0x4C &&
            manu[i + 1] == 0x00 &&
            manu[i + 2] == 0x02 &&
            manu[i + 3] == 0x15;
        final barePrefix = i + 1 < manu.length && manu[i] == 0x02 && manu[i + 1] == 0x15;

        if (applePrefix || barePrefix) {
          final offset = applePrefix ? i + 4 : i + 2;
          if (offset + 20 <= manu.length) {
            final uuidBytes = manu.sublist(offset, offset + 16);
            final major = (manu[offset + 16] << 8) | manu[offset + 17];
            final minor = (manu[offset + 18] << 8) | manu[offset + 19];
            final uuid = _bytesToUuid(uuidBytes);

            // Try read AoA from manufacturer trailing bytes (if any)
            final aoa = _tryExtractAoAFromBytes(manu);

            debugPrint('✅ [iBeacon Detected] $id  UUID:$uuid major:$major minor:$minor rssi:$rssi AoA:${aoa?.toStringAsFixed(1) ?? "—"}');
            final obs = Observation(id: id, type: 'iBeacon', info: '($uuid / $major / $minor)', rssi: rssi, seenAt: DateTime.now());
            // attach AoA to observation if your Observation supports it — else we will set it in BeaconState later
            return obs;
          }
        }
      }
    }

    // Try Eddystone UID in serviceData where service UUID FEAA is present and frame type 0x00 UID
    if (serviceData != null && serviceData.isNotEmpty) {
      for (final entry in serviceData.entries) {
        final svcUuid = entry.key;
        final bytes = List<int>.from(entry.value);
        // FEAA service indicates Eddystone
        if (svcUuid.toString().toUpperCase().contains('FEAA') && bytes.isNotEmpty) {
          final frameType = bytes[0];
          if (frameType == 0x00 && bytes.length >= 18) {
            // UID frame
            final namespace = bytes.sublist(2, 12).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
            final instance = bytes.sublist(12, 18).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
            final aoa = _tryExtractAoAFromBytes(bytes);

            debugPrint('✅ [Eddystone UID] $id  namespace:$namespace instance:$instance rssi:$rssi AoA:${aoa?.toStringAsFixed(1) ?? "—"}');
            return Observation(id: id, type: 'Eddystone', info: '($namespace / $instance)', rssi: rssi, seenAt: DateTime.now());
          }
          // other Eddystone frames (URL, TLM) are possible, ignore here
        }
      }
    }

    // No known pattern
    return null;
  }

  // Extract AoA from raw byte array (some beacons append angle in last two bytes as little-endian tenths of degree)
  double? _tryExtractAoAFromBytes(List<int> bytes) {
    // check last 2 bytes
    if (bytes.length >= 2) {
      final v = (bytes[bytes.length - 2] & 0xFF) | ((bytes[bytes.length - 1] & 0xFF) << 8);
      if (v > 0 && v <= 3600) return v / 10.0;
    }
    // fallback none
    return null;
  }

  String _bytesToUuid(List<int> bytes) {
    final hex = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
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

      debugPrint('🆕 New beacon detected: ${obs.id} | RSSI: ${obs.rssi} | rawDist: ${rawDist.toStringAsFixed(2)}m AoA:${aoa?.toStringAsFixed(1) ?? "—"}');
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

      debugPrint('📶 Updating beacon ${obs.id}: RSSI ${obs.rssi}, rawDist ${rawDist.toStringAsFixed(2)}m → filtered ${filtered.toStringAsFixed(2)}m AoA:${existing.bearing?.toStringAsFixed(1) ?? "—"}');
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

    // Collect valid beacons (non-stale, non-weak) with known positions
    for (final e in _beaconStates.entries) {
      final id = e.key;
      final state = e.value;
      final pos = mockBeaconPositions[id];
      if (pos == null) continue;

      final age = now.difference(state.lastSeen).inSeconds;
      if (age > staleAfterSeconds) continue;
      if (state.rssi < -95) continue;

      fixes.add(BeaconFix(pos, state.filteredDistance));
    }

    // Sort by distance, closest first
    fixes.sort((a, b) => a.dist.compareTo(b.dist));

    if (fixes.isEmpty) {
      _userPosition = null;
      _accuracy = "No beacons detected";
      _beaconsUsed = 0;
      debugPrint('🚫 No valid beacons found for triangulation.');
      setState(() {});
      return;
    }

    if (fixes.length == 1) {
      // One beacon only → cannot locate, show distance
      _userPosition = null;
      _accuracy = "Very poorly accurate (1 beacon)";
      _beaconsUsed = 1;
      debugPrint('📍 Only 1 beacon available, cannot trilaterate.');
      setState(() {});
      return;
    }

    if (fixes.length == 2) {
      // Two beacons → rough estimate (midpoint or 2-circle intersection)
      _userPosition = estimateFromTwo(fixes[0], fixes[1]);
      _accuracy = "Medium accuracy (2 beacons)";
      _beaconsUsed = 2;
      debugPrint('📐 Estimated position (2 beacons): $_userPosition');
      setState(() {});
      return;
    }

    // 3 or more → use trilateration on the 3 closest
    final best = fixes.take(3).toList();
    final trilaterated = trilaterate(best[0], best[1], best[2]);

    // Check for AoA-bearing beacons (optional refinement)
    final withAoA = _beaconStates.values
        .where((b) => b.bearing != null && mockBeaconPositions[b.id] != null)
        .take(3)
        .toList();

    if (withAoA.length >= 2) {
      final refined = _combineDistanceAndBearing(withAoA);
      if (refined != null) {
        _userPosition = trilaterated != null
            ? Offset(
          (trilaterated.dx + refined.dx) / 2,
          (trilaterated.dy + refined.dy) / 2,
        )
            : refined;
        debugPrint("🧭 AoA refined position → $_userPosition");
      } else {
        _userPosition = trilaterated;
      }
    } else {
      _userPosition = trilaterated;
    }

    _accuracy = "Highly accurate (3+ beacons)";
    _beaconsUsed = fixes.length;
    debugPrint('🎯 Trilaterated using ${best.length} beacons → Pos: $_userPosition');

    setState(() {});
  }


  // Combine distance + bearing by projecting each beacon bearing to a point at that distance and averaging
  Offset? _combineDistanceAndBearing(List<BeaconState> beacons) {
    if (beacons.length < 2) return null;
    final points = <Offset>[];
    for (final b in beacons) {
      final pos = mockBeaconPositions[b.id];
      if (pos == null || b.bearing == null) continue;
      points.add(_bearingToPoint(pos, b.bearing!, b.filteredDistance));
    }
    if (points.isEmpty) return null;
    final avgX = points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
    final avgY = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
    return Offset(avgX, avgY);
  }

  Offset _bearingToPoint(Offset origin, double bearingDeg, double dist) {
    final rad = bearingDeg * math.pi / 180.0;
    return Offset(origin.dx + dist * math.cos(rad), origin.dy + dist * math.sin(rad));
  }

  // -------------------------
  // scanning pipeline
  // - parse advertisement properly (iBeacon/Eddystone)
  // - pass AoA and observation into _processObservation
  // -------------------------
  Future<void> _startScan() async {
    if (_isScanning) return;

    _found.clear();
    _list.clear();
    _beaconStates.clear();
    mockBeaconPositions.clear();
    _assignedDemoCount = 0;
    setState(() => _isScanning = true);

    debugPrint('🚀 Starting scan mode: $_scanMode');

    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(_uiTick, (_) {
      if (!mounted) return;
      _updateUserPosition();
      setState(() {
        _list
          ..clear()
          ..addAll(_found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
      });
    });

    try {
      _scanSub = _ble.scanForDevices(withServices: [], scanMode: _scanMode).listen(
            (d) {
          // parse advertisement -> Observation
          // manufacturerData: Uint8List?  (may be empty)
          // serviceData: Map<Uuid, Uint8List>?
          final obs = _parseAdvertisement(
            id: d.id,
            rssi: d.rssi,
            manufacturerData: (d.manufacturerData is Uint8List) ? d.manufacturerData as Uint8List : (d.manufacturerData != null ? Uint8List.fromList(List<int>.from(d.manufacturerData as List<int>)) : null),
            serviceData: (d.serviceData is Map<Uuid, Uint8List>) ? Map<Uuid, Uint8List>.from(d.serviceData as Map<Uuid, Uint8List>) : (d.serviceData != null ? Map<Uuid, Uint8List>.from((d.serviceData as Map).map((k, v) => MapEntry(k as Uuid, Uint8List.fromList(List<int>.from(v as List<int>))))) : null),
          );

          if (obs != null) {
            // try extract AoA again (robust extraction from all fields)
            double? aoa;
            // attempt from manufacturer
            try {
              if (d.manufacturerData != null && (d.manufacturerData as Uint8List).isNotEmpty) {
                aoa = _tryExtractAoAFromBytes(List<int>.from(d.manufacturerData as Uint8List));
              }
            } catch (_) {}
            // attempt from service data if not found
            if (aoa == null && d.serviceData != null) {
              for (final e in d.serviceData.entries) {
                aoa ??= _tryExtractAoAFromBytes(List<int>.from(e.value));
                if (aoa != null) break;
              }
            }

            // store observation (distance displayed in list will use filteredDistance if present)
            final existing = _found[d.id];
            _found[d.id] = existing != null ? existing.copyUpdated(rssi: obs.rssi, seenAt: obs.seenAt) : obs;

            // process smoothing/filtering etc
            _processObservation(obs, aoa: aoa);
          } else {
            // not a known beacon - optionally you can still show it as "Unknown"
            final unk = Observation(id: d.id, type: 'BLE', info: '(raw)', rssi: d.rssi, seenAt: DateTime.now());
            final existing = _found[d.id];
            _found[d.id] = existing != null ? existing.copyUpdated(rssi: unk.rssi, seenAt: unk.seenAt) : unk;
          }
        },
        onError: (e) => debugPrint('❌ Scan error: $e'),
      );
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _uiTicker?.cancel();
    if (mounted) setState(() => _isScanning = false);
    debugPrint('🛑 Scan stopped.');
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
                debugPrint('🔁 Scan mode changed to: $_scanMode');
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
                debugPrint('🎛️ Filter changed → ${useKalman ? "Kalman" : "EWMA"}');
              },
            ),
          ),
          const SizedBox(width: 10),
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
                final dist = state?.filteredDistance ?? estimateDistanceFromRssi(o.rssi, txPower: txPower);
                final typeIcon = o.type == 'iBeacon' ? Icons.bluetooth_searching : (o.type == 'Eddystone' ? Icons.wifi : Icons.bluetooth);
                return ListTile(
                  leading: Icon(typeIcon, color: o.type == 'iBeacon' ? Colors.blueAccent : Colors.orangeAccent),
                  title: Text('${o.type} ${o.info}', style: const TextStyle(color: Colors.white)),
                  subtitle: Text('Device: ${o.id}\nAoA: ${state?.bearing?.toStringAsFixed(1) ?? "—"}°', style: const TextStyle(color: Colors.white54)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${o.rssi} dBm', style: const TextStyle(color: Colors.greenAccent)),
                      Text('~${dist.toStringAsFixed(2)} m', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                    ],
                  ),
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