import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_dopamine/features/usage_monitoring/domain/usage_models.dart';
import 'package:no_dopamine/features/usage_prediction/data/forecast_calculator.dart';

void main() {
  test('real isolate builds the dataset and returns the trained forecast',
      () async {
    final now = DateTime(2026, 10, 19, 15);
    final first = DateTime(2026, 9, 21);
    final app = TrackedApp(
        id: 'social', name: 'Social', icon: Uint8List.fromList([1, 2, 3]));
    final events = <UsageEvent>[];
    for (var i = 0; i < 28; i++) {
      events.add(UsageEvent(
          timestamp: DateTime(first.year, first.month, first.day + i, 9),
          type: 1,
          package: app.id));
      events.add(UsageEvent(
          timestamp: DateTime(first.year, first.month, first.day + i, 9, 30),
          type: 2,
          package: app.id));
    }
    final result = await LocalForecastCalculator().calculate(
        UsageSnapshot(
            events: events,
            coverage: [UsageCoverage(app.id, first, now)],
            syncedAt: now),
        [app]);
    expect(result.ready, isTrue);
    expect(result.completeDays, 28);
    expect(result.predictedMinutes, closeTo(210, 1e-5));
    expect(result.testDailyMae, closeTo(0, 1e-5));
    expect(result.forecasts.single.app.icon, [1, 2, 3]);
  });
}
