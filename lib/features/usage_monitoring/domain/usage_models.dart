import 'dart:typed_data';

enum UsagePeriod { day, week }

class TrackedApp {
  const TrackedApp({required this.id, required this.name, this.icon});

  final String id;
  final String name;
  final Uint8List? icon;

  bool get isSocial => _socialPackages.contains(id);

  static const _socialPackages = {
    'com.instagram.android',
    'com.instagram.barcelona',
    'com.facebook.katana',
    'com.facebook.lite',
    'com.facebook.orca',
    'com.zhiliaoapp.musically',
    'com.ss.android.ugc.trill',
    'com.zhiliaoapp.musically.go',
    'com.twitter.android',
    'com.google.android.youtube',
    'com.google.android.apps.youtube.music',
    'com.whatsapp',
    'com.whatsapp.w4b',
    'org.telegram.messenger',
    'org.telegram.messenger.web',
    'com.snapchat.android',
    'com.reddit.frontpage',
    'com.pinterest',
    'com.discord',
    'com.linkedin.android',
    'tv.twitch.android.app',
    'com.kwai.video',
    'com.kwai.video.lite',
    'com.bsky.app',
    'org.joinmastodon.android',
    'com.tumblr',
    'com.bereal.ft',
  };
}

class UsageState {
  const UsageState({
    required this.supported,
    required this.hasPermission,
    required this.apps,
    required this.selectedIds,
  });

  final bool supported;
  final bool hasPermission;
  final List<TrackedApp> apps;
  final Set<String> selectedIds;

  List<TrackedApp> get selectedApps =>
      apps.where((app) => selectedIds.contains(app.id)).toList();
}

class UsageEvent {
  const UsageEvent({
    required this.timestamp,
    required this.type,
    this.package = '',
    this.activity = '',
  });

  final DateTime timestamp;
  final int type;
  final String package;
  final String activity;
}

class UsageCoverage {
  const UsageCoverage(this.package, this.start, this.end);

  final String package;
  final DateTime start;
  final DateTime end;
}

class UsageSnapshot {
  const UsageSnapshot({
    required this.events,
    required this.coverage,
    required this.syncedAt,
  });

  final List<UsageEvent> events;
  final List<UsageCoverage> coverage;
  final DateTime syncedAt;
}

class UsageSession {
  const UsageSession({
    required this.package,
    required this.start,
    required this.end,
    this.isOngoing = false,
  });

  final String package;
  final DateTime start;
  final DateTime end;
  final bool isOngoing;

  Duration get duration => end.difference(start);
}

class UsageBucket {
  const UsageBucket({
    required this.start,
    required this.end,
    required this.duration,
    required this.isComplete,
  });

  final DateTime start;
  final DateTime end;
  final Duration duration;
  final bool isComplete;
}

DateTime localDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime periodStart(DateTime value, UsagePeriod period) {
  final day = localDay(value);
  return period == UsagePeriod.day
      ? day
      : DateTime(day.year, day.month, day.day - day.weekday + 1);
}

DateTime periodEnd(DateTime start, UsagePeriod period) => DateTime(
    start.year, start.month, start.day + (period == UsagePeriod.day ? 1 : 7));
