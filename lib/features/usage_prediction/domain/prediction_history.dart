import '../../usage_monitoring/domain/usage_analytics.dart';
import '../../usage_monitoring/domain/usage_models.dart';
import 'prediction_models.dart';

List<UsageDay> buildPredictionHistory(
    UsageSnapshot snapshot, List<TrackedApp> apps) {
  final today = localDay(snapshot.syncedAt);
  final first = DateTime(
      today.year, today.month, today.day - ForecastAnalysis.historyDays);
  final values = <DateTime, Map<String, double>>{};
  for (var i = 0; i <= ForecastAnalysis.historyDays; i++) {
    values[DateTime(first.year, first.month, first.day + i)] = {
      for (final app in apps) app.id: 0,
    };
  }
  for (final session in coveredUsageSessions(snapshot, apps)) {
    var cursor = session.start.isBefore(first) ? first : session.start;
    final end = session.end.isAfter(snapshot.syncedAt)
        ? snapshot.syncedAt
        : session.end;
    while (cursor.isBefore(end)) {
      final day = localDay(cursor);
      final next = DateTime(day.year, day.month, day.day + 1);
      final stop = end.isBefore(next) ? end : next;
      final row = values[day];
      if (row != null) {
        row[session.package] = row[session.package]! +
            stop.difference(cursor).inMilliseconds /
                Duration.millisecondsPerMinute;
      }
      cursor = stop;
    }
  }
  return [
    for (final row in values.entries)
      UsageDay(
        date: row.key,
        minutes: row.value,
        completePackages: {
          if (row.key.isBefore(today))
            for (final app in apps)
              if (hasUsageCoverage(snapshot.coverage, [app.id], row.key,
                  DateTime(row.key.year, row.key.month, row.key.day + 1)))
                app.id,
        },
      )
  ];
}
