import 'package:flutter/material.dart';

import '../domain/usage_analytics.dart';
import '../domain/usage_models.dart';
import 'app_picker.dart';
import 'usage_format.dart';
import 'usage_notice.dart';

class UsageReportView extends StatefulWidget {
  const UsageReportView({required this.report, super.key});
  final UsageReport report;

  @override
  State<UsageReportView> createState() => _UsageReportViewState();
}

class _UsageReportViewState extends State<UsageReportView> {
  String? _logApp;
  int _logLimit = 30;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final ranked = [...report.apps]
      ..sort((a, b) => report.totals[b.id]!.compareTo(report.totals[a.id]!));
    final logs = report.sessions
        .where((s) => _logApp == null || s.package == _logApp)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!report.isComplete) ...[
        const UsageNotice(
            icon: Icons.info_outline,
            title: 'Histórico parcial neste período',
            description:
                'O Android mantém os eventos detalhados por poucos dias. '
                'Mostramos somente os registros disponíveis e os já salvos pelo app. '
                'Um intervalo sem registros pode ter uso não recuperado.'),
        const SizedBox(height: 16),
      ],
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: const Color(0xFF183F34),
            borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              report.period == UsagePeriod.day
                  ? 'TEMPO NO DIA'
                  : 'TEMPO NA SEMANA',
              style: const TextStyle(
                  color: Color(0xFFC4DED0), fontSize: 12, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          Text(formatDuration(report.total),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w700)),
          const Text('Soma dos aplicativos selecionados',
              style: TextStyle(color: Color(0xFFC4DED0), fontSize: 12)),
          const SizedBox(height: 14),
          Wrap(spacing: 20, runSpacing: 8, children: [
            Text('${report.sessions.length} sessões',
                style: const TextStyle(color: Color(0xFFD8E7DE))),
            Text('${report.apps.length} apps selecionados',
                style: const TextStyle(color: Color(0xFFD8E7DE))),
          ]),
          if (report.total > Duration.zero) ...[
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: Color(0xFF416354))),
            Text(
                'Mais usado: ${ranked.first.name} · ${formatDuration(report.totals[ranked.first.id]!)}',
                style: const TextStyle(color: Colors.white)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      _usageChart(report),
      const SizedBox(height: 16),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Comparação entre aplicativos',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Participação no tempo registrado'),
                  const SizedBox(height: 20),
                  for (final app in ranked)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppAvatar(app: app),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(app.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600))),
                                    const SizedBox(width: 8),
                                    Text(
                                        formatDuration(report.totals[app.id]!)),
                                  ]),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: _share(report, app.id),
                                    minHeight: 7,
                                    borderRadius: BorderRadius.circular(8),
                                    backgroundColor: const Color(0xFFEDF2ED),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                      '${(100 * _share(report, app.id)).round()}% do total',
                                      style: const TextStyle(
                                          color: Color(0xFF6B796F),
                                          fontSize: 12)),
                                ])),
                          ],
                        )),
                ],
              ))),
      const SizedBox(height: 24),
      const Text('Registros de uso',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
          'Sessões mais recentes primeiro · Atualizado às ${formatClock(report.syncedAt)}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B796F))),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _logApp ?? '',
        isExpanded: true,
        decoration: const InputDecoration(
            labelText: 'Filtrar registros por aplicativo',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)))),
        items: [
          const DropdownMenuItem(
              value: '', child: Text('Todos os selecionados')),
          for (final app in report.apps)
            DropdownMenuItem(value: app.id, child: Text(app.name)),
        ],
        onChanged: (value) => setState(() {
          _logApp = value == '' ? null : value;
          _logLimit = 30;
        }),
      ),
      const SizedBox(height: 14),
      if (logs.isEmpty)
        UsageNotice(
            icon: Icons.history_toggle_off,
            title: 'Nenhuma sessão registrada',
            description: report.isComplete
                ? 'Não houve uso dos aplicativos escolhidos neste período.'
                : 'Não encontramos sessões no histórico disponível para este período.'),
      for (var i = 0; i < logs.length && i < _logLimit; i++) ...[
        if (i == 0 || localDay(logs[i].start) != localDay(logs[i - 1].start))
          Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
              child: Text(
                  '${weekdays[logs[i].start.weekday - 1]}, ${formatDate(logs[i].start)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Color(0xFF6B796F)))),
        _sessionTile(
            logs[i], report.apps.firstWhere((a) => a.id == logs[i].package)),
        const SizedBox(height: 8),
      ],
      if (logs.length > _logLimit)
        TextButton(
          onPressed: () => setState(() => _logLimit += 30),
          child: Text('Ver mais registros (${logs.length - _logLimit})'),
        ),
    ]);
  }

  double _share(UsageReport report, String id) =>
      report.total.inMilliseconds == 0
          ? 0
          : report.totals[id]!.inMilliseconds / report.total.inMilliseconds;

  Widget _sessionTile(UsageSession session, TrackedApp app) => Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              AppAvatar(app: app, size: 36),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(app.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                        '${formatClock(session.start)} → ${session.isOngoing ? 'até a atualização' : formatClock(session.end)}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B796F))),
                  ])),
              const SizedBox(width: 8),
              Text(formatDuration(session.duration),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ])),
      );

  Widget _usageChart(UsageReport report) {
    final maxMs = report.buckets.fold<int>(
        0,
        (a, b) =>
            b.duration.inMilliseconds > a ? b.duration.inMilliseconds : a);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    report.period == UsagePeriod.day
                        ? 'Uso ao longo do dia'
                        : 'Uso por dia da semana',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Pico: ${formatDuration(Duration(milliseconds: maxMs))}',
                    style: const TextStyle(
                        color: Color(0xFF6B796F), fontSize: 12)),
                const SizedBox(height: 24),
                SizedBox(
                    height: 132,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < report.buckets.length; i++)
                            Expanded(
                                child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: report.period == UsagePeriod.day
                                      ? 1.5
                                      : 6),
                              child: _bar(report.buckets[i], i, maxMs, report),
                            )),
                        ])),
                const SizedBox(height: 12),
                const Text(
                    'Toque nas barras para ver os tempos. Barras claras indicam histórico parcial.',
                    style: TextStyle(color: Color(0xFF6B796F), fontSize: 11)),
              ],
            )));
  }

  Widget _bar(UsageBucket bucket, int index, int maxMs, UsageReport report) {
    final future = !bucket.start.isBefore(report.syncedAt);
    final value = bucket.duration.inMilliseconds;
    final label =
        report.period == UsagePeriod.day ? '${index}h' : weekdays[index];
    final tip =
        '$label: ${future ? 'período futuro' : formatDuration(bucket.duration)}'
        '${bucket.isComplete ? '' : ' · histórico parcial'}';
    return Tooltip(
      message: tip,
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
          label: tip,
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Expanded(
                child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      height: future || value == 0
                          ? 4
                          : (maxMs == 0 ? 4 : 96 * value / maxMs)
                              .clamp(4, 96)
                              .toDouble(),
                      decoration: BoxDecoration(
                        color: future
                            ? const Color(0xFFEDF2ED)
                            : bucket.isComplete
                                ? const Color(0xFF386A5E)
                                : const Color(0xFF9BB6AA),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ))),
            const SizedBox(height: 10),
            SizedBox(
                height: 22,
                child: Text(
                    report.period == UsagePeriod.week
                        ? label
                        : index % 4 == 0
                            ? '$index'
                            : '',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF6B796F)))),
          ])),
    );
  }
}
