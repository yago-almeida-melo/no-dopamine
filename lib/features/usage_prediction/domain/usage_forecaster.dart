import 'dart:math' as math;

import '../../usage_monitoring/domain/usage_models.dart';
import 'prediction_models.dart';

/// Small-data supervised learning: weighted ridge regression with calendar
/// features, checked against a seasonal-naive benchmark. No remote model/API.
class UsageForecaster {
  ForecastAnalysis analyze(
      List<UsageDay> days, List<TrackedApp> apps, DateTime asOf) {
    final today = localDay(asOf);
    final byDate = {for (final day in days) localDay(day.date): day};
    final recent = <UsageDay>[];
    if (apps.isNotEmpty) {
      for (var offset = 1; offset <= ForecastAnalysis.historyDays; offset++) {
        final date = DateTime(today.year, today.month, today.day - offset);
        final day = byDate[date];
        if (day == null || !apps.every((app) => _usable(day, app.id))) break;
        recent.add(day);
      }
    }
    final training = recent.reversed.toList();
    final history = <ObservedWeek>[];
    for (var weeksBack = 4; weeksBack >= 1; weeksBack--) {
      if (training.length < weeksBack * 7) continue;
      final block = training.sublist(training.length - weeksBack * 7,
          training.length - (weeksBack - 1) * 7);
      history.add(ObservedWeek(
          block.first.date,
          DateTime(block.last.date.year, block.last.date.month,
              block.last.date.day + 1),
          block.fold<double>(
              0,
              (sum, day) =>
                  sum +
                  apps.fold<double>(
                      0, (total, app) => total + day.minutes[app.id]!))));
    }
    if (training.length < ForecastAnalysis.minimumDays) {
      return ForecastAnalysis(
          calculatedAt: asOf,
          completeDays: training.length,
          apps: apps,
          history: history,
          forecasts: [],
          selectionFolds: 0);
    }

    // Non-overlapping weekly rolling-origin folds. The newest week is held
    // out of model selection, not recycled as an optimistic accuracy score.
    final origins = <int>[];
    for (var n = training.length - 7; n >= 7 && origins.length < 6; n -= 7) {
      origins.add(n);
    }
    origins.sort();
    final selectionOrigins = origins.take(origins.length - 1).toList();
    final testOrigin = origins.last;
    final forecastDates = [
      for (var i = 0; i < 7; i++)
        DateTime(today.year, today.month, today.day + i)
    ];
    final forecasts = <AppForecast>[];
    for (final app in apps) {
      var chosen = ForecastModel.ridgeConservative;
      if (selectionOrigins.isNotEmpty) {
        var bestScore = double.infinity;
        for (final candidate in ForecastModel.values) {
          var score = 0.0;
          for (final origin in selectionOrigins) {
            final target = training.sublist(origin, origin + 7);
            final estimates = _predict(candidate, training.sublist(0, origin),
                app.id, target.map((d) => d.date).toList());
            final actual = target.map((d) => d.minutes[app.id]!).toList();
            final totalError = (_sum(estimates) - _sum(actual)).abs();
            var dailyError = 0.0;
            for (var i = 0; i < 7; i++) {
              dailyError += (estimates[i] - actual[i]).abs();
            }
            score += totalError + dailyError * .25;
          }
          // Prefer the simple benchmark for numerical ties.
          if (score < bestScore - 1e-6) {
            bestScore = score;
            chosen = candidate;
          }
        }
      }
      final testRows = training.sublist(testOrigin);
      final testPredictions = _predict(chosen, training.sublist(0, testOrigin),
          app.id, testRows.map((d) => d.date).toList());
      final estimates = _predict(chosen, training, app.id, forecastDates);
      // Today is never a training observation. Its measured usage is a lower
      // bound on today's full-day forecast, not a completed day of evidence.
      final observed = byDate[today]?.minutes[app.id];
      if (observed != null && observed.isFinite && observed >= 0) {
        estimates[0] = math
            .max(estimates[0], observed)
            .clamp(0, _capacity(today))
            .toDouble();
      }
      forecasts.add(AppForecast(
          app: app,
          model: chosen,
          days: [
            for (var i = 0; i < 7; i++)
              ForecastDay(forecastDates[i], estimates[i])
          ],
          recentMinutes: training
              .skip(training.length - 7)
              .fold(0, (total, d) => total + d.minutes[app.id]!),
          testPredictions: testPredictions,
          testActuals: testRows.map((d) => d.minutes[app.id]!).toList()));
    }
    return ForecastAnalysis(
        calculatedAt: asOf,
        completeDays: training.length,
        apps: apps,
        history: history,
        forecasts: forecasts,
        selectionFolds: selectionOrigins.length);
  }

