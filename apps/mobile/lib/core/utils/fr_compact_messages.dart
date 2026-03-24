import 'package:timeago/src/messages/lookupmessages.dart'; // ignore: implementation_imports

/// Compact French locale for timeago.
/// Produces condensed strings like "18h", "25 min", "3j", "2 mo."
class FrCompactMessages implements LookupMessages {
  @override
  String prefixAgo() => '';
  @override
  String prefixFromNow() => '';
  @override
  String suffixAgo() => '';
  @override
  String suffixFromNow() => '';
  @override
  String lessThanOneMinute(int seconds) => '< 1 min';
  @override
  String aboutAMinute(int minutes) => '1 min';
  @override
  String minutes(int minutes) => '$minutes min';
  @override
  String aboutAnHour(int minutes) => '1h';
  @override
  String hours(int hours) => '${hours}h';
  @override
  String aDay(int hours) => '1j';
  @override
  String days(int days) => '${days}j';
  @override
  String aboutAMonth(int days) => '1 mo.';
  @override
  String months(int months) => '$months mo.';
  @override
  String aboutAYear(int year) => '1 an';
  @override
  String years(int years) => '$years ans';
  @override
  String wordSeparator() => ' ';
}
