import 'dart:math';

import 'bots/preflop_chart.dart';
import 'history.dart';

/// Table positions, in action order (preflop) for display.
const positionOrder = ['UTG', 'MP', 'HJ', 'CO', 'BTN', 'SB', 'BB'];

class PositionStats {
  int hands = 0, vpip = 0;
  double netBb = 0;
  double get bbPer100 => hands == 0 ? 0 : netBb / hands * 100;
  double get vpipPct => hands == 0 ? 0 : vpip / hands;
}

/// Aggregated player statistics computed from hand histories.
class PlayerStats {
  int hands = 0, handsWon = 0;
  int netChips = 0;
  double netBb = 0;

  // Preflop.
  int vpip = 0, pfr = 0, threeBetOpp = 0, threeBet = 0, limps = 0;

  // Postflop actions (flop, turn, river).
  int postBets = 0, postRaises = 0, postCalls = 0, postChecks = 0, postFolds = 0;

  int sawFlop = 0, wonWhenSawFlop = 0, showdowns = 0, wonAtShowdown = 0;
  int cbetOpp = 0, cbet = 0, foldToCbetOpp = 0, foldToCbet = 0;

  double biggestPotBb = 0;
  int? bestHandValue;

  /// Running net result in big blinds after each hand.
  final List<double> bankrollBb = [];
  final Map<String, PositionStats> byPosition = {for (final p in positionOrder) p: PositionStats()};

  /// Per starting-hand grid cell (see [startingHandIndex]).
  final List<int> handCount = List.filled(169, 0);
  final List<double> handNetBb = List.filled(169, 0);

  static double _r(int a, int b) => b == 0 ? 0 : a / b;

  double get vpipPct => _r(vpip, hands);
  double get pfrPct => _r(pfr, hands);
  double get threeBetPct => _r(threeBet, threeBetOpp);
  double get winRate => _r(handsWon, hands);
  double get bbPer100 => hands == 0 ? 0 : netBb / hands * 100;

  /// (bets + raises) / calls, postflop. Infinity-safe.
  double get aggressionFactor =>
      postCalls == 0 ? (postBets + postRaises).toDouble() : (postBets + postRaises) / postCalls;

  /// Share of postflop decisions that were bets or raises.
  double get aggressionFrequency =>
      _r(postBets + postRaises, postBets + postRaises + postCalls + postChecks + postFolds);
  double get wtsdPct => _r(showdowns, sawFlop);
  double get wsdPct => _r(wonAtShowdown, showdowns);
  double get wwsfPct => _r(wonWhenSawFlop, sawFlop);
  double get cbetPct => _r(cbet, cbetOpp);
  double get foldToCbetPct => _r(foldToCbet, foldToCbetOpp);
  double get sawFlopPct => _r(sawFlop, hands);
}

/// Position label for [seat] given the active seats of a hand.
String positionOf({required int seat, required int button, required int bbSeat, required List<int> active}) {
  final n = active.length;
  if (seat == button) return 'BTN';
  if (n == 2) return 'BB';
  if (seat == bbSeat) return 'BB';
  // Small blind is the seat after the button.
  final order = <int>[];
  final i0 = active.indexOf(button);
  for (var k = 1; k <= n; k++) {
    order.add(active[(i0 + k) % n]);
  }
  // order: SB, BB, then UTG ... CO, BTN (last).
  if (seat == order[0]) return 'SB';
  final rest = order.sublist(2, n - 1); // UTG..CO
  final idx = rest.indexOf(seat);
  final fromEnd = rest.length - 1 - idx;
  if (fromEnd == 0) return 'CO';
  if (fromEnd == 1) return 'HJ';
  return idx == 0 ? 'UTG' : 'MP';
}

