import 'dart:io';

import 'package:bridgedesk/features/pairing/pairing_store.dart';
import 'package:flutter_test/flutter_test.dart';

PairedDevice _device(String id) => PairedDevice(
      deviceId: id,
      name: 'Device $id',
      os: 'macOS',
      ipAddress: '192.168.1.$id',
      port: 48150,
      fingerprint: 'aa' * 32,
      pairedAt: DateTime.utc(2026, 11, 5),
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bridgedesk_store_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('starts empty when no file exists', () async {
    final PairingStore store = await PairingStore.load(baseDir: tempDir);
    expect(store.paired, isEmpty);
    expect(store.findById('x'), isNull);
  });

  test('add + reload round-trip persists the pairing', () async {
    final PairingStore store = await PairingStore.load(baseDir: tempDir);
    await store.add(_device('1'));
    final PairingStore reloaded =
        await PairingStore.load(baseDir: tempDir);
    expect(reloaded.paired.length, 1);
    expect(reloaded.findById('1')?.name, 'Device 1');
    expect(reloaded.findById('1')?.fingerprint, 'aa' * 32);
  });

  test('adding the same device id replaces it (upsert)', () async {
    final PairingStore store = await PairingStore.load(baseDir: tempDir);
    await store.add(_device('1'));
    final PairedDevice moved = _device('1').copyWith(ipAddress: '10.0.0.9');
    await store.add(moved);
    expect(store.paired.length, 1);
    expect(store.findById('1')?.ipAddress, '10.0.0.9');
  });

  test('remove forgets one device, removeAll forgets all', () async {
    final PairingStore store = await PairingStore.load(baseDir: tempDir);
    await store.add(_device('1'));
    await store.add(_device('2'));
    await store.remove('1');
    expect(store.paired.length, 1);
    expect(store.findById('1'), isNull);
    final PairingStore reloaded =
        await PairingStore.load(baseDir: tempDir);
    expect(reloaded.paired.length, 1);
    await reloaded.removeAll();
    expect(reloaded.paired, isEmpty);
    final PairingStore empty = await PairingStore.load(baseDir: tempDir);
    expect(empty.paired, isEmpty);
  });

  test('corrupt file starts empty instead of crashing', () async {
    final File file = File('${tempDir.path}/pairings.json');
    await file.writeAsString('this is not json {{{');
    final PairingStore store = await PairingStore.load(baseDir: tempDir);
    expect(store.paired, isEmpty);
  });
}