  bool _usable(UsageDay day, String package) {
    final value = day.minutes[package];
    return day.completePackages.contains(package) &&
        value != null &&
        value.isFinite &&
        value >= 0 &&
        value <= _capacity(day.date) + 1e-6;
  }

  List<double> _predict(ForecastModel model, List<UsageDay> training,
      String package, List<DateTime> targets) {
    if (model == ForecastModel.weeklyPattern) {
      return [
        for (final target in targets)
          training
              .lastWhere((d) => d.date.weekday == target.weekday)
              .minutes[package]!
              .clamp(0, _capacity(target))
              .toDouble()
      ];
    }
    const dimensions = 8; // intercept, time in weeks, 6 weekday indicators
    final matrix =
        List.generate(dimensions, (_) => List.filled(dimensions, 0.0));
    final response = List.filled(dimensions, 0.0);
    final last = training.last.date;
    for (final day in training) {
      final features = _features(day.date, last);
      final weight =
          math.pow(.5, (_ordinal(last) - _ordinal(day.date)) / 28).toDouble();
      final y = day.minutes[package]!;
      for (var i = 0; i < dimensions; i++) {
        response[i] += weight * features[i] * y;
        for (var j = 0; j < dimensions; j++) {
          matrix[i][j] += weight * features[i] * features[j];
        }
      }
    }
    matrix[0][0] +=
        1e-9; // numerical guard, intercept is effectively unpenalized
    matrix[1][1] += model == ForecastModel.ridgeTrend ? .2 : 4;
    for (var i = 2; i < dimensions; i++) {
      matrix[i][i] += model == ForecastModel.ridgeTrend ? .5 : 2;
    }
    final coefficients = _solve(matrix, response);
    return [
      for (final target in targets)
        _boundedPrediction(
            coefficients, _features(target, last), _capacity(target))
    ];
  }

  double _boundedPrediction(
      List<double> coefficients, List<double> features, double maximum) {
    var value = 0.0;
    for (var i = 0; i < coefficients.length; i++) {
      value += coefficients[i] * features[i];
    }
    return value.clamp(0, maximum).toDouble();
  }

  List<double> _features(DateTime date, DateTime origin) => [
        1,
        (_ordinal(date) - _ordinal(origin)) / 7,
        for (var weekday = 1; weekday <= 6; weekday++)
          date.weekday == weekday ? 1 : 0,
      ];

  // Calendar indexing is independent of 23/25-hour daylight-saving days.
  int _ordinal(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  double _capacity(DateTime day) => DateTime(day.year, day.month, day.day + 1)
      .difference(DateTime(day.year, day.month, day.day))
      .inMinutes
      .toDouble();

  double _sum(List<double> values) => values.fold(0, (a, b) => a + b);

  /// Gaussian elimination with partial pivoting for the positive definite
  /// 8x8 ridge system. The intercept is not shrunk toward zero.
  List<double> _solve(List<List<double>> matrix, List<double> response) {
    final n = response.length;
    final rows = [
      for (var i = 0; i < n; i++) [...matrix[i], response[i]]
    ];
    for (var column = 0; column < n; column++) {
      var pivot = column;
      for (var row = column + 1; row < n; row++) {
        if (rows[row][column].abs() > rows[pivot][column].abs()) pivot = row;
      }
      final swap = rows[column];
      rows[column] = rows[pivot];
      rows[pivot] = swap;
      final divisor = rows[column][column];
      if (divisor.abs() < 1e-12)
        throw StateError('Sistema de previsão singular.');
      for (var j = column; j <= n; j++) {
        rows[column][j] /= divisor;
      }
      for (var row = 0; row < n; row++) {
        if (row == column) continue;
        final factor = rows[row][column];
        for (var j = column; j <= n; j++) {
          rows[row][j] -= factor * rows[column][j];
        }
      }
    }
    return [for (var i = 0; i < n; i++) rows[i][n]];
  }
}