PlayerStats computeStats(Iterable<HandHistory> histories) {
  final st = PlayerStats();
  var running = 0.0;
  for (final h in histories) {
    final start = h.events.firstWhere((e) => e['e'] == 'start', orElse: () => const {});
    if (start.isEmpty) continue;
    final seats = (start['seats'] as List).cast<Map>();
    final hero = h.heroSeat;
    if (hero >= seats.length || seats[hero]['inHand'] != true) continue;
    final bb = (start['bb'] as int?) ?? 1;
    final button = start['button'] as int;
    final active = [for (final s in seats) if (s['inHand'] == true) s['index'] as int];
    final pos = positionOf(seat: hero, button: button, bbSeat: start['bbSeat'] as int, active: active);

    st.hands++;
    st.netChips += h.heroNet;
    final netBb = h.heroNet / bb;
    st.netBb += netBb;
    running += netBb;
    st.bankrollBb.add(running);

    var raisesBefore = 0;
    var heroActedPre = false, heroVpip = false, heroPfr = false;
    var preAggressor = -1;
    var heroFolded = false, heroSawFlop = false;
    var street = 'preflop';
    // Flop c-bet tracking.
    var flopBetSeen = false, heroActedFlop = false, flopRaiseSeen = false;
    var aggressorCbet = false, heroRespondedCbet = false;
    var won = 0;

    for (final e in h.events) {
      switch (e['e']) {
        case 'street':
          street = e['street'] as String;
          if (street == 'flop' && !heroFolded) heroSawFlop = true;
        case 'act':
          final seat = e['seat'] as int;
          final type = e['type'] as String;
          final aggressive = type == 'bet' || type == 'raise';
          if (street == 'preflop') {
            if (seat == hero) {
              if (!heroActedPre && raisesBefore == 1 && preAggressor != hero) {
                st.threeBetOpp++;
                if (aggressive) st.threeBet++;
              }
              if (!heroActedPre && raisesBefore == 0 && type == 'call') st.limps++;
              heroActedPre = true;
              if (type == 'call' || aggressive) heroVpip = true;
              if (aggressive) heroPfr = true;
              if (type == 'fold') heroFolded = true;
            }
            if (aggressive) {
              raisesBefore++;
              preAggressor = seat;
            }
          } else {
            if (seat == hero) {
              switch (type) {
                case 'bet':
                  st.postBets++;
                case 'raise':
                  st.postRaises++;
                case 'call':
                  st.postCalls++;
                case 'check':
                  st.postChecks++;
                case 'fold':
                  st.postFolds++;
                  heroFolded = true;
              }
            }
            if (street == 'flop') {
              if (seat == hero && !heroActedFlop) {
                heroActedFlop = true;
                if (preAggressor == hero && !flopBetSeen) {
                  st.cbetOpp++;
                  if (type == 'bet') st.cbet++;
                }
              }
              if (seat == hero && aggressorCbet && !heroRespondedCbet && !flopRaiseSeen) {
                heroRespondedCbet = true;
                st.foldToCbetOpp++;
                if (type == 'fold') st.foldToCbet++;
              }
              if (type == 'bet' && !flopBetSeen) {
                flopBetSeen = true;
                if (seat == preAggressor && seat != hero) aggressorCbet = true;
              } else if (type == 'raise') {
                flopRaiseSeen = true;
              }
            }
          }
        case 'showdown':
          final hands = (e['hands'] as Map);
          final mine = hands['$hero'] as Map?;
          if (mine != null) {
            st.showdowns++;
            final v = mine['value'] as int;
            if (st.bestHandValue == null || v > st.bestHandValue!) st.bestHandValue = v;
          }
        case 'award':
          final shares = (e['shares'] as Map);
          final s = shares['$hero'];
          if (s != null) won += s as int;
      }
    }

    if (heroVpip) st.vpip++;
    if (heroPfr) st.pfr++;
    final ps = st.byPosition[pos]!;
    ps.hands++;
    ps.netBb += netBb;
    if (heroVpip) ps.vpip++;
    if (heroSawFlop) st.sawFlop++;
    if (won > 0) {
      st.handsWon++;
      if (heroSawFlop) st.wonWhenSawFlop++;
      st.biggestPotBb = max(st.biggestPotBb, won / bb);
    }
    final showdown = h.events.any((e) => e['e'] == 'showdown' && (e['hands'] as Map).containsKey('$hero'));
    if (showdown && won > 0) st.wonAtShowdown++;

    final hole = h.heroHole;
    if (hole != null && hole.length == 2) {
      final i = startingHandIndex(hole[0], hole[1]);
      st.handCount[i]++;
      st.handNetBb[i] += netBb;
    }
  }
  return st;
}

// ---------------------------------------------------------------- profile

