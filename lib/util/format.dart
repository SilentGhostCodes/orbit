import 'package:orbit/data/models.dart';

/// Russian plural form: [one] for 1, 21…; [few] for 2–4, 22…; [many] for the rest.
String plural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

String daysLabel(int n) => '$n ${plural(n, 'день', 'дня', 'дней')}';

String serversLabel(int n) => '$n ${plural(n, 'сервер', 'сервера', 'серверов')}';

/// Gigabytes, without a decimal part once the value is large enough to make it noise.
String gigabytes(int bytes) {
  final gb = bytes / (1024 * 1024 * 1024);
  if (gb >= 10 || gb == gb.roundToDouble()) return gb.round().toString();
  return gb.toStringAsFixed(1).replaceAll('.', ',');
}

/// "350 МБ", "1,2 ГБ", "48 ГБ".
String formatSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes < 1024 * mb) {
    final m = bytes / mb;
    if (m == 0) return '0 МБ';
    return '${m < 10 ? m.toStringAsFixed(1).replaceAll('.', ',') : m.round()} МБ';
  }
  return '${gigabytes(bytes)} ГБ';
}

String formatElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// The subscription line: traffic, and days left that can be tinted when they run out.
class SubscriptionSummary {
  const SubscriptionSummary({required this.traffic, required this.ratio, this.days, this.daysLow = false});

  /// "48 из 100 ГБ", or "12 ГБ из ∞" when the traffic is unlimited.
  final String traffic;

  /// "29 дней", or null when the subscription reports no expiry.
  final String? days;

  /// Few days left, or already expired.
  final bool daysLow;

  /// The share of traffic used, 0..1; 0 for unlimited.
  final double ratio;
}

SubscriptionSummary summarize(Subscription s) {
  final unlimited = s.total <= 0;
  const gb = 1024 * 1024 * 1024;
  final String traffic;
  if (unlimited) {
    traffic = '${formatSize(s.used)} из ∞';
  } else if (s.used >= gb) {
    // both in GB: "48 из 100 ГБ", as in the design
    traffic = '${gigabytes(s.used)} из ${formatSize(s.total)}';
  } else {
    traffic = '${formatSize(s.used)} из ${formatSize(s.total)}';
  }
  String? days;
  var low = false;
  if (s.expire != null) {
    final left = s.expire!.difference(DateTime.now());
    if (left.isNegative) {
      days = 'истекла';
      low = true;
    } else {
      final n = (left.inHours / 24).ceil();
      days = daysLabel(n);
      low = n <= 3;
    }
  }
  return SubscriptionSummary(
    traffic: traffic,
    days: days,
    daysLow: low,
    ratio: unlimited ? 0 : (s.used / s.total).clamp(0, 1).toDouble(),
  );
}
