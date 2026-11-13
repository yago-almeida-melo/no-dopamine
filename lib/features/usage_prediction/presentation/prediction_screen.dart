import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../usage_monitoring/data/usage_repository.dart';
import '../../usage_monitoring/domain/usage_models.dart';
import '../../usage_monitoring/presentation/app_picker.dart';
import '../../usage_monitoring/presentation/usage_notice.dart';
import '../data/forecast_calculator.dart';
import '../domain/prediction_models.dart';
import 'prediction_report_view.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen(
      {required this.repository,
      required this.onOpenUsage,
      this.calculator,
      this.active = true,
      super.key});
  final UsageRepository repository;
  final ForecastCalculator? calculator;
  final VoidCallback onOpenUsage;
  final bool active;

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen>
    with WidgetsBindingObserver {
  late final ForecastCalculator _calculator =
      widget.calculator ?? LocalForecastCalculator();
  UsageState? _state;
  ForecastAnalysis? _analysis;
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PredictionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _analysis = null;
    });
    try {
      final state = await widget.repository.loadState();
      if (!mounted || request != _request) return;
      setState(() => _state = state);
      ForecastAnalysis? analysis;
      if (state.supported &&
          state.hasPermission &&
          state.selectedApps.isNotEmpty) {
        final today = localDay(DateTime.now());
        final snapshot = await widget.repository.loadHistory(
            DateTime(today.year, today.month,
                today.day - ForecastAnalysis.historyDays),
            DateTime(today.year, today.month, today.day + 1));
        if (!mounted || request != _request) return;
        analysis = await _calculator.calculate(snapshot, state.selectedApps);
      }
      if (!mounted || request != _request) return;
      setState(() {
        _analysis = analysis;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error is PlatformException && error.code == 'PERMISSION_DENIED'
            ? 'O acesso de uso foi desativado. Autorize novamente na aba Uso.'
            : 'Não foi possível calcular a previsão. Atualize o histórico e tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.auto_graph_rounded),
        title: const Text('Previsão de uso',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              onPressed: _loading ? null : _refresh,
              tooltip: 'Atualizar previsão',
              icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 8)
        ],
      ),
      body: SafeArea(
          child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const Text('Seu ritmo, mais adiante',
                style: TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8)),
            const SizedBox(height: 8),
            Text(
                'Uma projeção dos próximos 7 dias, aprendida com seu histórico.',
                style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            if (state?.supported == false)
              const UsageNotice(
                  icon: Icons.android,
                  title: 'Previsão disponível no Android',
                  description:
                      'Use o No Dopamine no seu celular para analisar o histórico real dos aplicativos.'),
            if (state?.supported == true && !state!.hasPermission)
              UsageNotice(
                  icon: Icons.lock_open_rounded,
                  title: 'Autorize o histórico primeiro',
                  description:
                      'A previsão usa os mesmos registros da aba Uso. Permita o acesso de uso no Android para começar.',
                  action: FilledButton(
                      onPressed: widget.onOpenUsage,
                      child: const Text('Ir para Uso'))),
            if (state?.supported == true &&
                state!.hasPermission &&
                state.selectedApps.isEmpty)
              UsageNotice(
                  icon: Icons.apps_rounded,
                  title: 'Escolha os aplicativos',
                  description:
                      'Selecione na aba Uso as redes que deseja incluir na previsão. A análise usará a mesma seleção.',
                  action: FilledButton(
                      onPressed: widget.onOpenUsage,
                      child: const Text('Escolher apps na aba Uso'))),
            if (state != null && state.selectedApps.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final app in state.selectedApps)
                  Chip(
                      avatar: AppAvatar(app: app, size: 22),
                      label: Text(app.name),
                      side: BorderSide.none,
                      backgroundColor: Colors.white),
              ]),
              const SizedBox(height: 16),
            ],
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(36),
                  child: Column(children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Analisando seu histórico…'),
                  ])),
            if (_error != null)
              UsageNotice(
                  icon: Icons.error_outline,
                  title: 'Previsão indisponível agora',
                  description: _error!,
                  action: Wrap(spacing: 8, children: [
                    FilledButton(
                        onPressed: _refresh,
                        child: const Text('Tentar novamente')),
                    TextButton(
                        onPressed: widget.onOpenUsage,
                        child: const Text('Ver histórico')),
                  ])),
            if (!_loading && _analysis != null)
              if (_analysis!.ready)
                PredictionReportView(analysis: _analysis!)
              else
                _insufficient(_analysis!),
            const SizedBox(height: 24),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, size: 17, color: Color(0xFF6B796F)),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Aprendizado no aparelho · Os registros ficam com você. '
                      'A previsão é uma estimativa e pode mudar com seus hábitos.',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: Color(0xFF6B796F)))),
            ]),
          ],
        ),
      )),
    );
  }

  Widget _insufficient(ForecastAnalysis analysis) => Card(
          child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.insights_outlined,
              size: 32, color: Color(0xFF386A5E)),
          const SizedBox(height: 16),
          const Text('Construindo sua base de previsão',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text(
              'Precisamos de pelo menos 14 dias completos e consecutivos para todos os apps escolhidos. '
              'Isso permite observar duas vezes cada dia da semana.'),
          const SizedBox(height: 20),
          LinearProgressIndicator(
              value: analysis.completeDays / ForecastAnalysis.minimumDays,
              minHeight: 9,
              borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 10),
          Text('${analysis.completeDays} de 14 dias completos',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
              'Faltam ${analysis.missingDays} dias de dados válidos na base recente. '
              'Hoje e intervalos com falhas não entram no treinamento.'),
          const SizedBox(height: 12),
          const Text(
              'Abra o app regularmente para preservar o histórico disponibilizado pelo Android. '
              'Uma rede adicionada recentemente pode ter menos dados disponíveis.'),
          const SizedBox(height: 16),
          OutlinedButton(
              onPressed: widget.onOpenUsage,
              child: const Text('Consultar os registros de uso')),
        ]),
      ));
}
