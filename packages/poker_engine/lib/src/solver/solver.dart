import 'dart:math';
import 'dart:typed_data';

import '../card.dart';
import '../evaluator.dart';
import '../ranges/weighted_range.dart';

/// Bet sizes for one street, as fractions of the pot.
class StreetSizes {
  const StreetSizes({this.bet = const [0.33, 0.75], this.raise = const [0.75], this.oopBet});

  /// The in-position player's bets (and the out-of-position player's, unless
  /// [oopBet] is given).
  final List<double> bet;

  /// Raises, as a fraction of the pot after calling.
  final List<double> raise;

  /// Leads for the out-of-position player; empty means they always check to
  /// the in-position player first.
  final List<double>? oopBet;

  Map<String, Object?> toJson() => {'bet': bet, 'raise': raise, 'oopBet': oopBet};
}

/// A heads-up postflop spot to solve.
class SolverSpot {
  SolverSpot({
    required this.board,
    required this.pot,
    required this.stack,
    required this.oop,
    required this.ip,
    this.flop = const StreetSizes(),
    this.turn = const StreetSizes(bet: [0.66]),
    this.river = const StreetSizes(bet: [0.5, 1.0]),
    this.maxBetsPerStreet = 2,
    this.allInThreshold = 0.67,
    this.allInMaxSpr = 3,
    this.flopTurnCards = 8,
    this.flopRiverCards = 6,
  }) : assert(board.length >= 3 && board.length <= 5);

  /// 3–5 community cards.
  final List<int> board;

  /// Chips in the pot when the spot starts, and the effective stack behind.
  final int pot, stack;

  /// Out-of-position and in-position ranges.
  final WeightedRange oop, ip;
  final StreetSizes flop, turn, river;

  /// Bets plus raises allowed on one street (2 = a bet and one raise).
  final int maxBetsPerStreet;

  /// A bet or raise that would put in more than this share of the remaining
  /// stack becomes all-in.
  final double allInThreshold;

  /// All-in is offered as its own size only when the stack behind is at
  /// most this many pots (bets above that are rarely sensible).
  final double allInMaxSpr;

  /// Flop solves only: how many turn cards, and river cards per turn, are
  /// modelled (a sampled subset, spread across ranks and suits).
  final int flopTurnCards, flopRiverCards;

  StreetSizes sizesFor(int boardLen) => boardLen == 3 ? flop : (boardLen == 4 ? turn : river);
}

enum NodeKind { action, chance, fold, showdown }

/// One action at a decision point.
class SolverAction {
  const SolverAction(this.kind, this.amount);

  /// 'check', 'bet', 'call', 'raise', 'fold' or 'allin'.
  final String kind;

  /// For bets and raises: the player's total chips in on this hand (beyond
  /// their half of the starting pot) after the action. For calls: chips added.
  final int amount;

  bool get aggressive => kind == 'bet' || kind == 'raise' || kind == 'allin';
}

/// A node in the game tree.
class SolverNode {
  SolverNode._(this.kind, this.board, this.c0, this.c1, {this.player = -1, this.winner = -1});

  final NodeKind kind;

  /// Community cards at this node.
  final List<int> board;

  /// Chips each player has put in beyond their half of the starting pot.
  final int c0, c1;

  /// Acting player (0 = out of position, 1 = in position) for action nodes.
  final int player;

  /// Fold nodes: who wins.
  final int winner;

  final List<SolverAction> actions = [];
  final List<SolverNode> children = [];

  /// Chance nodes: the card dealt to reach each child.
  final List<int> cards = [];
  double chanceWeight = 0;

  // Action nodes: per action × hand of [player].
  Float32List regret = Float32List(0), strategySum = Float32List(0);

  int committed(int p) => p == 0 ? c0 : c1;
}

