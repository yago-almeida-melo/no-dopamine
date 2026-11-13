import '../domain/usage_models.dart';

String formatDuration(Duration duration) {
  if (duration.inMilliseconds == 0) return '0 min';
  if (duration.inSeconds < 1) return '< 1 s';
  if (duration.inMinutes < 1) return '${duration.inSeconds} s';
  if (duration.inHours < 1) return '${duration.inMinutes} min';
  final minutes = duration.inMinutes.remainder(60);
  return '${duration.inHours} h${minutes == 0 ? '' : ' $minutes min'}';
}

String formatClock(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}:'
    '${date.second.toString().padLeft(2, '0')}';

const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];
const weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

String formatDate(DateTime date) => '${date.day} de ${_months[date.month - 1]}';

String periodLabel(DateTime start, UsagePeriod period) {
  if (period == UsagePeriod.day) {
    final today = localDay(DateTime.now());
    return '${start == today ? 'Hoje · ' : ''}${formatDate(start)}, ${start.year}';
  }
  final last = DateTime(start.year, start.month, start.day + 6);
  return '${formatDate(start)} – ${formatDate(last)}, ${last.year}';
}
