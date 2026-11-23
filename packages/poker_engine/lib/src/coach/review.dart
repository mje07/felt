import '../bots/preflop_chart.dart';
import '../game_state.dart';
import 'advisor.dart';
import 'notation.dart';
import 'ranges.dart';

enum Grade {
  best('Best', 100),
  good('Good', 85),
  inaccuracy('Inaccuracy', 60),
  mistake('Mistake', 30),
  blunder('Blunder', 0);

  const Grade(this.label, this.score);
  final String label;

  /// Contribution to the accuracy score.
  final int score;
}

enum MistakeKind {
  callingWithoutOdds('Calling without the odds'),
  foldingWithOdds('Folding with the odds'),
  missedValue('Missed value bets'),
  passiveWithStrong('Too passive with strong hands'),
  overplayedWeak('Overplaying weak hands'),
  preflopTooLoose('Playing too many hands preflop'),
  preflopTooTight('Folding playable hands preflop'),
  openLimp('Limping instead of raising');

  const MistakeKind(this.label);
  final String label;
}

/// The coach's verdict on one decision.
class DecisionReview {
  const DecisionReview({
    required this.street,
    required this.taken,
    required this.recommended,
    required this.grade,
    required this.explanation,
    this.kind,
    this.lossBb,
    this.equity,
    this.requiredEquity,
  });

  factory DecisionReview.fromJson(Map<String, Object?> j) => DecisionReview(
        street: Street.values.byName(j['street'] as String),
        taken: j['taken'] as String,
        recommended: j['rec'] as String,
        grade: Grade.values.byName(j['grade'] as String),
        explanation: j['text'] as String,
        kind: j['kind'] == null ? null : MistakeKind.values.byName(j['kind'] as String),
        lossBb: (j['loss'] as num?)?.toDouble(),
        equity: (j['eq'] as num?)?.toDouble(),
        requiredEquity: (j['req'] as num?)?.toDouble(),
      );

  final Street street;

  /// What the player did / what the coach preferred, e.g. "Call 40".
  final String taken, recommended;
  final Grade grade;
  final MistakeKind? kind;
  final String explanation;

  /// Estimated cost versus the best option, in big blinds (postflop).
  final double? lossBb;
  final double? equity, requiredEquity;

  Map<String, Object?> toJson() => {
        'street': street.name,
        'taken': taken,
        'rec': recommended,
        'grade': grade.name,
        'text': explanation,
        if (kind != null) 'kind': kind!.name,
        if (lossBb != null) 'loss': double.parse(lossBb!.toStringAsFixed(2)),
        if (equity != null) 'eq': double.parse(equity!.toStringAsFixed(3)),
        if (requiredEquity != null) 'req': double.parse(requiredEquity!.toStringAsFixed(3)),
      };
}

/// Mean decision score (0..100), or null with no decisions.
double? accuracyOf(Iterable<DecisionReview> reviews) {
  if (reviews.isEmpty) return null;
  return reviews.fold(0, (a, r) => a + r.grade.score) / reviews.length;
}

String _pct(double v) => '${(v * 100).round()}%';

/// Grades [taken] against the coach's analysis. Returns null for spots the
/// coach doesn't grade (short-stacked preflop).
DecisionReview? gradeDecision(DecisionAnalysis a, PlayerAction taken) {
  return a.isPreflop ? _gradePreflop(a, taken) : _gradePostflop(a, taken);
}

DecisionReview? _gradePreflop(DecisionAnalysis a, PlayerAction taken) {
  final adv = a.preflop;
  if (adv == null) return null;
  final did = switch (taken.type) {
    ActionType.fold => PreAction.fold,
    ActionType.check => PreAction.check,
    ActionType.call => PreAction.call,
    _ => PreAction.raise,
  };
  final rec = adv.action;
  final hand = startingHandName(a.handIndex);
  final pos = a.position ?? '';
  final chart = adv.chart;
  final chartPct = _pct(rangeFraction(chart.played));
  final pct = preflopPercentileOf(a.handIndex);
  final edge = pct + adv.depth; // weakest hand the chart plays
  final strength = edge <= 0 ? 1.0 : pct / edge; // 0 = best possible, 1 = at the edge

  final recLabel = switch (rec) {
    PreAction.raise => a.legal.isBet ? 'Bet' : (a.scenario == PreflopScenario.unopened ? 'Raise' : '3-bet'),
    PreAction.call => 'Call',
    PreAction.check => 'Check',
    PreAction.fold => 'Fold',
  };
  final takenLabel = a.describe(taken);
  String where() => a.scenario == PreflopScenario.unopened ? 'from the $pos' : 'in this spot (${a.scenario!.label.toLowerCase()})';

  Grade grade;
  MistakeKind? kind;
  String text;

  if (did == rec || (rec == PreAction.check && did == PreAction.check)) {
    grade = Grade.best;
    text = rec == PreAction.fold
        ? '$hand is outside the baseline range ${where()} ($chartPct of hands). Folding is right.'
        : '$hand is in the baseline ${rec == PreAction.raise ? 'raising' : 'calling'} range ${where()}.';
  } else if (did == PreAction.fold) {
    kind = MistakeKind.preflopTooTight;
    grade = strength < 0.25 ? Grade.blunder : (strength < 0.6 ? Grade.mistake : Grade.inaccuracy);
    text = '$hand is a ${strength < 0.25 ? 'premium' : 'playable'} hand ${where()} — the baseline chart plays '
        'the top $chartPct. ${recLabel == 'Call' ? 'Calling' : 'Raising'} was better than folding.';
  } else if (rec == PreAction.fold || rec == PreAction.check) {
    final outside = -adv.depth;
    kind = MistakeKind.preflopTooLoose;
    grade = outside < 0.08 ? Grade.inaccuracy : (outside < 0.3 ? Grade.mistake : Grade.blunder);
    if (rec == PreAction.check && did == PreAction.raise) {
      grade = outside < 0.15 ? Grade.good : Grade.inaccuracy;
    }
    text = rec == PreAction.check
        ? '$hand isn\'t strong enough to raise over the limpers here; checking your option is fine.'
        : '$hand is ${outside < 0.08 ? 'just' : 'well'} outside the baseline range ${where()}, which plays the '
            'top $chartPct of hands. Folding was better.';
  } else if (rec == PreAction.raise && did == PreAction.call) {
    if (a.scenario == PreflopScenario.unopened) {
      kind = MistakeKind.openLimp;
      grade = Grade.inaccuracy;
      text = 'Limping $hand lets the blinds in cheaply. Open with a raise instead — it can win the pot right away.';
    } else if (strength < 0.3) {
      kind = MistakeKind.passiveWithStrong;
      grade = Grade.inaccuracy;
      text = '$hand is strong enough to re-raise here; just calling lets opponents see a cheap flop.';
    } else {
      grade = Grade.good;
      text = '$hand is in the 3-bet range, but calling is a reasonable mix.';
    }
  } else {
    // Recommended call, player raised.
    grade = strength < 0.5 ? Grade.good : Grade.inaccuracy;
    kind = grade == Grade.inaccuracy ? MistakeKind.preflopTooLoose : null;
    text = grade == Grade.good
        ? '$hand is a call in the baseline chart; raising it is a reasonable deviation.'
        : '$hand plays better as a call here; raising it turns a decent hand into a bluff.';
  }

  return DecisionReview(
    street: Street.preflop,
    taken: takenLabel,
    recommended: rec == PreAction.raise && a.legal.canRaise
        ? recLabel
        : (rec == PreAction.call && a.legal.canCheck ? 'Check' : recLabel),
    grade: grade,
    kind: kind,
    explanation: text,
  );
}

