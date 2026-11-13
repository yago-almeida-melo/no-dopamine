import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/usage_models.dart';

abstract class UsageRepository {
  Future<UsageState> loadState();
  Future<void> openPermissionSettings();
  Future<void> saveSelection(Set<String> packages);
  Future<UsageSnapshot> loadUsage(DateTime start, DateTime end);
  Future<UsageSnapshot> loadHistory(DateTime start, DateTime end);
}

class AndroidUsageRepository implements UsageRepository {
  static const _channel = MethodChannel('no_dopamine/usage');

  @override
  Future<UsageState> loadState() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const UsageState(
        supported: false,
        hasPermission: false,
        apps: [],
        selectedIds: {},
      );
    }
    final data = await _channel.invokeMapMethod<String, dynamic>('getState');
    if (data == null) throw StateError('O Android não respondeu.');
    return UsageState(
      supported: true,
      hasPermission: data['hasPermission'] as bool,
      apps: (data['apps'] as List).map((raw) {
        final app = raw as Map;
        return TrackedApp(
          id: app['id'] as String,
          name: app['name'] as String,
          icon: app['icon'] as Uint8List?,
        );
      }).toList(),
      selectedIds: (data['selectedIds'] as List).cast<String>().toSet(),
    );
  }

  @override
  Future<void> openPermissionSettings() =>
      _channel.invokeMethod<void>('openPermissionSettings');

  @override
  Future<void> saveSelection(Set<String> packages) => _channel
      .invokeMethod<void>('saveSelection', {'packages': packages.toList()});

  @override
  Future<UsageSnapshot> loadUsage(DateTime start, DateTime end) =>
      _loadSnapshot('getUsage', start, end);

  @override
  Future<UsageSnapshot> loadHistory(DateTime start, DateTime end) =>
      _loadSnapshot('getHistory', start, end);

  Future<UsageSnapshot> _loadSnapshot(
      String method, DateTime start, DateTime end) async {
    final data = await _channel.invokeMapMethod<String, dynamic>(method, {
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
    if (data == null) throw StateError('O Android não retornou o histórico.');
    DateTime time(dynamic value) =>
        DateTime.fromMillisecondsSinceEpoch((value as num).toInt());
    return UsageSnapshot(
      syncedAt: time(data['syncedAt']),
      events: (data['events'] as List).map((raw) {
        final event = raw as Map;
        return UsageEvent(
          timestamp: time(event['timestamp']),
          type: (event['type'] as num).toInt(),
          package: event['package'] as String,
          activity: event['activity'] as String,
        );
      }).toList(),
      coverage: (data['coverage'] as List).map((raw) {
        final range = raw as Map;
        return UsageCoverage(
          range['package'] as String,
          time(range['start']),
          time(range['end']),
        );
      }).toList(),
    );
  }
}
