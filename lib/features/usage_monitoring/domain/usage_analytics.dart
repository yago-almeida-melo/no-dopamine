import 'usage_models.dart';

/// Counts resumed activities once per package, including multi-window use.
/// Missing closing events at reboot are discarded instead of inventing usage.
List<UsageSession> reconstructSessions(
  List<UsageEvent> events,
  Set<String> packages,
  DateTime until,
) {
  final sorted = events.where((e) => !e.timestamp.isAfter(until)).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final active = <String, Set<String>>{};
  final starts = <String, DateTime>{};
  final sessions = <UsageSession>[];
  var shuttingDown = false;

  void close(String package, DateTime end, {bool ongoing = false}) {
    final start = starts.remove(package);
    active.remove(package);
    if (start != null && end.isAfter(start)) {
      sessions.add(UsageSession(
        package: package,
        start: start,
        end: end,
        isOngoing: ongoing,
      ));
    }
  }

  for (final event in sorted) {
    if (event.type == 27) {
      // A startup without a preceding shutdown has no known closing time.
      active.clear();
      starts.clear();
      shuttingDown = false;
    } else if (event.type == 26 || event.type == 16 || event.type == 17) {
      for (final package in starts.keys.toList()) {
        close(package, event.timestamp);
      }
      if (event.type == 26) shuttingDown = true;
    } else if (!shuttingDown && packages.contains(event.package)) {
      if (event.type == 1) {
        final activities = active.putIfAbsent(event.package, () => {});
        starts.putIfAbsent(event.package, () => event.timestamp);
        activities.add(event.activity);
      } else if (event.type == 2 || event.type == 23) {
        final activities = active[event.package];
        activities?.remove(event.activity);
        if (activities != null && activities.isEmpty) {
          close(event.package, event.timestamp);
        }
      }
    }
  }
  for (final package in starts.keys.toList()) {
    close(package, until, ongoing: true);
  }
  return _mergeAdjacentSessions(sessions);
}

List<UsageSession> _mergeAdjacentSessions(List<UsageSession> sessions) {
  sessions.sort((a, b) {
    final byPackage = a.package.compareTo(b.package);
    return byPackage != 0 ? byPackage : a.start.compareTo(b.start);
  });
  final merged = <UsageSession>[];
  for (final session in sessions) {
    if (merged.isNotEmpty) {
      final last = merged.last;
      if (last.package == session.package && !session.start.isAfter(last.end)) {
        merged[merged.length - 1] = UsageSession(
          package: last.package,
          start: last.start,
          end: session.end.isAfter(last.end) ? session.end : last.end,
          isOngoing: last.isOngoing || session.isOngoing,
        );
        continue;
      }
    }
    merged.add(session);
  }
  merged.sort((a, b) => b.start.compareTo(a.start));
  return merged;
}

/// Shared session source for the historical dashboard and the forecast dataset.
List<UsageSession> coveredUsageSessions(
    UsageSnapshot snapshot, List<TrackedApp> apps) {
  final all = <UsageSession>[];
  for (final app in apps) {
    for (final range in snapshot.coverage.where((c) => c.package == app.id)) {
      final until =
          range.end.isBefore(snapshot.syncedAt) ? range.end : snapshot.syncedAt;
      final events = snapshot.events
          .where(
            (e) =>
                (e.package.isEmpty || e.package == app.id) &&
                !e.timestamp.isBefore(range.start) &&
                !e.timestamp.isAfter(until),
          )
          .toList();
      for (final session in reconstructSessions(events, {app.id}, until)) {
        all.add(UsageSession(
            package: session.package,
            start: session.start,
            end: session.end,
            isOngoing: session.isOngoing && until == snapshot.syncedAt));
      }
    }
  }
  all.sort((a, b) => b.start.compareTo(a.start));
  return all;
}

bool hasUsageCoverage(List<UsageCoverage> coverage, Iterable<String> packages,
    DateTime from, DateTime until) {
  if (!until.isAfter(from)) return true;
  return packages.every((package) {
    final ranges = coverage.where((c) => c.package == package).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    var cursor = from;
    for (final range in ranges) {
      if (range.start.isAfter(cursor)) return false;
      if (range.end.isAfter(cursor)) cursor = range.end;
      if (!cursor.isBefore(until)) return true;
    }
    return false;
  });
}

class UsageReport {
  UsageReport({
    required UsageSnapshot snapshot,
    required this.apps,
    required this.start,
    required this.end,
    required this.period,
  }) : syncedAt = snapshot.syncedAt {
    final until = end.isBefore(syncedAt) ? end : syncedAt;
    final all = coveredUsageSessions(snapshot, apps);
    sessions = [];
    totals = {for (final app in apps) app.id: Duration.zero};
    for (final session in all) {
      final clippedStart =
          session.start.isBefore(start) ? start : session.start;
      final clippedEnd = session.end.isAfter(until) ? until : session.end;
      if (!clippedEnd.isAfter(clippedStart)) continue;
      final clipped = UsageSession(
        package: session.package,
        start: clippedStart,
        end: clippedEnd,
        isOngoing: session.isOngoing && !session.end.isAfter(until),
      );
      sessions.add(clipped);
      totals[clipped.package] = totals[clipped.package]! + clipped.duration;
    }
    buckets = [];
    for (var i = 0; i < (period == UsagePeriod.day ? 24 : 7); i++) {
      final bucketStart = period == UsagePeriod.day
          ? DateTime(start.year, start.month, start.day, i)
          : DateTime(start.year, start.month, start.day + i);
      final bucketEnd = period == UsagePeriod.day
          ? DateTime(start.year, start.month, start.day, i + 1)
          : DateTime(start.year, start.month, start.day + i + 1);
      var duration = Duration.zero;
      for (final session in sessions) {
        final a =
            session.start.isAfter(bucketStart) ? session.start : bucketStart;
        final b = session.end.isBefore(bucketEnd) ? session.end : bucketEnd;
        if (b.isAfter(a)) duration += b.difference(a);
      }
      buckets.add(UsageBucket(
        start: bucketStart,
        end: bucketEnd,
        duration: duration,
        isComplete: _covered(snapshot.coverage, bucketStart, bucketEnd),
      ));
    }
    isComplete = _covered(snapshot.coverage, start, end);
  }

  final List<TrackedApp> apps;
  final DateTime start;
  final DateTime end;
  final DateTime syncedAt;
  final UsagePeriod period;
  late final List<UsageSession> sessions;
  late final Map<String, Duration> totals;
  late final List<UsageBucket> buckets;
  late final bool isComplete;

  Duration get total => totals.values.fold(Duration.zero, (a, b) => a + b);

  bool _covered(List<UsageCoverage> coverage, DateTime from, DateTime to) {
    final until = to.isAfter(syncedAt) ? syncedAt : to;
    return hasUsageCoverage(coverage, apps.map((app) => app.id), from, until);
  }
}
