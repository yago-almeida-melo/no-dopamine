import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/usage_repository.dart';
import '../domain/usage_analytics.dart';
import '../domain/usage_models.dart';
import 'app_picker.dart';
import 'usage_format.dart';
import 'usage_notice.dart';
import 'usage_report_view.dart';

class UsageDashboard extends StatefulWidget {
  const UsageDashboard({super.key, this.repository, this.active = true});
  final UsageRepository? repository;
  final bool active;

  @override
  State<UsageDashboard> createState() => _UsageDashboardState();
}

class _UsageDashboardState extends State<UsageDashboard>
    with WidgetsBindingObserver {
  late final UsageRepository _repository =
      widget.repository ?? AndroidUsageRepository();
  UsageState? _state;
  UsageReport? _report;
  UsagePeriod _period = UsagePeriod.day;
  DateTime _date = localDay(DateTime.now());
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _refresh();
  }

  @override
  void didUpdateWidget(covariant UsageDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await _repository.loadState();
      if (!mounted || request != _request) return;
      setState(() => _state = state);
      UsageReport? report;
      if (state.supported &&
          state.hasPermission &&
          state.selectedApps.isNotEmpty) {
        final from = periodStart(_date, _period);
        final to = periodEnd(from, _period);
        final snapshot = await _repository.loadUsage(from, to);
        report = UsageReport(
            snapshot: snapshot,
            apps: state.selectedApps,
            start: from,
            end: to,
            period: _period);
      }
      if (!mounted || request != _request) return;
      setState(() {
        _state = state;
        _report = report;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _report = null;
        _error = error is PlatformException && error.code == 'PERMISSION_DENIED'
            ? 'O acesso de uso foi desativado. Autorize novamente nas configurações do Android.'
            : 'Não foi possível atualizar o histórico. Confira o acesso de uso e tente novamente.';
      });
    }
  }

  Future<void> _chooseApps() async {
    final state = _state;
    if (state == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AppPicker(
          apps: state.apps,
          selected: state.selectedIds,
          onSave: _repository.saveSelection),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _openPermission() async {
    try {
      await _repository.openPermissionSettings();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Abra Configurações > Acesso de uso e permita o No Dopamine.'),
        ));
    }
  }

  void _changePeriod(UsagePeriod value) {
    if (_period == value) return;
    setState(() {
      _period = value;
      _date = periodStart(_date, value);
    });
    _refresh();
  }

  void _navigate(int direction) {
    final step = _period == UsagePeriod.day ? 1 : 7;
    setState(() => _date =
        DateTime(_date.year, _date.month, _date.day + direction * step));
    _refresh();
  }

  Future<void> _pickDate() async {
    final now = localDay(DateTime.now());
    final first = DateTime(now.year, now.month, now.day - 89);
    final initial = _date.isBefore(first)
        ? first
        : _date.isAfter(now)
            ? now
            : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: now,
      helpText: _period == UsagePeriod.day
          ? 'Escolha o dia'
          : 'Escolha um dia da semana',
    );
    if (picked != null && mounted) {
      setState(() => _date = periodStart(picked, _period));
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('No Dopamine',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        leading: const Icon(Icons.spa_outlined),
        actions: [
          IconButton(
            tooltip: 'Atualizar histórico',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8)
        ],
      ),
      body: SafeArea(
          child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text('Seu tempo nas redes',
                style: TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8)),
            const SizedBox(height: 8),
            Text('Entenda seus hábitos, um dia de cada vez.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 15)),
            const SizedBox(height: 24),
            if (state?.supported == false)
              const UsageNotice(
                  icon: Icons.android,
                  title: 'Disponível no Android',
                  description:
                      'Abra o aplicativo no seu celular Android para selecionar redes e consultar o uso.'),
            if (state?.supported == true) ...[
              if (!state!.hasPermission) ...[
                UsageNotice(
                  icon: Icons.lock_open_rounded,
                  title: 'Permita o acesso de uso',
                  description:
                      'Para mostrar quando e por quanto tempo você usou os apps escolhidos, '
                      'autorize o No Dopamine no Android. Os registros ficam neste aparelho.',
                  action: FilledButton.icon(
                    onPressed: _openPermission,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Autorizar acesso de uso'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Expanded(
                                child: Text('Aplicativos acompanhados',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16))),
                            TextButton(
                                onPressed: _chooseApps,
                                child: const Text('Escolher apps')),
                          ]),
                          if (state.selectedApps.isEmpty)
                            const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                    'Escolha as redes sociais que você quer analisar.'))
                          else
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final app in state.selectedApps)
                                Chip(
                                  avatar: AppAvatar(app: app, size: 22),
                                  label: Text(app.name),
                                  side: BorderSide.none,
                                  backgroundColor: const Color(0xFFF1F5F1),
                                ),
                            ]),
                        ],
                      ))),
              const SizedBox(height: 24),
              _periodControls(),
              const SizedBox(height: 16),
            ],
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              UsageNotice(
                  icon: Icons.error_outline,
                  title: 'Não foi possível carregar',
                  description: _error!,
                  action: Wrap(spacing: 8, children: [
                    FilledButton(
                        onPressed: _refresh,
                        child: const Text('Tentar novamente')),
                    if (state?.supported == true)
                      TextButton(
                          onPressed: _openPermission,
                          child: const Text('Ver acesso de uso')),
                  ])),
            if (!_loading && _report != null)
              UsageReportView(
                key: ValueKey(
                    '${_report!.start}:${_report!.apps.map((a) => a.id).join(',')}'),
                report: _report!,
              ),
            const SizedBox(height: 24),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, size: 17, color: Color(0xFF6B796F)),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Histórico local · Sincronizado ao abrir ou atualizar o app. '
                      'Tempo calculado pelas sessões em primeiro plano.',
                      style: TextStyle(
                          color: Color(0xFF6B796F),
                          fontSize: 12,
                          height: 1.5))),
            ]),
          ],
        ),
      )),
    );
  }

  Widget _periodControls() {
    final now = localDay(DateTime.now());
    final start = periodStart(_date, _period);
    final earliest = DateTime(now.year, now.month, now.day - 89);
    return Column(children: [
      SizedBox(
          width: double.infinity,
          child: SegmentedButton<UsagePeriod>(
            segments: const [
              ButtonSegment(
                  value: UsagePeriod.day,
                  label: Text('Dia'),
                  icon: Icon(Icons.today_outlined)),
              ButtonSegment(
                  value: UsagePeriod.week,
                  label: Text('Semana'),
                  icon: Icon(Icons.date_range_outlined)),
            ],
            selected: {_period},
            onSelectionChanged: (value) => _changePeriod(value.single),
          )),
      const SizedBox(height: 12),
      Row(children: [
        IconButton(
            tooltip: 'Período anterior',
            onPressed: start.isAfter(periodStart(earliest, _period))
                ? () => _navigate(-1)
                : null,
            icon: const Icon(Icons.chevron_left)),
        Expanded(
            child: TextButton(
                onPressed: _pickDate,
                child: Text(periodLabel(start, _period),
                    textAlign: TextAlign.center))),
        IconButton(
            tooltip: 'Próximo período',
            onPressed: start.isBefore(periodStart(now, _period))
                ? () => _navigate(1)
                : null,
            icon: const Icon(Icons.chevron_right)),
      ]),
    ]);
  }
}