DecisionReview _gradePostflop(DecisionAnalysis a, PlayerAction taken) {
  final best = a.best;
  final takenEv = a.evOf(taken);
  final loss = (best.ev - takenEv).clamp(0.0, double.infinity);
  final lossBb = loss / a.bigBlind;
  final frac = loss / (a.pot <= 0 ? 1 : a.pot);
  final e = a.equity ?? 0;
  final req = a.requiredEquity;

  Grade grade;
  if (lossBb < 0.5 || frac <= 0.02) {
    grade = Grade.best;
  } else if (frac <= 0.08) {
    grade = Grade.good;
  } else if (frac <= 0.2) {
    grade = Grade.inaccuracy;
  } else if (frac <= 0.45) {
    grade = Grade.mistake;
  } else {
    grade = Grade.blunder;
  }

  bool aggressive(ActionType t) => t == ActionType.bet || t == ActionType.raise;
  // A pure sizing disagreement (both bets/raises) is graded Good at worst:
  // the EV model is an estimate, not a solver, and sizing is where it is weakest.
  final sizingOnly = aggressive(taken.type) && aggressive(best.action.type);
  if (sizingOnly && grade.index > Grade.good.index) grade = Grade.good;
  MistakeKind? kind;
  if (grade.index >= Grade.inaccuracy.index) {
    if (taken.type == ActionType.call && best.action.type == ActionType.fold) {
      kind = MistakeKind.callingWithoutOdds;
    } else if (taken.type == ActionType.fold) {
      kind = MistakeKind.foldingWithOdds;
    } else if (taken.type == ActionType.check && aggressive(best.action.type) && e >= 0.55) {
      kind = MistakeKind.missedValue;
    } else if (taken.type == ActionType.call && aggressive(best.action.type) && e >= 0.6) {
      kind = MistakeKind.passiveWithStrong;
    } else if (aggressive(taken.type) && !aggressive(best.action.type)) {
      kind = MistakeKind.overplayedWeak;
    }
  }

  final bestLabel = a.describe(best.action);
  final takenLabel = a.describe(taken);
  final who = a.opponentNote;
  final eq = _pct(e);
  final String text;
  switch (kind) {
    case MistakeKind.callingWithoutOdds:
      text = 'You called ${a.legal.callAmount} into ${a.pot}, which needs ${_pct(req)} equity. Against $who you had '
          'about $eq. Folding was better.';
    case MistakeKind.foldingWithOdds:
      text = req > 0
          ? 'You needed ${_pct(req)} equity to call and had about $eq against $who. $bestLabel was better than folding.'
          : 'Folding when you could check is never right — checking was free.';
    case MistakeKind.missedValue:
      text = 'With about $eq equity against $who, checking gives up value. $bestLabel gets paid by worse hands.';
    case MistakeKind.passiveWithStrong:
      text = 'You were well ahead (about $eq). $bestLabel builds the pot while you have the best of it.';
    case MistakeKind.overplayedWeak:
      text = 'With about $eq equity, betting mostly gets called by better hands and folds out worse ones. '
          '$bestLabel was better.';
    case MistakeKind.preflopTooLoose:
    case MistakeKind.preflopTooTight:
    case MistakeKind.openLimp:
    case null:
      if (grade == Grade.best) {
        text = 'Good decision. With about $eq equity against $who, $takenLabel was the strongest option.';
      } else if (grade == Grade.good) {
        text = '$takenLabel is fine; $bestLabel was slightly better (equity about $eq).';
      } else {
        text = '$bestLabel was better than $takenLabel here (equity about $eq against $who).';
      }
  }

  return DecisionReview(
    street: a.street,
    taken: takenLabel,
    recommended: bestLabel,
    grade: grade,
    kind: kind,
    explanation: text,
    lossBb: lossBb,
    equity: e,
    requiredEquity: req > 0 ? req : null,
  );
}