/// Solved (or solving) spot. Run [iterate], check [exploitability], then
/// read strategies with [averageStrategy] and values with [handEv].
class Solver {
  Solver(this.spot) {
    final dead = spot.board;
    for (var p = 0; p < 2; p++) {
      final r = (p == 0 ? spot.oop : spot.ip).removeDead(dead);
      final hands = r.live.toList();
      _hands[p] = Int32List.fromList(hands);
      _cardA[p] = Uint8List.fromList([for (final h in hands) comboCards[h].$1]);
      _cardB[p] = Uint8List.fromList([for (final h in hands) comboCards[h].$2]);
      _weight[p] = Float64List.fromList([for (final h in hands) r.w[h]]);
      final byCard = List.generate(52, (_) => <int>[]);
      for (var i = 0; i < hands.length; i++) {
        final (a, b) = comboCards[hands[i]];
        byCard[a].add(i);
        byCard[b].add(i);
      }
      _withCard[p] = [for (final l in byCard) Int32List.fromList(l)];
    }
    // Index of the identical combo in the other player's list.
    for (var p = 0; p < 2; p++) {
      final other = {for (var i = 0; i < _hands[1 - p].length; i++) _hands[1 - p][i]: i};
      _same[p] = Int32List.fromList([for (final h in _hands[p]) other[h] ?? -1]);
    }
    root = _build(List.of(spot.board), 0, 0, 0, 0, false, 0);
  }

  final SolverSpot spot;
  late final SolverNode root;
  final _hands = List<Int32List>.filled(2, Int32List(0));
  final _weight = List<Float64List>.filled(2, Float64List(0));
  final _withCard = List<List<Int32List>>.filled(2, const []);
  final _same = List<Int32List>.filled(2, Int32List(0));
  final _cardA = List<Uint8List>.filled(2, Uint8List(0)), _cardB = List<Uint8List>.filled(2, Uint8List(0));
  final _scratchSum = Float64List(52), _scratchBelow = Float64List(52), _scratchEq = Float64List(52);
  final Map<int, _Showdown> _showdowns = {};
  int iterations = 0;
  int nodeCount = 0;

  /// Combo indices (see [comboCards]) of each player's hands, in the order
  /// strategies and values are reported.
  Int32List hands(int player) => _hands[player];
  Float64List weights(int player) => _weight[player];

  double get _halfPot => spot.pot / 2;

  // ---------------------------------------------------------------- tree

  SolverNode _build(List<int> board, int c0, int c1, int toAct, int bets, bool checked, int lastRaise) {
    nodeCount++;
    final node = SolverNode._(NodeKind.action, board, c0, c1, player: toAct);
    final me = toAct == 0 ? c0 : c1, opp = toAct == 0 ? c1 : c0;
    final remaining = spot.stack - me;
    final pot = spot.pot + c0 + c1;
    final sizes = spot.sizesFor(board.length);
    final amounts = <int>{};

    void addAggressive(String kind, int to) {
      final maxTo = spot.stack;
      var t = min(to, maxTo);
      if (t - me >= remaining * spot.allInThreshold) t = maxTo;
      if (t <= opp || amounts.contains(t)) return;
      amounts.add(t);
      final allIn = t == maxTo;
      node.actions.add(SolverAction(allIn ? 'allin' : kind, t));
      final n0 = toAct == 0 ? t : c0, n1 = toAct == 1 ? t : c1;
      node.children.add(_build(board, n0, n1, 1 - toAct, bets + 1, false, t - opp));
    }

    if (opp == me) {
      // Check or bet.
      node.actions.add(const SolverAction('check', 0));
      node.children.add(toAct == 0 && !checked
          ? _build(board, c0, c1, 1, bets, true, 0)
          : _streetEnd(board, c0, c1));
      if (remaining > 0 && bets < spot.maxBetsPerStreet) {
        final fracs = toAct == 0 && sizes.oopBet != null ? sizes.oopBet! : sizes.bet;
        for (final f in fracs) {
          addAggressive('bet', me + max(1, (pot * f).round()));
        }
        if (fracs.isNotEmpty && remaining <= pot * spot.allInMaxSpr) addAggressive('bet', spot.stack);
      }
    } else {
      // Facing a bet: fold, call, raise.
      node.actions.add(const SolverAction('fold', 0));
      node.children.add(_terminalFold(board, c0, c1, 1 - toAct));
      final call = min(opp, spot.stack);
      node.actions.add(SolverAction('call', call - me));
      final n0 = toAct == 0 ? call : c0, n1 = toAct == 1 ? call : c1;
      node.children.add(call >= spot.stack || (toAct == 0 ? n1 : n0) >= spot.stack
          ? _runout(board, n0, n1)
          : _streetEnd(board, n0, n1));
      if (remaining > opp - me && bets < spot.maxBetsPerStreet && opp < spot.stack) {
        final potAfterCall = spot.pot + 2 * opp;
        for (final f in sizes.raise) {
          addAggressive('raise', opp + max(lastRaise, (potAfterCall * f).round()));
        }
        if (spot.stack - opp <= (spot.pot + 2 * opp) * spot.allInMaxSpr) addAggressive('raise', spot.stack);
      }
    }
    _initArrays(node);
    return node;
  }

