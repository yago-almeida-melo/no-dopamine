import 'package:flutter_test/flutter_test.dart';
import 'package:no_dopamine/features/usage_monitoring/domain/usage_analytics.dart';
import 'package:no_dopamine/features/usage_monitoring/domain/usage_models.dart';
import 'package:no_dopamine/features/usage_prediction/domain/prediction_history.dart';

void main() {
  const apps = [TrackedApp(id: 'social', name: 'Social')];
  final now = DateTime(2026, 10, 19, 15);
  final start = DateTime(2026, 10, 18);

  test('forecast dataset matches dashboard totals and splits midnight', () {
    final snapshot = UsageSnapshot(syncedAt: now, events: [
      UsageEvent(
          timestamp: DateTime(2026, 10, 18, 23, 50),
          type: 1,
          package: 'social'),
      UsageEvent(
          timestamp: DateTime(2026, 10, 19, 0, 10), type: 2, package: 'social'),
    ], coverage: [
      UsageCoverage('social', start, now)
    ]);
    final days = buildPredictionHistory(snapshot, apps);
    final yesterday = days.firstWhere((d) => d.date == start);
    final today = days.last;
    expect(yesterday.minutes['social'], 10);
    expect(today.minutes['social'], 10);
    expect(yesterday.completePackages, {'social'});
    expect(today.completePackages, isEmpty);
    final report = UsageReport(
        snapshot: snapshot,
        apps: apps,
        start: start,
        end: DateTime(2026, 10, 19),
        period: UsagePeriod.day);
    expect(yesterday.minutes['social'], report.total.inMilliseconds / 60000);
  });

  test('covered zero-use days are evidence, unavailable days are not', () {
    final days = buildPredictionHistory(
        UsageSnapshot(
            syncedAt: now,
            events: [],
            coverage: [UsageCoverage('social', start, now)]),
        apps);
    expect(
        days.firstWhere((d) => d.date == start).completePackages, {'social'});
    expect(days.first.completePackages, isEmpty);
    expect(days.first.minutes['social'], 0);
    expect(days.last.completePackages, isEmpty);
    expect(days.length, 85);
  });
}
