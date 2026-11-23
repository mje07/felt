import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LedgerKind { start, buyIn, rebuy, cashOut, prize, topUp, reset }

class LedgerEntry {
  const LedgerEntry(this.at, this.kind, this.amount, this.balance, [this.note = '']);

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        DateTime.parse(j['at'] as String),
        LedgerKind.values.byName(j['k'] as String),
        j['a'] as int,
        j['b'] as int,
        (j['n'] as String?) ?? '',
      );

  final DateTime at;
  final LedgerKind kind;

  /// Signed change to the balance.
  final int amount;

  /// Balance after this entry.
  final int balance;
  final String note;

  Map<String, Object> toJson() =>
      {'at': at.toIso8601String(), 'k': kind.name, 'a': amount, 'b': balance, if (note.isNotEmpty) 'n': note};
}

/// The player's chip bankroll, shared by cash games and Sit & Gos.
///
/// Chips sitting on a cash table are tracked as [inPlay] after every hand, so
/// if the app closes mid-session they are returned on the next launch.
class Bankroll extends ChangeNotifier {
  Bankroll._(this._prefs);

  static const startingBalance = 10000;
  static const _keep = 400;

  /// The app-wide instance (replaced at startup by [load]).
  static Bankroll current = Bankroll._(null)..balance = startingBalance;

  final SharedPreferences? _prefs;
  int balance = startingBalance;
  int inPlay = 0;
  final List<LedgerEntry> ledger = [];

  /// In-memory bankroll for tests.
  factory Bankroll.memory([int balance = startingBalance]) => Bankroll._(null)..balance = balance;

  static Future<Bankroll> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final b = Bankroll._(prefs);
    final raw = prefs?.getString('bankroll');
    if (raw == null) {
      b._add(LedgerKind.start, startingBalance, 'Starting bankroll', setBalance: true);
    } else {
      try {
        final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
        b.balance = j['balance'] as int;
        b.inPlay = (j['inPlay'] as int?) ?? 0;
        for (final e in (j['ledger'] as List? ?? const [])) {
          b.ledger.add(LedgerEntry.fromJson((e as Map).cast<String, dynamic>()));
        }
      } catch (_) {
        b.balance = startingBalance;
      }
      // Chips left on a cash table when the app last closed.
      if (b.inPlay > 0) b.cashOut(b.inPlay, note: 'Recovered from last session');
    }
    return current = b;
  }

  bool canAfford(int amount) => balance >= amount;

  void _add(LedgerKind kind, int amount, String note, {bool setBalance = false}) {
    balance = setBalance ? amount : balance + amount;
    ledger.add(LedgerEntry(DateTime.now(), kind, amount, balance, note));
    if (ledger.length > _keep) ledger.removeAt(0);
    _save();
    notifyListeners();
  }

  void _save() {
    _prefs?.setString(
        'bankroll',
        jsonEncode({
          'balance': balance,
          'inPlay': inPlay,
          'ledger': [for (final e in ledger) e.toJson()],
        }));
  }

  /// Takes a buy-in (cash table or tournament). Returns false if short.
  bool debit(int amount, {LedgerKind kind = LedgerKind.buyIn, String note = ''}) {
    if (amount <= 0) return true;
    if (!canAfford(amount)) return false;
    _add(kind, -amount, note);
    return true;
  }

  void credit(int amount, {LedgerKind kind = LedgerKind.prize, String note = ''}) {
    if (amount <= 0) return;
    _add(kind, amount, note);
  }

  /// Records chips currently on a cash table (saved after every hand).
  void setInPlay(int chips) {
    inPlay = chips;
    _save();
  }

  void cashOut(int chips, {String note = 'Cash game'}) {
    inPlay = 0;
    if (chips > 0) {
      _add(LedgerKind.cashOut, chips, note);
    } else {
      _save();
      notifyListeners();
    }
  }

  /// Free top-up back to the starting balance when broke.
  void topUp() {
    if (balance >= startingBalance) return;
    _add(LedgerKind.topUp, startingBalance - balance, 'Top-up');
  }

  void reset() {
    ledger.clear();
    inPlay = 0;
    _add(LedgerKind.reset, startingBalance, 'Bankroll reset', setBalance: true);
  }
}