  void _initArrays(SolverNode n) {
    final size = n.actions.length * _hands[n.player].length;
    n.regret = Float32List(size);
    n.strategySum = Float32List(size);
  }

  SolverNode _terminalFold(List<int> board, int c0, int c1, int winner) {
    nodeCount++;
    return SolverNode._(NodeKind.fold, board, c0, c1, winner: winner);
  }

  SolverNode _showdown(List<int> board, int c0, int c1) {
    nodeCount++;
    return SolverNode._(NodeKind.showdown, board, c0, c1);
  }

  /// Both players have acted on this street: next card, or showdown.
  SolverNode _streetEnd(List<int> board, int c0, int c1) {
    if (board.length == 5) return _showdown(board, c0, c1);
    return _chance(board, c0, c1, (next) => _build(next, c0, c1, 0, 0, false, 0));
  }

  /// Someone is all-in: deal the remaining cards, then show down.
  SolverNode _runout(List<int> board, int c0, int c1) {
    if (board.length == 5) return _showdown(board, c0, c1);
    return _chance(board, c0, c1, (next) => _runout(next, c0, c1));
  }

  SolverNode _chance(List<int> board, int c0, int c1, SolverNode Function(List<int>) child) {
    nodeCount++;
    final node = SolverNode._(NodeKind.chance, board, c0, c1);
    final deck = [for (var c = 0; c < 52; c++) if (!board.contains(c)) c];
    var cards = deck;
    final rootLen = spot.board.length;
    if (rootLen == 3) {
      // Flop solves model a spread-out subset of turn and river cards.
      final k = board.length == 3 ? spot.flopTurnCards : spot.flopRiverCards;
      if (k < deck.length) cards = _spread(deck, k, board);
    }
    // Probability of each dealt card for a pair of hands: 1 / (cards left
    // once both hands are out), scaled up when only a subset is modelled.
    node.chanceWeight = deck.length / ((deck.length - 4) * cards.length);
    for (final c in cards) {
      node.cards.add(c);
      node.children.add(child([...board, c]));
    }
    return node;
  }

  /// [k] cards from [deck], spread evenly across ranks and cycling suits,
  /// favouring suits that matter on this board (flush cards).
  static List<int> _spread(List<int> deck, int k, List<int> board) {
    final byRank = List.generate(13, (_) => <int>[]);
    for (final c in deck) {
      byRank[cardRank(c)].add(c);
    }
    final out = <int>[];
    for (var i = 0; i < k; i++) {
      final rank = 12 - (i * 13 ~/ k);
      final options = byRank[rank];
      if (options.isEmpty) continue;
      out.add(options[i % options.length]);
    }
    return out;
  }

  // ---------------------------------------------------------------- CFR