enum Archetype {
  nit('The Nit', 'Ultra-tight', 'You wait for premium hands and fold almost everything else. Opponents '
      'will learn to get out of your way when you finally bet.'),
  rock('The Rock', 'Tight-passive', 'You play few hands and prefer calling to betting. Solid, but you leave '
      'money on the table by not pressing your edges.'),
  shark('The Shark', 'Tight-aggressive', 'Selective and assertive: you pick good spots and play them hard. '
      'This is the winning style most pros build from.'),
  maverick('The Maverick', 'Loose-aggressive', 'You play lots of hands and keep the pressure on. Dangerous and '
      'hard to read, but it demands sharp hand-reading to stay profitable.'),
  maniac('The Maniac', 'Hyper-aggressive', 'You bet and raise relentlessly with almost anything. It wins small '
      'pots, but strong hands will punish you in the big ones.'),
  station('The Calling Station', 'Loose-passive', 'You see lots of flops and call far more than you bet. '
      'Curious, but calling without strong hands is the costliest habit in poker.');

  const Archetype(this.title, this.style, this.description);
  final String title, style, description;
}

class Insight {
  const Insight(this.title, this.detail, {this.positive = false});
  final String title, detail;
  final bool positive;
}

class PlayerProfile {
  const PlayerProfile({
    required this.archetype,
    required this.looseness,
    required this.aggression,
    required this.confidence,
    required this.insights,
  });

  final Archetype archetype;

  /// 0..1 (VPIP-based) and 0..1 (blend of PFR/VPIP and postflop aggression).
  final double looseness, aggression;

  /// 0..1, grows with sample size.
  final double confidence;
  final List<Insight> insights;
}

/// Hands needed before a profile is shown.
const minHandsForProfile = 20;

PlayerProfile? profileFor(PlayerStats s) {
  if (s.hands < minHandsForProfile) return null;
  final vpip = s.vpipPct;
  final pfrRatio = s.vpip == 0 ? 0.0 : s.pfr / s.vpip;
  final postAggr = (s.aggressionFrequency / 0.5).clamp(0.0, 1.0);
  final aggression = (0.55 * pfrRatio.clamp(0.0, 1.0) + 0.45 * postAggr).clamp(0.0, 1.0);
  final looseness = (vpip / 0.6).clamp(0.0, 1.0);

  final Archetype a;
  if (vpip < 0.12) {
    a = Archetype.nit;
  } else if (vpip <= 0.26) {
    a = aggression >= 0.5 ? Archetype.shark : Archetype.rock;
  } else if (aggression >= 0.5) {
    a = vpip > 0.45 && aggression > 0.7 ? Archetype.maniac : Archetype.maverick;
  } else {
    a = Archetype.station;
  }

  return PlayerProfile(
    archetype: a,
    looseness: looseness,
    aggression: aggression,
    confidence: (s.hands / 500).clamp(0.0, 1.0),
    insights: _insights(s, pfrRatio),
  );
}

String _pct(double v) => '${(v * 100).round()}%';

