import '../../usage_monitoring/presentation/usage_format.dart';

Duration forecastDuration(double minutes) =>
    Duration(milliseconds: (minutes * Duration.millisecondsPerMinute).round());

String forecastTime(double minutes) =>
    formatDuration(forecastDuration(minutes));

String forecastChange(double difference, double? percent) {
  final prefix = difference > .01
      ? '+'
      : difference < -.01
          ? '−'
          : '';
  final time = '$prefix${forecastTime(difference.abs())}';
  if (percent == null) return time;
  final value = percent.abs().toStringAsFixed(1).replaceAll('.', ',');
  return '$time ($prefix$value%)';
}

String forecastRange(DateTime start, DateTime end) {
  final last = DateTime(end.year, end.month, end.day - 1);
  return '${formatDate(start)} – ${formatDate(last)}';
}
