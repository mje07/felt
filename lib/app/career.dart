import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bankroll.dart';
import 'skills.dart';

/// One rung of the career ladder: what you may play, and what it takes to
/// move up.
class CareerStage {
  const CareerStage({
    required this.name,
    required this.blurb,
    required this.maxStake,
    required this.maxSngBuyIn,
    required this.events,
    this.promoteAt,
    this.minRating = 0,
  });

  final String name, blurb;

  /// Highest cash stake allowed (index into the lobby's stakes: 0 = 1/2).
  final int maxStake;
  final int maxSngBuyIn;

  /// Tournament events open at this stage (by name).
  final List<String> events;

  /// Bankroll needed to be promoted (null at the top).
  final int? promoteAt;

  /// Average skill rating needed to be promoted.
  final double minRating;
}

const careerStages = [
  CareerStage(
    name: 'Rookie',
    blurb: 'Micro stakes. Build a bankroll and learn the basics.',
    maxStake: 0,
    maxSngBuyIn: 500,
    events: ['Daily Freeroll', 'Nightly 500'],
    promoteAt: 10000,
    minRating: 1250,
  ),
  CareerStage(
    name: 'Regular',
    blurb: 'Small stakes and your first real tournaments.',
    maxStake: 1,
    maxSngBuyIn: 2500,
    events: ['Daily Freeroll', 'Nightly 500', 'Turbo 2K'],
    promoteAt: 50000,
    minRating: 1300,
  ),
  CareerStage(
    name: 'Grinder',
    blurb: 'Mid stakes and the Sunday Million.',
    maxStake: 2,
    maxSngBuyIn: 10000,
    events: ['Nightly 500', 'Turbo 2K', 'Sunday Million'],
    promoteAt: 250000,
    minRating: 1350,
  ),
  CareerStage(
    name: 'Pro',
    blurb: 'High stakes and the high rollers.',
    maxStake: 3,
    maxSngBuyIn: 100000,
    events: ['Turbo 2K', 'Sunday Million', 'High Roller', 'Super High Roller'],
    promoteAt: 2000000,
    minRating: 1400,
  ),
  CareerStage(
    name: 'High Roller',
    blurb: 'Nosebleed Sit & Gos and the Main Event.',
    maxStake: 3,
    maxSngBuyIn: 1000000,
    events: ['Sunday Million', 'High Roller', 'Super High Roller', 'Main Event'],
    promoteAt: 20000000,
    minRating: 1450,
  ),
  CareerStage(
    name: 'Legend',
    blurb: 'Everything is open. Win The Big One.',
    maxStake: 3,
    maxSngBuyIn: 1000000,
    events: ['Super High Roller', 'Main Event', 'The Big One'],
  ),
];

/// Career mode: climb from micro stakes to The Big One with a separate
/// bankroll. Promotion needs both chips and skill.
class Career extends ChangeNotifier {
  Career._(this._prefs);

  static const startingBankroll = 2000;

  static Career current = Career._(null);
  factory Career.memory() => Career._(null);

  static Future<Career> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final c = Career._(prefs);
    final raw = prefs?.getString('career');
    if (raw != null) {
      try {
        final j = (jsonDecode(raw) as Map).cast<String, Object?>();
        c.stage = ((j['stage'] as int?) ?? 0).clamp(0, careerStages.length - 1);
        c.started = (j['started'] as bool?) ?? false;
        c.champion = (j['champion'] as bool?) ?? false;
      } catch (_) {}
    }
    return current = c;
  }

  final SharedPreferences? _prefs;
  int stage = 0;
  bool started = false;

  /// Won The Big One in career mode.
  bool champion = false;

  CareerStage get stageInfo => careerStages[stage];
  CareerStage? get next => stage + 1 < careerStages.length ? careerStages[stage + 1] : null;

  bool allowsStake(int index) => index <= stageInfo.maxStake;
  bool allowsSng(int buyIn) => buyIn <= stageInfo.maxSngBuyIn;
  bool allowsEvent(String name) => stageInfo.events.contains(name);

  /// What's still needed for promotion (empty when ready, null at the top).
  List<String>? missingFor({required Bankroll bankroll, required SkillRatings ratings}) {
    final need = stageInfo.promoteAt;
    if (need == null) return null;
    return [
      if (bankroll.balance < need) 'Bankroll ${_chips(need)}',
      if (ratings.average < stageInfo.minRating) 'Average skill ${stageInfo.minRating.round()}',
    ];
  }

  bool canPromote({required Bankroll bankroll, required SkillRatings ratings}) =>
      missingFor(bankroll: bankroll, ratings: ratings)?.isEmpty ?? false;

  void start() {
    started = true;
    _save();
    notifyListeners();
  }

  void promote() {
    if (next == null) return;
    stage++;
    _save();
    notifyListeners();
  }

  void crown() {
    champion = true;
    _save();
    notifyListeners();
  }

  /// Back to Rookie with a fresh career bankroll.
  void restart(Bankroll careerBankroll) {
    stage = 0;
    champion = false;
    careerBankroll.reset();
    _save();
    notifyListeners();
  }

  void _save() => _prefs?.setString('career', jsonEncode({'stage': stage, 'started': started, 'champion': champion}));
}

String _chips(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
