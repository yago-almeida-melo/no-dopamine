import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_dopamine/features/usage_monitoring/data/usage_repository.dart';
import 'package:no_dopamine/features/usage_monitoring/domain/usage_models.dart';
import 'package:no_dopamine/features/usage_monitoring/presentation/usage_dashboard.dart';

class FakeRepository implements UsageRepository {
  @override
  Future<UsageSnapshot> loadHistory(DateTime start, DateTime end) =>
      loadUsage(start, end);
  bool permission = false;
  bool supported = true;
  bool fail = false;
  int settingsOpened = 0;
  Set<String> selected = {};
  final ranges = <(DateTime, DateTime)>[];

  @override
  Future<UsageState> loadState() async {
    if (fail) throw StateError('offline');
    return UsageState(
        supported: supported,
        hasPermission: permission,
        apps: const [
          TrackedApp(id: 'com.instagram.android', name: 'Instagram'),
          TrackedApp(id: 'com.google.android.youtube', name: 'YouTube')
        ],
        selectedIds: {
          ...selected
        });
  }

  @override
  Future<void> openPermissionSettings() async {
    settingsOpened++;
  }

  @override
  Future<void> saveSelection(Set<String> packages) async {
    selected = {...packages};
  }

  @override
  Future<UsageSnapshot> loadUsage(DateTime start, DateTime end) async {
    ranges.add((start, end));
    return UsageSnapshot(syncedAt: end, events: [
      UsageEvent(
          timestamp: start.add(const Duration(hours: 1)),
          type: 1,
          package: 'com.instagram.android'),
      UsageEvent(
          timestamp: start.add(const Duration(hours: 1, minutes: 30)),
          type: 2,
          package: 'com.instagram.android'),
    ], coverage: [
      for (final app in selected) UsageCoverage(app, start, end)
    ]);
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeRepository repository) async {
    await tester
        .pumpWidget(MaterialApp(home: UsageDashboard(repository: repository)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'permission is explicit and apps are persisted before reading usage',
      (tester) async {
    final repo = FakeRepository();
    await open(tester, repo);
    expect(find.text('Autorizar acesso de uso'), findsOneWidget);
    expect(repo.ranges, isEmpty);
    await tester.tap(find.text('Autorizar acesso de uso'));
    await tester.pumpAndSettle();
    expect(repo.settingsOpened, 1);
    await tester.ensureVisible(find.text('Escolher apps'));
    await tester.tap(find.text('Escolher apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-com.instagram.android')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar seleção (1)'));
    await tester.pumpAndSettle();
    expect(repo.selected, {'com.instagram.android'});
    expect(repo.ranges, isEmpty);
    repo.permission = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.ranges.length, 1);
    expect(find.text('Autorizar acesso de uso'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('day and week query different calendar ranges', (tester) async {
    final repo = FakeRepository()
      ..permission = true
      ..selected = {'com.instagram.android'};
    await open(tester, repo);
    expect(repo.ranges.last.$2.difference(repo.ranges.last.$1).inDays, 1);
    await tester.ensureVisible(find.text('Semana'));
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    expect(repo.ranges.last.$1.weekday, DateTime.monday);
    expect(repo.ranges.last.$2.difference(repo.ranges.last.$1).inDays, 7);
    await tester.scrollUntilVisible(find.text('TEMPO NA SEMANA'), 250);
    expect(find.text('30 min'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoking access removes cached report on resume',
      (tester) async {
    final repo = FakeRepository()
      ..permission = true
      ..selected = {'com.instagram.android'};
    await open(tester, repo);
    repo.permission = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Autorizar acesso de uso'), findsOneWidget);
    expect(find.text('TEMPO NO DIA'), findsNothing);
  });

  testWidgets('read failures offer retry and unsupported platforms stay usable',
      (tester) async {
    final repo = FakeRepository()..fail = true;
    await open(tester, repo);
    expect(find.text('Tentar novamente'), findsOneWidget);
    repo
      ..fail = false
      ..supported = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Disponível no Android'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
