import 'package:flutter_test/flutter_test.dart';
import 'package:no_dopamine/features/usage_monitoring/domain/usage_models.dart';
import 'package:no_dopamine/features/usage_prediction/domain/prediction_models.dart';
import 'package:no_dopamine/features/usage_prediction/domain/usage_forecaster.dart';

void main() {
  final now = DateTime(2026, 10, 19, 15);
  final today = localDay(now);
  const app = TrackedApp(id: 'social', name: 'Social');
  const other = TrackedApp(id: 'other', name: 'Other');
  final forecaster = UsageForecaster();

  List<UsageDay> sample(int count, double Function(int, DateTime) value) => [
        for (var i = 0; i < count; i++)
          UsageDay(
              date: DateTime(today.year, today.month, today.day - count + i),
              minutes: {
                'social': value(
                    i, DateTime(today.year, today.month, today.day - count + i))
              },
              completePackages: const {
                'social'
              }),
      ];

  test(
      'requires two complete consecutive weeks and never fabricates a forecast',
      () {
    final result = forecaster.analyze(sample(13, (i, d) => 60), [app], now);
    expect(result.ready, isFalse);
    expect(result.completeDays, 13);
    expect(result.missingDays, 1);
    expect(result.forecasts, isEmpty);
    expect(result.daily, isEmpty);
  });

  test('a data gap resets the recent training streak instead of becoming zero',
      () {
    final days = sample(42, (i, d) => 60);
    days[30] = UsageDay(
        date: days[30].date,
        minutes: const {'social': 0},
        completePackages: const {});
    final result = forecaster.analyze(days, [app], now);
    expect(result.completeDays, 11);
    expect(result.ready, isFalse);
    final missingRecent =
        forecaster.analyze(days.take(41).toList(), [app], now);
    expect(missingRecent.completeDays, 0);
  });

  test('every selected app must have a complete common training window', () {
    final result =
        forecaster.analyze(sample(28, (i, d) => 60), [app, other], now);
    expect(result.ready, isFalse);
    expect(result.completeDays, 0);
  });

  test('a constant series stays constant and has no spurious growth', () {
    final result = forecaster.analyze(sample(42, (i, d) => 60), [app], now);
    expect(result.predictedMinutes, closeTo(420, 1e-5));
    expect(result.change, closeTo(0, 1e-5));
    expect(result.testDailyMae, closeTo(0, 1e-5));
    expect(result.forecasts.single.model, ForecastModel.weeklyPattern);
    expect(result.history.length, 4);
  });

  test('learns a sustained increasing trend', () {
    final result =
        forecaster.analyze(sample(56, (i, d) => 30 + i * 2.0), [app], now);
    expect(result.predictedMinutes, greaterThan(result.recentMinutes));
    expect(result.changePercent, greaterThan(3));
    expect(result.forecasts.single.model, isNot(ForecastModel.weeklyPattern));
    final expected =
        [for (var i = 56; i < 63; i++) 30 + 2 * i].reduce((a, b) => a + b);
    expect(result.predictedMinutes, closeTo(expected, expected * .05));
  });

  test('a decreasing trend produces a reduction, never negative usage', () {
    final result =
        forecaster.analyze(sample(28, (i, d) => 100 - i * 3.0), [app], now);
    expect(result.change, lessThan(0));
    expect(result.daily.every((day) => day.minutes >= 0), isTrue);
  });

  test('learns weekday seasonality and preserves the forecast horizon', () {
    final result = forecaster.analyze(
        sample(42, (i, d) => d.weekday >= 6 ? 180 : 30), [app], now);
    expect(result.daily.length, 7);
    expect(result.daily.first.date, today);
    expect(result.daily.last.date, DateTime(2026, 10, 25));
    expect(result.daily[5].minutes, greaterThan(result.daily[0].minutes));
    expect(result.predictedMinutes, closeTo(510, 1e-5));
  });

  test('today is a lower bound, excluded from training and model selection',
      () {
    final days = sample(42, (i, d) => 60);
    final original = forecaster.analyze(days, [app], now);
    days.add(UsageDay(
        date: today,
        minutes: const {'social': 300},
        completePackages: const {'social'}));
    final updated = forecaster.analyze(days, [app], now);
    expect(updated.completeDays, original.completeDays);
    expect(updated.forecasts.single.model, original.forecasts.single.model);
    expect(updated.daily.first.minutes, 300);
    expect(updated.daily.skip(1).map((d) => d.minutes),
        original.daily.skip(1).map((d) => d.minutes));
    expect(updated.recentMinutes, original.recentMinutes);
  });

  test(
      'future observations do not leak into training or historical test errors',
      () {
    final days = sample(42, (i, d) => 60 + i.toDouble());
    final original = forecaster.analyze(days, [app], now);
    days.add(UsageDay(
        date: DateTime(2026, 10, 25),
        minutes: const {'social': 1440},
        completePackages: const {'social'}));
    final result = forecaster.analyze(days, [app], now);
    expect(result.predictedMinutes, original.predictedMinutes);
    expect(result.testDailyMae, original.testDailyMae);
  });

  test('the held-out week cannot influence which model is selected', () {
    final days = sample(56, (i, d) => 20 + i * 2.0);
    final original = forecaster.analyze(days, [app], now);
    for (var i = 49; i < 56; i++) {
      days[i] = UsageDay(
          date: days[i].date,
          minutes: const {'social': 1},
          completePackages: const {'social'});
    }
    final changed = forecaster.analyze(days, [app], now);
    expect(changed.forecasts.single.model, original.forecasts.single.model);
    expect(changed.testDailyMae, isNot(closeTo(original.testDailyMae, 1e-5)));
  });

  test('zero baseline produces no infinity or artificial percentage', () {
    final days = sample(28, (i, d) => 0);
    days.add(UsageDay(
        date: today, minutes: const {'social': 5}, completePackages: const {}));
    final result = forecaster.analyze(days, [app], now);
    expect(result.ready, isTrue);
    expect(result.recentMinutes, 0);
    expect(result.changePercent, isNull);
    expect(result.predictedMinutes, 5);
    expect(result.daily.every((d) => d.minutes.isFinite), isTrue);
  });

  test('short history is marked initial and training never exceeds 84 days',
      () {
    final initial = forecaster.analyze(sample(14, (i, d) => 60), [app], now);
    expect(initial.ready, isTrue);
    expect(initial.initial, isTrue);
    expect(initial.selectionFolds, 0);
    expect(initial.forecasts.single.testActuals.length, 7);
    final long = forecaster.analyze(sample(120, (i, d) => 60), [app], now);
    expect(long.completeDays, 84);
    expect(long.selectionFolds, 5);
    expect(long.initial, isFalse);
  });

  test('per-app forecasts are physically bounded and totals reconcile', () {
    final days = sample(56, (i, d) => 340 + i * 20.0)
        .map((day) => UsageDay(
              date: day.date,
              minutes: {'social': day.minutes['social']!, 'other': 30},
              completePackages: const {'social', 'other'},
            ))
        .toList();
    // The last observed value is 1440, and extrapolation would exceed 24h.
    final result = forecaster.analyze(days, [app, other], now);
    expect(result.ready, isTrue);
    for (final app in result.forecasts) {
      expect(
          app.days.every((d) => d.minutes >= 0 && d.minutes <= 1440), isTrue);
    }
    expect(result.daily.fold<double>(0, (a, b) => a + b.minutes),
        closeTo(result.predictedMinutes, 1e-6));
    expect(result.forecasts.fold<double>(0, (a, b) => a + b.total),
        result.predictedMinutes);
  });
}