List<Insight> _insights(PlayerStats s, double pfrRatio) {
  final out = <Insight>[];
  final vpip = s.vpipPct;

  if (vpip > 0.38) {
    out.add(Insight('Playing too many hands',
        'You put money in ${_pct(vpip)} of the time. Winning players are usually around 18–28%. '
        'Fold more weak offsuit hands, especially from early position.'));
  } else if (vpip < 0.13) {
    out.add(Insight('Very tight preflop',
        'At ${_pct(vpip)} VPIP opponents can fold to your raises. Open more hands from the cutoff and button '
        'to steal the blinds.'));
  } else {
    out.add(Insight('Healthy hand selection',
        'Your VPIP of ${_pct(vpip)} is in the range most winning players use.', positive: true));
  }

  if (s.vpip >= 10 && pfrRatio < 0.5) {
    out.add(Insight('Calling more than raising preflop',
        'Only ${_pct(pfrRatio)} of the hands you play are raised. Limping and flat-calling let opponents see '
        'cheap flops — raise or fold instead.'));
  }
  if (s.limps >= 5 && s.limps / max(1, s.vpip) > 0.25) {
    out.add(Insight('Open-limping',
        'You limped into ${s.limps} pots. Opening with a raise wins the blinds outright more often.'));
  }
  if (s.threeBetOpp >= 15) {
    final tb = s.threeBetPct;
    if (tb < 0.04) {
      out.add(Insight('Rarely 3-betting',
          'You re-raise only ${_pct(tb)} when facing a raise. Add 3-bets with premium hands and a few '
          'suited bluffs (A5s, KTs) to stop opponents opening freely.'));
    } else if (tb > 0.14) {
      out.add(Insight('3-betting a lot', 'You 3-bet ${_pct(tb)} of the time — strong opponents will start '
          '4-betting you light.'));
    }
  }

  final totalPost = s.postBets + s.postRaises + s.postCalls;
  if (totalPost >= 15) {
    final af = s.aggressionFactor;
    if (af < 1.2) {
      out.add(Insight('Passive after the flop',
          'Your aggression factor is ${af.toStringAsFixed(1)}. Bet your strong hands and good draws rather than '
          'calling — betting gives you two ways to win.'));
    } else if (af > 4.5) {
      out.add(Insight('Very aggressive after the flop',
          'An aggression factor of ${af.toStringAsFixed(1)} means you rarely call. Make sure your bluffs have '
          'outs, and let weaker hands bluff into you sometimes.'));
    } else {
      out.add(Insight('Balanced postflop aggression',
          'Aggression factor ${af.toStringAsFixed(1)} — you mix betting and calling well.', positive: true));
    }
  }

  if (s.sawFlop >= 15) {
    if (s.wtsdPct > 0.36) {
      out.add(Insight('Calling down too often',
          'You reach showdown in ${_pct(s.wtsdPct)} of flops seen. Let go of one-pair hands when opponents '
          'keep betting big.'));
    } else if (s.wtsdPct < 0.2) {
      out.add(Insight('Giving up easily', 'You only reach showdown ${_pct(s.wtsdPct)} of the time after seeing a '
          'flop — opponents may be bluffing you off the best hand.'));
    }
  }
  if (s.showdowns >= 12) {
    if (s.wsdPct < 0.45) {
      out.add(Insight('Losing at showdown',
          'You win ${_pct(s.wsdPct)} of showdowns. Showing down weaker hands than your opponents is a '
          'sign of calling too light.'));
    } else if (s.wsdPct > 0.55) {
      out.add(Insight('Strong at showdown',
          'You win ${_pct(s.wsdPct)} of showdowns — you get there with good hands.', positive: true));
    }
  }
  if (s.cbetOpp >= 10) {
    if (s.cbetPct < 0.45) {
      out.add(Insight('Missing continuation bets',
          'You c-bet ${_pct(s.cbetPct)} of flops after raising preflop. A small c-bet on dry boards wins the pot '
          'often.'));
    } else if (s.cbetPct > 0.85) {
      out.add(Insight('Auto-pilot c-betting', 'You c-bet ${_pct(s.cbetPct)} of flops. Check some boards that '
          'favour the caller, like low connected cards.'));
    }
  }
  if (s.foldToCbetOpp >= 10 && s.foldToCbetPct > 0.65) {
    out.add(Insight('Folding to c-bets',
        'You fold ${_pct(s.foldToCbetPct)} to continuation bets. Float or raise more with draws and '
        'overcards.'));
  }

  final positions = s.byPosition.entries.where((e) => e.value.hands >= 15).toList();
  if (positions.length >= 3) {
    positions.sort((a, b) => b.value.bbPer100.compareTo(a.value.bbPer100));
    final best = positions.first, worst = positions.last;
    if (best.value.netBb > 0) {
      out.add(Insight('Best seat: ${best.key}',
          'You win ${best.value.bbPer100.toStringAsFixed(1)} bb/100 from the ${best.key}.', positive: true));
    }
    if (worst.value.netBb < 0) {
      out.add(Insight('Leaking from ${worst.key}',
          'You lose ${(-worst.value.bbPer100).toStringAsFixed(1)} bb/100 from the ${worst.key}. '
          '${worst.key == 'SB' || worst.key == 'BB' ? 'Blinds lose money for everyone, but defend tighter out of position.' : 'Tighten your range in this seat.'}'));
    }
  }
  return out;
}
