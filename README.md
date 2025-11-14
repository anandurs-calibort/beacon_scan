# beacon_scan

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


Step-by-step procedure

Check prerequisites

[//]: # ()
[//]: # (Verify Bluetooth & Location status and permissions.)

[//]: # ()
[//]: # (If anything missing: show appropriate message and stop &#40;set _isScanning = false&#41;.)

Start scanning

[//]: # ()
[//]: # (Set _isScanning = true.)

[//]: # ()
[//]: # (Clear previous data structures &#40;_found, _beaconStates, _list, mock positions if needed&#41;.)

[//]: # ()
[//]: # (Start any UI tick / periodic refresh timers.)

Receive advertisement (per packet)

[//]: # (Parse incoming packet into an Observation with id, rssi, type, seenAt, and optional raw bytes.)

Extract AoA (if present)

[//]: # ()
[//]: # (Try to parse AoA angle from manufacturer/service bytes.)

[//]: # ()
[//]: # (If AoA found, attach bearing to that beacon’s state.)

Estimate raw distance

[//]: # (rawDistance = estimateDistanceFromRssi&#40;rssi, txPower&#41;.)

Filter / smooth distance

[//]: # (If beacon is new → create BeaconState with rawDistance, filteredDistance = rawDistance and optional Kalman init.)

[//]: # ()
[//]: # (If existing → apply chosen filter:)

[//]: # ()
[//]: # (EWMA: filtered = ewma&#40;oldFiltered, rawDistance, alpha&#41;)

[//]: # ()
[//]: # (Kalman: filtered = kalman.update&#40;rawDistance&#41;)

[//]: # ()
[//]: # (Clamp large jumps: filtered = clampJump&#40;oldFiltered, filtered, maxJump&#41;.)

[//]: # ()
[//]: # (Update BeaconState.filteredDistance, rssi, lastSeen, and bearing &#40;if AoA&#41;.)

Store / update observation for UI

[//]: # ()
[//]: # (Keep _found[id] for list display &#40;with updated RSSI/time&#41;.)

[//]: # ()
[//]: # (Rebuild _list sorted by RSSI when UI timer fires.)

Drop stale/weak beacons

[//]: # (In position update, ignore beacons with lastSeen older than staleAfterSeconds or rssi < threshold &#40;e.g. -95 dBm&#41;.)

Select beacons for positioning

[//]: # (Sort valid beacons by filteredDistance and pick up to 3 nearest for trilateration.)

[//]: # ()
[//]: # (Also collect beacons that have valid AoA &#40;if any&#41;.)

Trilateration (distance-based)

[//]: # (Input: three &#40;pos, dist&#41; pairs → solve linear system to get trilateratedPos.)

[//]: # ()
[//]: # (If only 2 beacons → use estimateFromTwo &#40;midpoint projection&#41;.)

[//]: # ()
[//]: # (If 1 beacon → cannot trilaterate &#40;mark low accuracy&#41;.)

AoA refinement (angle-based)

[//]: # (If ≥2 beacons have AoA: convert beacon position + AoA into bearing lines, compute intersection / best-fit point → aoaRefinedPos.)

[//]: # ()
[//]: # (Combine: if both trilateration and AoA result exist, average or weight them &#40;e.g. final = &#40;tri + aoa&#41;/2&#41;, else use whichever exists.)

Set final user position & accuracy

[//]: # (Set _userPosition = final computed position.)

[//]: # ()
[//]: # (Update _accuracy string and _beaconsUsed.)

UI refresh

[//]: # (Update _list for beacon tiles and redraw UI &#40;position, accuracy, beacons used&#41;.)

[//]: # ()
[//]: # (Use the periodic UI timer or call setState after updates.)

Stop scanning

[//]: # (Cancel BLE subscription &#40;_scanSub?.cancel&#40;&#41;&#41;.)

[//]: # ()
[//]: # (Cancel timers &#40;_uiTicker?.cancel&#40;&#41; and any simulation timer&#41;.)

[//]: # ()
[//]: # (Set _isScanning = false and update UI.)
