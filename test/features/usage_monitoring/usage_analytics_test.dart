import 'package:flutter_test/flutter_test.dart';
import 'package:no_dopamine/features/usage_monitoring/domain/usage_analytics.dart';
import 'package:no_dopamine/features/usage_monitoring/domain/usage_models.dart';

void main() {
  final day = DateTime(2026, 10, 19);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 19, hour, minute);
  UsageEvent event(int type, DateTime time,
          [String package = 'instagram', String activity = 'main']) =>
      UsageEvent(
          timestamp: time, type: type, package: package, activity: activity);
  const apps = [
    TrackedApp(id: 'instagram', name: 'Instagram'),
    TrackedApp(id: 'youtube', name: 'YouTube')
  ];

  UsageReport report(List<UsageEvent> events,
          {DateTime? start,
          DateTime? end,
          UsagePeriod period = UsagePeriod.day,
          List<UsageCoverage>? coverage}) =>
      UsageReport(
        snapshot: UsageSnapshot(
            events: events,
            syncedAt: at(20),
            coverage: coverage ??
                [
                  for (final app in apps)
                    UsageCoverage(app.id, DateTime(2026, 10, 1), at(20)),
                ]),
        apps: apps,
        start: start ?? day,
        end: end ?? at(24),
        period: period,
      );

  test('separates app totals and ignores unselected apps', () {
    final value = report([
      event(1, at(9)),
      event(2, at(9, 30)),
      event(1, at(10), 'youtube'),
      event(2, at(11), 'youtube'),
      event(1, at(12), 'unselected'),
      event(2, at(13), 'unselected'),
    ]);
    expect(value.total, const Duration(minutes: 90));
    expect(value.totals['instagram'], const Duration(minutes: 30));
    expect(value.totals['youtube'], const Duration(hours: 1));
    expect(value.sessions.length, 2);
    expect(value.sessions.first.package, 'youtube');
  });

  test('clips a session at midnight and splits weekly daily buckets', () {
    final events = [
      event(1, DateTime(2026, 10, 18, 23, 50)),
      event(2, at(0, 10))
    ];
    expect(report(events).total, const Duration(minutes: 10));
    final week = report(events,
        start: DateTime(2026, 10, 12), end: day, period: UsagePeriod.week);
    expect(week.total, const Duration(minutes: 10));
    expect(week.buckets.last.duration, const Duration(minutes: 10));
    expect(week.buckets.length, 7);
  });

  test('hourly buckets exactly conserve total duration', () {
    final value = report([event(1, at(9, 45)), event(2, at(11, 15))]);
    expect(value.buckets[9].duration, const Duration(minutes: 15));
    expect(value.buckets[10].duration, const Duration(hours: 1));
    expect(value.buckets[11].duration, const Duration(minutes: 15));
    expect(value.buckets.fold(Duration.zero, (a, b) => a + b.duration),
        value.total);
  });

  test('does not double-count overlapping activities or duplicate resumes', () {
    final value = report([
      event(1, at(9)),
      event(1, at(9)),
      event(1, at(9, 10), 'instagram', 'video'),
      event(2, at(9, 20)),
      event(23, at(9, 21)),
      event(2, at(9, 30), 'instagram', 'video'),
    ]);
    expect(value.total, const Duration(minutes: 30));
    expect(value.sessions.length, 1);
  });

  test('screen off and lock close active sessions', () {
    final value = report([
      event(1, at(9)),
      event(16, at(9, 15), ''),
      event(1, at(10)),
      event(17, at(10, 5), ''),
      event(2, at(11)),
    ]);
    expect(value.total, const Duration(minutes: 20));
  });

  test('shutdown closes usage and startup discards unmatched activities', () {
    final value = report([
      event(1, at(8)),
      event(26, at(8, 10), ''),
      event(1, at(8, 11)),
      event(2, at(8, 20)),
      event(27, at(9), ''),
      event(1, at(10)),
      event(27, at(11), ''),
      event(1, at(12)),
      event(2, at(12, 5)),
    ]);
    expect(value.total, const Duration(minutes: 15));
  });

  test('ongoing session ends at snapshot time, never in the future', () {
    final value = report([event(1, at(19)), event(2, at(21))]);
    expect(value.total, const Duration(hours: 1));
    expect(value.sessions.single.isOngoing, isTrue);
  });

  test('gaps in archived coverage cannot inflate ongoing usage', () {
    final value = report([
      event(1, at(8)),
      event(2, at(14)),
      event(1, at(15)),
      event(2, at(15, 10)),
    ], coverage: [
      UsageCoverage('instagram', at(7), at(9)),
      UsageCoverage('instagram', at(13), at(20)),
      UsageCoverage('youtube', day, at(20)),
    ]);
    expect(value.total, const Duration(minutes: 70));
    expect(value.isComplete, isFalse);
    expect(value.buckets[10].isComplete, isFalse);
    expect(value.buckets[15].isComplete, isTrue);
    expect(value.sessions.every((s) => !s.isOngoing), isTrue);
  });

  test('missing history differs from a covered day without usage', () {
    final unavailable = report([], coverage: []);
    final unused = report([]);
    expect(unavailable.total, Duration.zero);
    expect(unavailable.isComplete, isFalse);
    expect(unused.total, Duration.zero);
    expect(unused.isComplete, isTrue);
  });

  test('week starts on Monday across month and year boundaries', () {
    expect(periodStart(DateTime(2027, 1, 3), UsagePeriod.week),
        DateTime(2026, 12, 28));
    expect(periodEnd(DateTime(2026, 12, 28), UsagePeriod.week),
        DateTime(2027, 1, 4));
  });
}
