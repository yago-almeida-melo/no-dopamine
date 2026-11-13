import '../../usage_monitoring/domain/usage_models.dart';

enum ForecastModel { weeklyPattern, ridgeTrend, ridgeConservative }

extension ForecastModelLabel on ForecastModel {
  String get label => switch (this) {
        ForecastModel.weeklyPattern => 'Padrão da última semana',
        ForecastModel.ridgeTrend => 'Tendência e padrão semanal',
        ForecastModel.ridgeConservative => 'Tendência com maior regularização',
      };
}

/// Only dates with complete coverage may be used as training observations.
class UsageDay {
  const UsageDay(
      {required this.date,
      required this.minutes,
      required this.completePackages});
  final DateTime date;
  final Map<String, double> minutes;
  final Set<String> completePackages;
  double get total => minutes.values.fold(0, (a, b) => a + b);
}

class ForecastDay {
  const ForecastDay(this.date, this.minutes);
  final DateTime date;
  final double minutes;
}

class ObservedWeek {
  const ObservedWeek(this.start, this.end, this.minutes);
  final DateTime start;
  final DateTime end;
  final double minutes;
}

class AppForecast {
  const AppForecast(
      {required this.app,
      required this.model,
      required this.days,
      required this.recentMinutes,
      required this.testPredictions,
      required this.testActuals});
  final TrackedApp app;
  final ForecastModel model;
  final List<ForecastDay> days;
  final double recentMinutes;
  final List<double> testPredictions;
  final List<double> testActuals;
  double get total => days.fold(0, (a, b) => a + b.minutes);
  double get change => total - recentMinutes;
  double? get changePercent =>
      recentMinutes <= 0 ? null : change / recentMinutes * 100;
}

class ForecastAnalysis {
  const ForecastAnalysis(
      {required this.calculatedAt,
      required this.completeDays,
      required this.apps,
      required this.history,
      required this.forecasts,
      required this.selectionFolds});
  static const minimumDays = 14;
  static const historyDays = 84;
  final DateTime calculatedAt;
  final int completeDays;
  final List<TrackedApp> apps;
  final List<ObservedWeek> history;
  final List<AppForecast> forecasts;
  final int selectionFolds;

  bool get ready => forecasts.isNotEmpty;
  int get missingDays => (minimumDays - completeDays).clamp(0, minimumDays);
  double get predictedMinutes => forecasts.fold(0, (a, b) => a + b.total);
  double get recentMinutes => forecasts.fold(0, (a, b) => a + b.recentMinutes);
  double get change => predictedMinutes - recentMinutes;
  double? get changePercent =>
      recentMinutes <= 0 ? null : change / recentMinutes * 100;
  DateTime get start => localDay(calculatedAt);
  DateTime get end => DateTime(start.year, start.month, start.day + 7);
  bool get initial => completeDays < 28 || selectionFolds == 0;

  List<ForecastDay> get daily => [
        for (var i = 0; i < (ready ? 7 : 0); i++)
          ForecastDay(forecasts.first.days[i].date,
              forecasts.fold(0, (a, b) => a + b.days[i].minutes)),
      ];

  /// Error on a held-out week never used to select the model.
  double get testDailyMae {
    if (!ready) return 0;
    var error = 0.0;
    for (var i = 0; i < 7; i++) {
      final expected =
          forecasts.fold<double>(0, (a, b) => a + b.testPredictions[i]);
      final actual = forecasts.fold<double>(0, (a, b) => a + b.testActuals[i]);
      error += (expected - actual).abs();
    }
    return error / 7;
  }

  double get testWeeklyError => (forecasts.fold<double>(
              0,
              (a, b) =>
                  a + b.testPredictions.fold<double>(0, (c, d) => c + d)) -
          forecasts.fold<double>(
              0, (a, b) => a + b.testActuals.fold<double>(0, (c, d) => c + d)))
      .abs();

  bool get unstable {
    final mean = recentMinutes / 7;
    return ready && testDailyMae > (mean > 0 ? mean * .35 : 1);
  }
}