  /// Runs [n] iterations of Discounted CFR (α = 1.5, β = 0, γ = 2).
  void iterate(int n) {
    for (var k = 0; k < n; k++) {
      iterations++;
      final t = iterations.toDouble();
      for (var p = 0; p < 2; p++) {
        _cfr(root, p, Float64List.fromList(_weight[p]), Float64List.fromList(_weight[1 - p]));
      }
      final pos = pow(t, 1.5) / (pow(t, 1.5) + 1), neg = 0.5, strat = pow(t / (t + 1), 2).toDouble();
      _discount(root, pos.toDouble(), neg, strat);
    }
  }

  void _discount(SolverNode n, double pos, double neg, double strat) {
    if (n.kind == NodeKind.action) {
      final r = n.regret, s = n.strategySum;
      for (var i = 0; i < r.length; i++) {
        r[i] *= r[i] > 0 ? pos : neg;
        s[i] *= strat;
      }
    }
    for (final c in n.children) {
      _discount(c, pos, neg, strat);
    }
  }

  /// Current strategy from regrets (regret matching), actions × hands.
  Float64List _current(SolverNode n) {
    final a = n.actions.length, h = _hands[n.player].length;
    final out = Float64List(a * h);
    for (var j = 0; j < h; j++) {
      var sum = 0.0;
      for (var i = 0; i < a; i++) {
        final r = n.regret[i * h + j];
        if (r > 0) sum += r;
      }
      for (var i = 0; i < a; i++) {
        final r = n.regret[i * h + j];
        out[i * h + j] = sum > 0 ? (r > 0 ? r / sum : 0) : 1 / a;
      }
    }
    return out;
  }

  /// Average strategy (what the solver recommends), actions × hands.
  Float64List averageStrategy(SolverNode n) {
    final a = n.actions.length, h = _hands[n.player].length;
    final out = Float64List(a * h);
    for (var j = 0; j < h; j++) {
      var sum = 0.0;
      for (var i = 0; i < a; i++) {
        sum += n.strategySum[i * h + j];
      }
      for (var i = 0; i < a; i++) {
        out[i * h + j] = sum > 0 ? n.strategySum[i * h + j] / sum : 1 / a;
      }
    }
    return out;
  }

  /// Counterfactual values for [t]'s hands at [n], given both reaches.
  Float64List _cfr(SolverNode n, int t, Float64List reachSelf, Float64List reachOpp) {
    switch (n.kind) {
      case NodeKind.fold:
      case NodeKind.showdown:
        return _terminal(n, t, reachOpp);
      case NodeKind.chance:
        return _chanceValues(n, t, reachSelf, reachOpp, (c, rs, ro) => _cfr(c, t, rs, ro));
      case NodeKind.action:
        final a = n.actions.length;
        final sigma = _current(n);
        if (n.player == t) {
          final h = _hands[t].length;
          final value = Float64List(h);
          final childValues = <Float64List>[];
          for (var i = 0; i < a; i++) {
            final rs = Float64List(h);
            for (var j = 0; j < h; j++) {
              rs[j] = reachSelf[j] * sigma[i * h + j];
            }
            final v = _cfr(n.children[i], t, rs, reachOpp);
            childValues.add(v);
            for (var j = 0; j < h; j++) {
              value[j] += sigma[i * h + j] * v[j];
            }
          }
          for (var i = 0; i < a; i++) {
            final v = childValues[i];
            for (var j = 0; j < h; j++) {
              n.regret[i * h + j] += v[j] - value[j];
              n.strategySum[i * h + j] += reachSelf[j] * sigma[i * h + j];
            }
          }
          return value;
        } else {
          final ho = _hands[n.player].length, h = _hands[t].length;
          final value = Float64List(h);
          for (var i = 0; i < a; i++) {
            final ro = Float64List(ho);
            var any = false;
            for (var j = 0; j < ho; j++) {
              ro[j] = reachOpp[j] * sigma[i * ho + j];
              if (ro[j] > 0) any = true;
            }
            if (!any) continue;
            final v = _cfr(n.children[i], t, reachSelf, ro);
            for (var j = 0; j < h; j++) {
              value[j] += v[j];
            }
          }
          return value;
        }
    }
  }

