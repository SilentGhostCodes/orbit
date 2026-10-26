import 'package:hiddify/features/profile/model/profile_entity.dart';

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

String formatBytes(int bytes) {
  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[unit]}';
}

String formatSpeed(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/с';

String formatElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// What the subscription line says, split so the days part can be tinted when they run out.
class SubscriptionSummary {
  const SubscriptionSummary({required this.traffic, this.days, this.daysLow = false, this.ratio});

  /// "48 из 100 ГБ" or "Безлимит".
  final String traffic;

  /// "29 дней", or null when the subscription reports no expiry.
  final String? days;

  /// Few days left, or already expired.
  final bool daysLow;

  /// The share of traffic used, 0..1, or null for unlimited.
  final double? ratio;

  String join([String? extra]) => [traffic, ?days, ?extra].join(' · ');
}

SubscriptionSummary summarize(ProfileEntity profile) {
  final info = switch (profile) {
    RemoteProfileEntity(:final subInfo) => subInfo,
    _ => null,
  };
  if (info == null) return const SubscriptionSummary(traffic: 'Безлимит');

  final unlimited = info.total <= 0;
  final traffic = unlimited ? 'Безлимит' : '${gigabytes(info.consumption)} из ${gigabytes(info.total)} ГБ';

  String? days;
  var low = false;
  // the panels send a far-future date (or 0) for "never expires"
  final expiresAt = info.expire;
  final neverExpires = expiresAt.year >= 2100 || expiresAt.millisecondsSinceEpoch <= 0;
  if (!neverExpires) {
    final left = expiresAt.difference(DateTime.now());
    if (left.isNegative) {
      days = 'истекла';
      low = true;
    } else {
      final n = (left.inHours / 24).ceil();
      days = daysLabel(n);
      low = n <= 3;
    }
  }
  return SubscriptionSummary(traffic: traffic, days: days, daysLow: low, ratio: unlimited ? null : info.ratio);
}
