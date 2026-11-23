import '../bots/preflop_table.g.dart';
import 'notation.dart';

/// Preflop situations the baseline charts cover.
enum PreflopScenario {
  /// Nobody has raised yet (limpers are treated as unopened: raise to isolate).
  unopened('Open raise'),

  /// Facing one raise from UTG / MP / HJ.
  vsEarlyOpen('Facing an early raise'),

  /// Facing one raise from CO / BTN / SB.
  vsLateOpen('Facing a late raise'),

  /// In the big blind facing one raise.
  bbDefense('Big blind defence'),

  /// Facing a 3-bet or more.
  vs3bet('Facing a 3-bet');

  const PreflopScenario(this.label);
  final String label;
}

enum PreAction { raise, call, check, fold }

/// A chart: hands to raise and hands to call (everything else folds).
class RangeChart {
  RangeChart(this.title, String raise, [String call = ''])
      : raise = parseRange(raise),
        call = parseRange(call).difference(parseRange(raise));
  final String title;
  final Set<int> raise, call;

  PreAction actionFor(int handIndex) =>
      raise.contains(handIndex) ? PreAction.raise : (call.contains(handIndex) ? PreAction.call : PreAction.fold);

  Set<int> get played => {...raise, ...call};
}

/// Baseline 100bb ring-game charts. Simplified from common published
/// starting-hand charts; not solver output.
final Map<String, RangeChart> openCharts = {
  'UTG': RangeChart('UTG open', '66+, A9s+, A5s-A4s, KTs+, QTs+, JTs, T9s, 98s, ATo+, KQo'),
  'MP': RangeChart('MP open', '55+, A8s+, A5s-A3s, K9s+, Q9s+, J9s+, T9s, 98s, 87s, ATo+, KJo+'),
  'HJ': RangeChart('HJ open', '44+, A2s+, K9s+, Q9s+, J9s+, T8s+, 97s+, 87s, 76s, ATo+, KJo+, QJo'),
  'CO': RangeChart(
      'CO open', '22+, A2s+, K7s+, Q8s+, J8s+, T8s+, 97s+, 86s+, 76s, 65s, 54s, A8o+, KTo+, QTo+, JTo'),
  'BTN': RangeChart('BTN open',
      '22+, A2s+, K2s+, Q5s+, J7s+, T7s+, 96s+, 85s+, 75s+, 64s+, 54s, 43s, A2o+, K8o+, Q9o+, J9o+, T9o, 98o'),
  'SB': RangeChart(
      'SB open', '22+, A2s+, K4s+, Q7s+, J7s+, T7s+, 97s+, 86s+, 75s+, 65s, 54s, A4o+, K9o+, QTo+, JTo'),
};

final RangeChart vsEarlyOpenChart = RangeChart(
  'Facing an early raise',
  'QQ+, AKs, AKo, A5s',
  'JJ-77, AQs-ATs, KQs, KJs, QJs, JTs, T9s, AQo',
);

final RangeChart vsLateOpenChart = RangeChart(
  'Facing a late raise',
  'TT+, AJs+, KQs, A5s-A4s, 76s, 65s, AQo+',
  '99-55, ATs-A8s, KJs, KTs, QJs, QTs, JTs, T9s, 98s, AJo, KQo',
);

final RangeChart bbDefenseChart = RangeChart(
  'Big blind defence',
  'JJ+, AQs+, AKo, A5s, A4s',
  '22-TT, A2s-AJs, K5s+, Q8s+, J8s+, T8s+, 97s+, 86s+, 75s+, 64s+, 54s, A8o-AQo, KTo+, QTo+, JTo',
);

final RangeChart vs3betChart = RangeChart('Facing a 3-bet', 'KK+, AKs', 'QQ-JJ, AKo, AQs');

/// Isolation raise over limpers from the big blind.
final RangeChart bbIsoChart = RangeChart('Big blind vs limpers', 'TT+, AQs+, AKo');

/// The chart for a spot. Position labels match `positionOf` in stats.dart.
RangeChart chartFor(String position, PreflopScenario scenario) {
  switch (scenario) {
    case PreflopScenario.unopened:
      if (position == 'BB') return bbIsoChart;
      return openCharts[position] ?? openCharts['UTG']!;
    case PreflopScenario.vsEarlyOpen:
      return position == 'BB' ? bbDefenseChart : vsEarlyOpenChart;
    case PreflopScenario.vsLateOpen:
      return position == 'BB' ? bbDefenseChart : vsLateOpenChart;
    case PreflopScenario.bbDefense:
      return bbDefenseChart;
    case PreflopScenario.vs3bet:
      return vs3betChart;
  }
}

class PreflopAdvice {
  const PreflopAdvice(this.action, this.depth, this.chart);

  /// Recommended action.
  final PreAction action;

  /// How far the hand is from the chart's edge, in hand-strength percentile:
  /// positive = inside the recommended range, negative = outside.
  final double depth;
  final RangeChart chart;
}

/// Advice for [handIndex] in a spot. In the unopened big blind, "fold"
/// becomes "check" (it's free).
PreflopAdvice adviseFor(String position, PreflopScenario scenario, int handIndex) {
  final chart = chartFor(position, scenario);
  var action = chart.actionFor(handIndex);
  if (scenario == PreflopScenario.unopened && position == 'BB' && action == PreAction.fold) {
    action = PreAction.check;
  }
  final pct = preflopPercentileTable[handIndex];
  final played = chart.played;
  final edge = played.isEmpty ? 0.0 : played.map((i) => preflopPercentileTable[i]).reduce((a, b) => a > b ? a : b);
  return PreflopAdvice(action, edge - pct, chart);
}

/// Classifies the preflop spot for the player to act.
PreflopScenario scenarioFor({required String position, required int raisesBefore, required String? openerPosition}) {
  if (raisesBefore == 0) return PreflopScenario.unopened;
  if (raisesBefore >= 2) return PreflopScenario.vs3bet;
  if (position == 'BB') return PreflopScenario.bbDefense;
  const late = {'CO', 'BTN', 'SB'};
  return late.contains(openerPosition) ? PreflopScenario.vsLateOpen : PreflopScenario.vsEarlyOpen;
}