  Float64List _chanceValues(SolverNode n, int t, Float64List reachSelf, Float64List reachOpp,
      Float64List Function(SolverNode, Float64List, Float64List) child) {
    final h = _hands[t].length;
    final value = Float64List(h);
    for (var k = 0; k < n.children.length; k++) {
      final card = n.cards[k];
      final rs = Float64List.fromList(reachSelf), ro = Float64List.fromList(reachOpp);
      for (final j in _withCard[t][card]) {
        rs[j] = 0;
      }
      for (final j in _withCard[1 - t][card]) {
        ro[j] = 0;
      }
      final v = child(n.children[k], rs, ro);
      final blocked = _withCard[t][card];
      final saved = [for (final j in blocked) value[j]];
      for (var j = 0; j < h; j++) {
        value[j] += n.chanceWeight * v[j];
      }
      // Hands holding the dealt card can't see this runout.
      for (var x = 0; x < blocked.length; x++) {
        value[blocked[x]] = saved[x];
      }
    }
    return value;
  }

  /// Fold or showdown: value for each of [t]'s hands, summed over the
  /// opponent's compatible hands weighted by their reach.
  Float64List _terminal(SolverNode n, int t, Float64List reachOpp) {
    final o = 1 - t;
    final h = _hands[t].length;
    final value = Float64List(h);
    final total = n.c0 + n.c1 + spot.pot;
    final invest = _halfPot + n.committed(t);
    final ta = _cardA[t], tb = _cardB[t], oa = _cardA[o], ob = _cardB[o];
    final same = _same[t];
    // Opponent reach per card, for card-removal corrections.
    var sumOpp = 0.0;
    final cardSum = _scratchSum..fillRange(0, 52, 0);
    for (var j = 0; j < reachOpp.length; j++) {
      final r = reachOpp[j];
      if (r == 0) continue;
      sumOpp += r;
      cardSum[oa[j]] += r;
      cardSum[ob[j]] += r;
    }
    if (sumOpp == 0) return value;
    if (n.kind == NodeKind.fold) {
      final payoff = (n.winner == t ? total : 0) - invest;
      for (var j = 0; j < h; j++) {
        final s = same[j];
        value[j] = payoff * (sumOpp - cardSum[ta[j]] - cardSum[tb[j]] + (s >= 0 ? reachOpp[s] : 0));
      }
      return value;
    }
    final sd = _showdownFor(n.board);
    final mine = sd.order[t], theirs = sd.order[o];
    final strengthT = sd.strength[t], strengthO = sd.strength[o];
    // Walk both sorted lists: opponent reach strictly below / equal to each hand.
    var below = 0.0;
    final cardBelow = _scratchBelow..fillRange(0, 52, 0);
    final cardEq = _scratchEq;
    var oi = 0;
    var i = 0;
    while (i < mine.length) {
      final s = strengthT[mine[i]];
      while (oi < theirs.length && strengthO[theirs[oi]] < s) {
        final j = theirs[oi];
        final r = reachOpp[j];
        if (r != 0) {
          below += r;
          cardBelow[oa[j]] += r;
          cardBelow[ob[j]] += r;
        }
        oi++;
      }
      // Opponent hands of equal strength.
      var eq = 0.0;
      var oe = oi;
      while (oe < theirs.length && strengthO[theirs[oe]] == s) {
        final j = theirs[oe];
        final r = reachOpp[j];
        if (r != 0) {
          eq += r;
          cardEq[oa[j]] += r;
          cardEq[ob[j]] += r;
        }
        oe++;
      }
      // Every hand of mine at this strength.
      while (i < mine.length && strengthT[mine[i]] == s) {
        final j = mine[i];
        final a = ta[j], b = tb[j];
        final sj = same[j];
        final selfR = sj >= 0 ? reachOpp[sj] : 0.0;
        final win = below - cardBelow[a] - cardBelow[b];
        final tie = eq - cardEq[a] - cardEq[b] + selfR;
        final compatible = sumOpp - cardSum[a] - cardSum[b] + selfR;
        value[j] = total * (win + tie / 2) - invest * compatible;
        i++;
      }
      // Reset the equal-strength card sums we touched.
      for (var x = oi; x < oe; x++) {
        final j = theirs[x];
        cardEq[oa[j]] = 0;
        cardEq[ob[j]] = 0;
      }
    }
    return value;
  }

