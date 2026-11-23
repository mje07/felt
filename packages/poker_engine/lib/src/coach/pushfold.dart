import '../bots/preflop_chart.dart';
import 'ranges.dart';

/// Effective-stack buckets (big blinds) the push/fold charts cover.
const pushFoldStacks = [15, 12, 10, 8, 6, 4];

/// Nearest chart bucket for a stack in big blinds.
int stackBucket(double bb) =>
    pushFoldStacks.reduce((a, b) => (a - bb).abs() <= (b - bb).abs() ? a : b);

/// Approximate Nash shove widths, as the top fraction of starting hands,
/// by position × [pushFoldStacks]. Simplified from published push/fold
/// charts; tighter early, wider late and as stacks shrink.
const _shove = <String, List<double>>{
  'UTG': [0.07, 0.08, 0.09, 0.11, 0.14, 0.20],
  'MP': [0.09, 0.10, 0.12, 0.14, 0.18, 0.25],
  'HJ': [0.11, 0.13, 0.15, 0.18, 0.23, 0.30],
  'CO': [0.15, 0.18, 0.21, 0.25, 0.31, 0.40],
  'BTN': [0.22, 0.26, 0.30, 0.36, 0.44, 0.55],
  'SB': [0.35, 0.42, 0.48, 0.56, 0.66, 0.80],
  'HU': [0.50, 0.56, 0.62, 0.70, 0.80, 0.95], // heads-up small blind (button)
};

/// Calling widths against a shove, by who shoved × [pushFoldStacks].
const _call = <String, List<double>>{
  'early': [0.05, 0.06, 0.07, 0.09, 0.12, 0.18],
  'late': [0.09, 0.11, 0.13, 0.16, 0.21, 0.30],
  'sbVsBb': [0.15, 0.19, 0.23, 0.29, 0.38, 0.55],
  'HU': [0.20, 0.25, 0.30, 0.38, 0.50, 0.70],
};

Set<int> topFraction(double f) => {
      for (var i = 0; i < 169; i++)
        if (preflopPercentileOf(i) <= f + 1e-9) i
    };

/// Fraction of hands shoved from [position] with [bucket] big blinds.
double shoveWidth(String position, int bucket, {bool headsUp = false}) =>
    _shove[headsUp ? 'HU' : (_shove.containsKey(position) ? position : 'UTG')]![pushFoldStacks.indexOf(bucket)];

String _callKey(String? shoverPosition, String heroPosition, bool headsUp) {
  if (headsUp) return 'HU';
  if (shoverPosition == 'SB' && heroPosition == 'BB') return 'sbVsBb';
  const late = {'CO', 'BTN', 'SB'};
  return late.contains(shoverPosition) ? 'late' : 'early';
}

double callWidth(String? shoverPosition, String heroPosition, int bucket, {bool headsUp = false}) =>
    _call[_callKey(shoverPosition, heroPosition, headsUp)]![pushFoldStacks.indexOf(bucket)];

RangeChart shoveChart(String position, int bucket, {bool headsUp = false}) => RangeChart.sets(
      '${headsUp ? 'Heads-up' : position} shove · $bucket bb',
      topFraction(shoveWidth(position, bucket, headsUp: headsUp)),
    );

RangeChart callShoveChart(String? shoverPosition, String heroPosition, int bucket, {bool headsUp = false}) =>
    RangeChart.sets(
      'Call a ${shoverPosition ?? ''} shove · $bucket bb'.replaceAll('  ', ' '),
      const {},
      topFraction(callWidth(shoverPosition, heroPosition, bucket, headsUp: headsUp)),
    );

/// Push/fold advice for a short-stacked spot: shove-or-fold when unopened,
/// call-or-fold when facing a shove.
PreflopAdvice pushFoldAdvice({
  required String position,
  required double stackBb,
  required int handIndex,
  bool facingShove = false,
  String? shoverPosition,
  bool headsUp = false,
}) {
  final bucket = stackBucket(stackBb);
  final chart = facingShove
      ? callShoveChart(shoverPosition, position, bucket, headsUp: headsUp)
      : shoveChart(position, bucket, headsUp: headsUp && position == 'BTN');
  final played = chart.played;
  final edge = played.isEmpty ? 0.0 : played.map(preflopPercentileOf).reduce((a, b) => a > b ? a : b);
  return PreflopAdvice(chart.actionFor(handIndex), edge - preflopPercentileOf(handIndex), chart);
}
