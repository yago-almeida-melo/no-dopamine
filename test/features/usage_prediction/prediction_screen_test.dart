import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_dopamine/features/home/presentation/home_page.dart';
import 'package:no_dopamine/features/usage_monitoring/data/usage_repository.dart';
import 'package:no_dopamine/features/usage_monitoring/domain/usage_models.dart';
import 'package:no_dopamine/features/usage_prediction/data/forecast_calculator.dart';
import 'package:no_dopamine/features/usage_prediction/domain/prediction_models.dart';
import 'package:no_dopamine/features/usage_prediction/domain/usage_forecaster.dart';
import 'package:no_dopamine/features/usage_prediction/presentation/prediction_screen.dart';

class PredictionRepositoryFake implements UsageRepository {
  bool permission = true;
  bool failHistory = false;
  Set<String> selected = {'social'};
  int historyReads = 0;
  int usageReads = 0;

  @override
  Future<UsageState> loadState() async => UsageState(
      supported: true,
      hasPermission: permission,
      apps: const [TrackedApp(id: 'social', name: 'Social')],
      selectedIds: {...selected});
  @override
  Future<void> openPermissionSettings() async {}
  @override
  Future<void> saveSelection(Set<String> packages) async {
    selected = {...packages};
  }

  @override
  Future<UsageSnapshot> loadUsage(DateTime start, DateTime end) async {
    usageReads++;
    return UsageSnapshot(
        events: [],
        coverage: [UsageCoverage('social', start, end)],
        syncedAt: DateTime.now());
  }

  @override
  Future<UsageSnapshot> loadHistory(DateTime start, DateTime end) async {
    historyReads++;
    if (failHistory) throw StateError('test failure');
    return UsageSnapshot(events: [], coverage: [], syncedAt: DateTime.now());
  }
}

class CalculatorFake implements ForecastCalculator {
  CalculatorFake({this.days = 42});
  final int days;
  @override
  Future<ForecastAnalysis> calculate(
      UsageSnapshot snapshot, List<TrackedApp> apps) async {
    final today = localDay(snapshot.syncedAt);
    return UsageForecaster().analyze([
      for (var i = 0; i < days; i++)
        UsageDay(
            date: DateTime(today.year, today.month, today.day - days + i),
            minutes: {for (final app in apps) app.id: 60},
            completePackages: apps.map((a) => a.id).toSet()),
    ], apps, snapshot.syncedAt);
  }
}

void main() {
  testWidgets('forecast loads lazily and reloads when its tab becomes active',
      (tester) async {
    final repo = PredictionRepositoryFake();
    await tester.pumpWidget(MaterialApp(
        home: HomePage(repository: repo, calculator: CalculatorFake())));
    await tester.pumpAndSettle();
    expect(repo.historyReads, 0);
    await tester.tap(find.text('Previsão'));
    await tester.pumpAndSettle();
    expect(repo.historyReads, 1);
    expect(find.text('Seu ritmo, mais adiante'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('PREVISÃO · 7 DIAS'), 200);
    expect(find.text('PREVISÃO · 7 DIAS'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Uso'));
    await tester.pumpAndSettle();
    expect(repo.historyReads, 1);
    await tester.tap(find.text('Previsão'));
    await tester.pumpAndSettle();
    expect(repo.historyReads, 2);
  });

  testWidgets(
      'insufficient history displays progress without a fabricated number',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PredictionScreen(
            repository: PredictionRepositoryFake(),
            calculator: CalculatorFake(days: 5),
            onOpenUsage: () {})));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Construindo sua base de previsão'), 150);
    expect(find.text('5 de 14 dias completos'), findsOneWidget);
    expect(find.text('PREVISÃO · 7 DIAS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'permission and app selection are required before reading history',
      (tester) async {
    final repo = PredictionRepositoryFake()..permission = false;
    var openUsage = 0;
    await tester.pumpWidget(MaterialApp(
        home: PredictionScreen(
            repository: repo,
            calculator: CalculatorFake(),
            onOpenUsage: () => openUsage++)));
    await tester.pumpAndSettle();
    expect(find.text('Autorize o histórico primeiro'), findsOneWidget);
    expect(repo.historyReads, 0);
    await tester.tap(find.text('Ir para Uso'));
    expect(openUsage, 1);
    repo
      ..permission = true
      ..selected = {};
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Escolha os aplicativos'), findsOneWidget);
    expect(repo.historyReads, 0);
  });

  testWidgets('failed forecasts can be retried without stale results',
      (tester) async {
    final repo = PredictionRepositoryFake()..failHistory = true;
    await tester.pumpWidget(MaterialApp(
        home: PredictionScreen(
            repository: repo,
            calculator: CalculatorFake(),
            onOpenUsage: () {})));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tentar novamente'), 150);
    repo.failHistory = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('PREVISÃO · 7 DIAS'), 150);
    expect(find.text('Previsão indisponível agora'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