  _Showdown _showdownFor(List<int> board) {
    var key = 0;
    for (final c in board) {
      key |= 1 << c;
    }
    return _showdowns.putIfAbsent(key, () {
      final st = <Int32List>[], ord = <Int32List>[];
      final cards = List<int>.filled(7, 0);
      for (var i = 0; i < 5; i++) {
        cards[2 + i] = board[i];
      }
      for (var p = 0; p < 2; p++) {
        final hs = _hands[p];
        final s = Int32List(hs.length);
        final idx = <int>[];
        for (var j = 0; j < hs.length; j++) {
          final (a, b) = comboCards[hs[j]];
          if (board.contains(a) || board.contains(b)) {
            s[j] = -1;
            continue;
          }
          cards[0] = a;
          cards[1] = b;
          s[j] = evaluate(cards);
          idx.add(j);
        }
        idx.sort((x, y) => s[x].compareTo(s[y]));
        st.add(s);
        ord.add(Int32List.fromList(idx));
      }
      return _Showdown(st, ord);
    });
  }

  // ---------------------------------------------------------------- values

  /// Values for [t]'s hands at [n] when both players follow the average
  /// strategy, or when [t] best-responds to it ([bestResponse]).
  Float64List _values(SolverNode n, int t, Float64List reachSelf, Float64List reachOpp, bool bestResponse) {
    switch (n.kind) {
      case NodeKind.fold:
      case NodeKind.showdown:
        return _terminal(n, t, reachOpp);
      case NodeKind.chance:
        return _chanceValues(n, t, reachSelf, reachOpp, (c, rs, ro) => _values(c, t, rs, ro, bestResponse));
      case NodeKind.action:
        final a = n.actions.length;
        final sigma = averageStrategy(n);
        if (n.player == t) {
          final h = _hands[t].length;
          final value = Float64List(h);
          if (bestResponse) value.fillRange(0, h, double.negativeInfinity);
          for (var i = 0; i < a; i++) {
            final rs = Float64List(h);
            for (var j = 0; j < h; j++) {
              rs[j] = bestResponse ? reachSelf[j] : reachSelf[j] * sigma[i * h + j];
            }
            final v = _values(n.children[i], t, rs, reachOpp, bestResponse);
            for (var j = 0; j < h; j++) {
              if (bestResponse) {
                if (v[j] > value[j]) value[j] = v[j];
              } else {
                value[j] += sigma[i * h + j] * v[j];
              }
            }
          }
          return value;
        } else {
          final ho = _hands[n.player].length, h = _hands[t].length;
          final value = Float64List(h);
          for (var i = 0; i < a; i++) {
            final ro = Float64List(ho);
            for (var j = 0; j < ho; j++) {
              ro[j] = reachOpp[j] * sigma[i * ho + j];
            }
            final v = _values(n.children[i], t, reachSelf, ro, bestResponse);
            for (var j = 0; j < h; j++) {
              value[j] += v[j];
            }
          }
          return value;
        }
    }
  }

  /// Sum over [t]'s hands of their weight × compatible opponent weight at
  /// the root (normalises values into chips per hand pair).
  double _pairWeight(int t) {
    final o = 1 - t;
    var sumOpp = 0.0;
    final cardSum = Float64List(52);
    for (var j = 0; j < _hands[o].length; j++) {
      final (a, b) = comboCards[_hands[o][j]];
      final w = _weight[o][j];
      sumOpp += w;
      cardSum[a] += w;
      cardSum[b] += w;
    }
    var total = 0.0;
    for (var j = 0; j < _hands[t].length; j++) {
      final (a, b) = comboCards[_hands[t][j]];
      final same = _same[t][j];
      total += _weight[t][j] * (sumOpp - cardSum[a] - cardSum[b] + (same >= 0 ? _weight[o][same] : 0));
    }
    return total;
  }

