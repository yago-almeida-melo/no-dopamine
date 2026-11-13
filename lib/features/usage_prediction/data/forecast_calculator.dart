import 'package:flutter/foundation.dart';

import '../../usage_monitoring/domain/usage_models.dart';
import '../domain/prediction_history.dart';
import '../domain/prediction_models.dart';
import '../domain/usage_forecaster.dart';

abstract class ForecastCalculator {
  Future<ForecastAnalysis> calculate(
      UsageSnapshot snapshot, List<TrackedApp> apps);
}

class LocalForecastCalculator implements ForecastCalculator {
  @override
  Future<ForecastAnalysis> calculate(
          UsageSnapshot snapshot, List<TrackedApp> apps) =>
      compute(_calculate, _ForecastInput(snapshot, apps));
}

class _ForecastInput {
  const _ForecastInput(this.snapshot, this.apps);
  final UsageSnapshot snapshot;
  final List<TrackedApp> apps;
}

ForecastAnalysis _calculate(_ForecastInput input) => UsageForecaster().analyze(
    buildPredictionHistory(input.snapshot, input.apps),
    input.apps,
    input.snapshot.syncedAt);
