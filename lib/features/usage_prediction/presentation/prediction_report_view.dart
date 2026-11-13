import 'package:flutter/material.dart';

import '../../usage_monitoring/presentation/app_picker.dart';
import '../../usage_monitoring/presentation/usage_format.dart';
import '../domain/prediction_models.dart';
import 'prediction_format.dart';

class PredictionReportView extends StatelessWidget {
  const PredictionReportView({required this.analysis, super.key});
  final ForecastAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final growing = analysis.change > 1;
    final percent = analysis.changePercent;
    final stable =
        analysis.change.abs() <= 1 || (percent != null && percent.abs() < 3);
    final trend = stable
        ? 'Variação pequena estimada'
        : percent == null
            ? 'Uso projetado a partir do histórico'
            : growing
                ? 'Tendência de aumento'
                : 'Tendência de redução';
    final ranked = [...analysis.forecasts]
      ..sort((a, b) => b.change.compareTo(a.change));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: const Color(0xFF183F34),
            borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PREVISÃO · 7 DIAS',
              style: TextStyle(
                  color: Color(0xFFC4DED0), fontSize: 12, letterSpacing: 1.4)),
          const SizedBox(height: 6),
          Text(forecastRange(analysis.start, analysis.end),
              style: const TextStyle(color: Color(0xFFC4DED0))),
          const SizedBox(height: 14),
          Text(forecastTime(analysis.predictedMinutes),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w700)),
          const Text('Hoje e os próximos 6 dias · soma dos apps',
              style: TextStyle(color: Color(0xFFC4DED0), fontSize: 12)),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(color: Color(0xFF416354))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
                stable
                    ? Icons.trending_flat
                    : growing
                        ? Icons.trending_up
                        : Icons.trending_down,
                color: growing && !stable
                    ? const Color(0xFFFFD49C)
                    : const Color(0xFFC4DED0)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(trend,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(forecastChange(analysis.change, percent),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                      'em relação aos ${forecastTime(analysis.recentMinutes)} registrados nos últimos 7 dias completos.',
                      style: const TextStyle(
                          color: Color(0xFFC4DED0), height: 1.5)),
                  if (percent == null)
                    const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                            'Sem percentual de comparação: o período anterior teve uso zero.',
                            style: TextStyle(
                                color: Color(0xFFC4DED0), fontSize: 12))),
                ])),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      _qualityCard(),
      const SizedBox(height: 16),
      _comparisonChart(),
      const SizedBox(height: 24),
      const Text('O que pode mudar por app',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Comparação com os últimos 7 dias completos.',
          style: TextStyle(color: Color(0xFF6B796F), fontSize: 13)),
      const SizedBox(height: 14),
      for (final forecast in ranked) ...[
        _appCard(forecast),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 6),
      Card(
          child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.calendar_view_week_outlined),
        title: const Text('Previsão por dia',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Distribuição estimada dos 7 dias'),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          for (final day in analysis.daily)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Expanded(
                    child: Text(
                        '${weekdays[day.date.weekday - 1]}, ${formatDate(day.date)}')),
                const SizedBox(width: 12),
                Text(forecastTime(day.minutes),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            )
        ],
      )),
      const SizedBox(height: 16),
      _methodCard(),
    ]);
  }

  Widget _qualityCard() {
    final label = analysis.initial
        ? 'Estimativa inicial'
        : analysis.unstable
            ? 'Alta variação no histórico'
            : 'Modelo verificado no histórico';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.fact_check_outlined,
                      color: Color(0xFF386A5E)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 12),
                Text(
                    '${analysis.completeDays} dias completos de aprendizado · ${analysis.apps.length} apps'),
                const SizedBox(height: 10),
                if (analysis.initial)
                  const Text(
                      'A base ainda é curta. A projeção pode mudar bastante conforme novos dias entram no histórico.',
                      style: TextStyle(height: 1.5))
                else if (analysis.unstable)
                  const Text(
                      'Os hábitos variaram bastante no teste. Considere a previsão uma referência ampla.',
                      style: TextStyle(height: 1.5)),
                const SizedBox(height: 12),
                Text(
                    'Erro médio por dia no teste: ${forecastTime(analysis.testDailyMae)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text(
                    'Diferença no total da semana de teste: ${forecastTime(analysis.testWeeklyError)}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B796F))),
                const SizedBox(height: 8),
                const Text(
                    'Teste em 7 dias históricos separados da escolha do modelo. '
                    'Esse erro observado não é uma garantia de precisão futura.',
                    style: TextStyle(
                        fontSize: 12, height: 1.5, color: Color(0xFF6B796F))),
              ],
            )));
  }

  Widget _comparisonChart() {
    final values = [
      ...analysis.history.map((week) => week.minutes),
      analysis.predictedMinutes
    ];
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Das semanas anteriores à previsão',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Wrap(spacing: 18, runSpacing: 8, children: [
                  _Legend(color: Color(0xFF7F9F8F), text: 'Registrado'),
                  _Legend(color: Color(0xFFCA9759), text: 'Previsto'),
                ]),
                const SizedBox(height: 24),
                SizedBox(
                    height: 154,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < values.length; i++)
                            Expanded(
                                child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 7),
                              child: Tooltip(
                                triggerMode: TooltipTriggerMode.tap,
                                message: i == values.length - 1
                                    ? 'Previsão: ${forecastRange(analysis.start, analysis.end)} · ${forecastTime(values[i])}'
                                    : '${forecastRange(analysis.history[i].start, analysis.history[i].end)} · ${forecastTime(values[i])}',
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Expanded(
                                          child: Align(
                                              alignment: Alignment.bottomCenter,
                                              child: Container(
                                                width: double.infinity,
                                                height: max <= 0
                                                    ? 4
                                                    : (110 * values[i] / max)
                                                        .clamp(4, 110)
                                                        .toDouble(),
                                                decoration: BoxDecoration(
                                                    color:
                                                        i == values.length - 1
                                                            ? const Color(
                                                                0xFFCA9759)
                                                            : const Color(
                                                                0xFF7F9F8F),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8)),
                                              ))),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                          height: 30,
                                          child: Text(
                                              i == values.length - 1
                                                  ? 'Prev.'
                                                  : 'S−${values.length - 1 - i}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                    ]),
                              ),
                            )),
                        ])),
                const SizedBox(height: 8),
                const Text(
                    'Blocos de 7 dias. S−1 é o mais recente, encerrado ontem. '
                    'Toque nas barras para ver datas e tempos.',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF6B796F), height: 1.5)),
                const SizedBox(height: 12),
                for (final week in analysis.history)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Expanded(
                            child: Text(forecastRange(week.start, week.end),
                                style: const TextStyle(fontSize: 12))),
                        const SizedBox(width: 10),
                        Text(forecastTime(week.minutes),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ])),
              ],
            )));
  }

  Widget _appCard(AppForecast forecast) => Card(
          child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AppAvatar(app: forecast.app),
            const SizedBox(width: 12),
            Expanded(
                child: Text(forecast.app.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700))),
            const SizedBox(width: 10),
            Text(forecastTime(forecast.total),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          Text(forecastChange(forecast.change, forecast.changePercent),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: forecast.change > 1
                      ? const Color(0xFF92652E)
                      : const Color(0xFF386A5E))),
          const SizedBox(height: 5),
          Text(
              'Antes: ${forecastTime(forecast.recentMinutes)} · ${forecast.model.label}',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B796F), height: 1.5)),
        ]),
      ));

  Widget _methodCard() => Card(
          child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.psychology_outlined),
        title: const Text('Como a previsão é calculada',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Modelo, dados e limites'),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          const Text(
              'O aprendizado de máquina acontece no celular. Uma regressão Ridge aprende '
              'a tendência ao longo do tempo e diferenças entre os dias da semana.',
              style: TextStyle(height: 1.6)),
          const SizedBox(height: 12),
          Text(
              analysis.selectionFolds == 0
                  ? 'Com essa base inicial, usamos a regressão com maior regularização. '
                      'Ainda faltam semanas para comparar modelos em vários testes.'
                  : 'Para cada app, comparamos duas regressões com a repetição do padrão da última semana. '
                      'O método com menor erro combinado nos ${analysis.selectionFolds} testes semanais anteriores foi escolhido.',
              style: const TextStyle(height: 1.6)),
          const SizedBox(height: 12),
          const Text(
              'A semana histórica mais recente fica fora dessa escolha e mede o erro mostrado na tela. '
              'Depois, o modelo escolhido é treinado com todos os dias completos disponíveis, até 12 semanas.',
              style: TextStyle(height: 1.6)),
          const SizedBox(height: 12),
          const Text(
              'Hoje não entra no treinamento. O uso já registrado hoje é o mínimo da previsão para este dia. '
              'Dias com lacunas não são preenchidos com zero. Mudanças de rotina podem alterar o resultado.',
              style: TextStyle(height: 1.6)),
        ],
      ));
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 7),
        Text(text, style: const TextStyle(fontSize: 12)),
      ]);
}