  /// Expected chips for player [t] (relative to their half of the pot), when
  /// [t] best-responds ([bestResponse]) or plays the average strategy.
  double expectedValue(int t, {bool bestResponse = false}) {
    final v = _values(root, t, Float64List.fromList(_weight[t]), Float64List.fromList(_weight[1 - t]), bestResponse);
    var s = 0.0;
    for (var j = 0; j < v.length; j++) {
      s += _weight[t][j] * v[j];
    }
    return s / _pairWeight(t);
  }

  /// How much a perfect opponent could win against the current average
  /// strategy, as a percentage of the starting pot (0 = unexploitable).
  double exploitability() {
    final br0 = expectedValue(0, bestResponse: true), br1 = expectedValue(1, bestResponse: true);
    return (br0 + br1) / 2 / spot.pot * 100;
  }

  /// Each of [player]'s hands' expected chips at [node] (given how both
  /// players reached it, see [reachAt]), playing the average strategy.
  /// NaN for hands that can't be there.
  Float64List handEv(List<SolverNode> path, int player) {
    final node = path.last;
    final reach = reachAt(path);
    final v = _values(node, player, reach[player], reach[1 - player], false);
    final o = 1 - player;
    var sumOpp = 0.0;
    final cardSum = Float64List(52);
    for (var j = 0; j < _hands[o].length; j++) {
      final r = reach[o][j];
      if (r == 0) continue;
      final (a, b) = comboCards[_hands[o][j]];
      sumOpp += r;
      cardSum[a] += r;
      cardSum[b] += r;
    }
    final out = Float64List(_hands[player].length);
    for (var j = 0; j < out.length; j++) {
      final (a, b) = comboCards[_hands[player][j]];
      final same = _same[player][j];
      final comp = sumOpp - cardSum[a] - cardSum[b] + (same >= 0 ? reach[o][same] : 0);
      out[j] = reach[player][j] > 0 && comp > 0 ? v[j] / comp : double.nan;
    }
    return out;
  }

  /// How likely each player is to hold each hand at the end of [path]
  /// (starting weight × the average strategy's action probabilities, with
  /// hands blocked by dealt cards removed).
  List<Float64List> reachAt(List<SolverNode> path) {
    final reach = [Float64List.fromList(_weight[0]), Float64List.fromList(_weight[1])];
    for (var k = 0; k + 1 < path.length; k++) {
      final n = path[k], next = path[k + 1];
      final i = n.children.indexOf(next);
      if (n.kind == NodeKind.action) {
        final sigma = averageStrategy(n);
        final h = _hands[n.player].length;
        for (var j = 0; j < h; j++) {
          reach[n.player][j] *= sigma[i * h + j];
        }
      } else if (n.kind == NodeKind.chance) {
        final card = n.cards[i];
        for (var p = 0; p < 2; p++) {
          for (final j in _withCard[p][card]) {
            reach[p][j] = 0;
          }
        }
      }
    }
    return reach;
  }
}

class _Showdown {
  _Showdown(this.strength, this.order);

  /// Per player: hand strength (−1 if blocked by the board).
  final List<Int32List> strength;

  /// Per player: unblocked hand indices sorted weakest first.
  final List<Int32List> order;
}

/// Plain-data snapshot of one node, safe to send between isolates.
class SolverNodeView {
  SolverNodeView({
    required this.kind,
    required this.board,
    required this.pot,
    required this.c0,
    required this.c1,
    required this.player,
    required this.actions,
    required this.cards,
    required this.hands,
    required this.strategy,
    required this.reach,
    required this.ev,
    required this.oppReach,
    required this.oppHands,
  });

  final NodeKind kind;
  final List<int> board;

  /// Pot at this node (starting pot plus both players' chips in).
  final int pot;
  final int c0, c1;

  /// Acting player at action nodes (0 = out of position).
  final int player;
  final List<SolverAction> actions;

