import 'package:flutter/material.dart';

import '../../usage_monitoring/data/usage_repository.dart';
import '../../usage_monitoring/presentation/usage_dashboard.dart';
import '../../usage_prediction/data/forecast_calculator.dart';
import '../../usage_prediction/presentation/prediction_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.repository, this.calculator});
  final UsageRepository? repository;
  final ForecastCalculator? calculator;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final UsageRepository _repository =
      widget.repository ?? AndroidUsageRepository();
  int _tab = 0;
  bool _predictionOpened = false;

  void _select(int value) => setState(() {
        _tab = value;
        if (value == 1) _predictionOpened = true;
      });

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _tab == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _tab != 0) _select(0);
        },
        child: Scaffold(
          body: IndexedStack(index: _tab, children: [
            UsageDashboard(repository: _repository, active: _tab == 0),
            if (_predictionOpened)
              PredictionScreen(
                repository: _repository,
                calculator: widget.calculator,
                active: _tab == 1,
                onOpenUsage: () => _select(0),
              )
            else
              const SizedBox.shrink(),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _select,
            backgroundColor: Colors.white,
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart_rounded),
                  label: 'Uso'),
              NavigationDestination(
                  icon: Icon(Icons.auto_graph_outlined),
                  selectedIcon: Icon(Icons.auto_graph_rounded),
                  label: 'Previsão'),
            ],
          ),
        ),
      );
}