  /// Chance nodes: the cards that can come.
  final List<int> cards;

  /// The acting player's hands (combo indices), strategy (actions × hands),
  /// how likely they are to hold each hand here, and each hand's EV in chips.
  final Int32List hands;
  final Float64List strategy, reach, ev;

  /// The other player's hands and reach (for showing their range).
  final Int32List oppHands;
  final Float64List oppReach;

  /// Share of the acting range (by reach) taking each action.
  List<double> get actionFrequencies {
    final a = actions.length, h = hands.length;
    final out = List<double>.filled(a, 0);
    var total = 0.0;
    for (var j = 0; j < h; j++) {
      total += reach[j];
      for (var i = 0; i < a; i++) {
        out[i] += reach[j] * strategy[i * h + j];
      }
    }
    return [for (final x in out) total > 0 ? x / total : 0];
  }
}

extension SolverQueries on Solver {
  /// The nodes from the root following child indices [path].
  List<SolverNode> nodesAt(List<int> path) {
    final out = [root];
    for (final i in path) {
      out.add(out.last.children[i]);
    }
    return out;
  }

  /// Everything the UI needs about the node at [path]. For chance nodes the
  /// "acting" player is the out-of-position player.
  SolverNodeView view(List<int> path) {
    final nodes = nodesAt(path);
    final n = nodes.last;
    final p = n.kind == NodeKind.action ? n.player : 0;
    final reach = reachAt(nodes);
    return SolverNodeView(
      kind: n.kind,
      board: n.board,
      pot: spot.pot + n.c0 + n.c1,
      c0: n.c0,
      c1: n.c1,
      player: p,
      actions: n.actions,
      cards: n.cards,
      hands: hands(p),
      strategy: n.kind == NodeKind.action ? averageStrategy(n) : Float64List(0),
      reach: reach[p],
      ev: n.kind == NodeKind.action ? handEv(nodes, p) : Float64List(0),
      oppReach: reach[1 - p],
      oppHands: hands(1 - p),
    );
  }

  /// The solved strategy (average strategy sums of every node), for caching.
  Float32List exportStrategies() {
    final parts = <Float32List>[];
    void walk(SolverNode n) {
      if (n.kind == NodeKind.action) parts.add(n.strategySum);
      n.children.forEach(walk);
    }

    walk(root);
    final out = Float32List(parts.fold(0, (s, p) => s + p.length) + 1);
    out[0] = iterations.toDouble();
    var o = 1;
    for (final p in parts) {
      out.setAll(o, p);
      o += p.length;
    }
    return out;
  }

  /// Loads strategies saved by [exportStrategies] for the same spot.
  /// Returns false if they don't fit this tree.
  bool importStrategies(Float32List data) {
    var o = 1;
    var ok = true;
    void walk(SolverNode n) {
      if (!ok) return;
      if (n.kind == NodeKind.action) {
        final len = n.strategySum.length;
        if (o + len > data.length) {
          ok = false;
          return;
        }
        n.strategySum.setAll(0, Float32List.sublistView(data, o, o + len));
        o += len;
      }
      n.children.forEach(walk);
    }

    walk(root);
    if (!ok || o != data.length) return false;
    iterations = data[0].toInt();
    return true;
  }
}

extension SolverSpotKey on SolverSpot {
  /// Canonical description; equal spots give equal strings (hash it for a
  /// cache key).
  String describe() {
    String sizes(StreetSizes s) => '${s.bet}/${s.raise}/${s.oopBet}';
    String range(WeightedRange r) => [for (var i = 0; i < 1326; i++) if (r.w[i] > 0) '$i:${r.w[i].toStringAsFixed(3)}'].join(',');
    return [
      'v1',
      board.join(','),
      pot,
      stack,
      sizes(flop),
      sizes(turn),
      sizes(river),
      maxBetsPerStreet,
      allInThreshold,
      allInMaxSpr,
      flopTurnCards,
      flopRiverCards,
      range(oop),
      range(ip),
    ].join('|');
  }
}
