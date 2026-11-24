part of 'controller.dart';

/// Home games: the client side mirrors the host's hands with the real rules
/// engine, so the table, animations and coach work exactly as offline.
extension _HomeGame on GameController {
  /// A friend's table: seats are filled in by the host's hand messages.
  void _setupClient() {
    final c = client!;
    final n = c.settings.seats;
    _players = [for (var i = 0; i < n; i++) TablePlayer(name: '', stack: 0, isHuman: i == GameController.heroSeat)];
    view = TableView([
      for (var i = 0; i < n; i++) SeatView(index: i, name: '', isHuman: i == GameController.heroSeat, style: ''),
    ]);
  }

  void _sendHostStatus() {
    final h = host;
    if (h == null) return;
    final t = tournament;
    if (t != null) {
      h.sendStatus(tournamentTitle, tournamentStatus, t.prizePool);
    } else {
      final players = _players.where((p) => p.name.isNotEmpty).length;
      h.sendStatus('${h.settings.name} · ${formatChips(config.smallBlind)}/${formatChips(config.bigBlind)}',
          '$players players · play chips', 0);
    }
  }

  /// Seat in our mirror (we are always seat 0) for a seat at the host.
  int _mirrorSeat(int hostSeat) {
    final n = client!.settings.seats;
    return (hostSeat - client!.seat + n) % n;
  }

  Future<void> _clientLoop() async {
    final c = client!;
    HandState? s;
    Future<DecisionAnalysis>? analysis;
    int? turnHand;
    var handOverSaved = true;

    Future<void> finishHand(HandState done) async {
      if (handOverSaved) return;
      handOverSaved = true;
      lastHandReviews = List.unmodifiable(_handReviews);
      reads.observe(done);
      unawaited(history.add(HandHistory.fromState(
        done,
        heroSeat: GameController.heroSeat,
        reviews: lastHandReviews,
        mode: c.settings.tournament ? 'sng' : 'cash',
      )));
      _checkAchievementsSoon();
      handOver = true;
      _notify();
    }

    await for (final m in c.gameMessages) {
      if (_disposed) return;
      switch (m['t']) {
        case 'hand':
          handOver = false;
          handOverSaved = false;
          _handReviews.clear();
          lastHandReviews = const [];
          final seats = (m['seats'] as List).cast<List<Object?>?>();
          final n = seats.length;
          final mine = c.seat;
          int rot(int i) => i < 0 ? i : (i - mine + n) % n;
          final players = <SeatSetup?>[for (var i = 0; i < n; i++) null];
          for (var i = 0; i < n; i++) {
            final seat = seats[i];
            if (seat != null) players[rot(i)] = SeatSetup(seat[0]! as String, seat[1]! as int);
          }
          for (var i = 0; i < n; i++) {
            _players[i] = TablePlayer(name: players[i]?.name ?? '', stack: players[i]?.stack ?? 0, isHuman: i == 0);
            view.seats[i]
              ..name = players[i]?.name ?? ''
              ..outPlace = view.seats[i].name == (players[i]?.name ?? '') ? view.seats[i].outPlace : null;
          }
          final button = rot(m['button'] as int), sb = rot(m['sbSeat'] as int), bb = rot(m['bbSeat'] as int);
          // Our cards go where the deal order puts them; other cards are
          // placeholders until revealed.
          final hole = (m['hole'] as List).cast<int>();
          final dealtIn = [for (var i = 0; i < n; i++) if (players[i] != null) i];
          final first = sb >= 0 ? sb : dealtIn.firstWhere((i) => i > button, orElse: () => dealtIn.first);
          final order = [
            for (var k = 0; k < n; k++)
              if (players[(first + k) % n] != null) (first + k) % n,
          ];
          final spare = [for (var card = 0; card < 52; card++) if (!hole.contains(card)) card];
          final deck = List<int>.from(spare.take(52 - hole.length))..addAll(hole);
          final mePos = order.indexOf(0);
          if (hole.length == 2 && mePos >= 0) {
            void put(int pos, int card) {
              final at = deck.indexOf(card);
              deck[at] = deck[pos];
              deck[pos] = card;
            }

            put(mePos, hole[0]);
            put(order.length + mePos, hole[1]);
          }
          s = startHand(
            players: players,
            button: button,
            smallBlindSeat: sb,
            bigBlindSeat: bb,
            smallBlind: m['sb'] as int,
            bigBlind: m['bb'] as int,
            ante: m['ante'] as int? ?? 0,
            anteFromEveryone: m['anteAll'] as bool? ?? false,
            handNumber: m['n'] as int,
            deck: deck,
          );
          _state = s;
          await _play(s, s.log);
        case 'act':
          final before = s;
          if (before == null || m['n'] != before.handNumber || before.isComplete) continue;
          // Fill in what this action reveals before the engine deals it.
          final board = ((m['board'] as List?) ?? const []).cast<int>();
          var pos = before.deckPos, len = before.board.length;
          var k = 0;
          while (k < board.length) {
            pos++; // burn
            final count = len == 0 ? 3 : 1;
            for (var j = 0; j < count && k < board.length; j++) {
              _swapInto(before.deck, pos++, board[k++]);
            }
            len += count;
          }
          final show = (m['show'] as Map?)?.cast<String, Object?>();
          if (show != null) {
            for (final e in show.entries) {
              final seat = _mirrorSeat(int.parse(e.key));
              if (seat != 0) before.seats[seat].hole = (e.value! as List).cast<int>();
            }
          }
          final action = PlayerAction(ActionType.values.byName(m['type'] as String), m['amount'] as int? ?? 0);
          // Our own action echoes back: grade it now (or it timed out).
          if (before.toAct == GameController.heroSeat && turnHand == before.handNumber) {
            if (_heroTurn != null && !_heroTurn!.isCompleted) {
              heroLegal = null;
              _heroTurn = null;
            }
            final a = analysis;
            if (a != null) {
              try {
                final review = gradeDecision(await a, action);
                if (review != null) {
                  _handReviews.add(review);
                  sessionReviews.add(review);
                  SkillRatings.current.recordReview(review);
                  view.seats[GameController.heroSeat].grade = review.grade;
                }
              } catch (_) {}
            }
            analysis = null;
            turnHand = null;
          }
          HandState next;
          try {
            next = applyAction(before, action);
          } catch (e) {
            debugPrint('Home game out of sync: $e');
            continue;
          }
          view.toAct = -1;
          _state = next;
          await _play(next, next.log.sublist(before.log.length));
          s = next;
          if (next.isComplete) {
            await finishHand(next);
          } else {
            view.toAct = next.toAct;
            _notify();
          }
        case 'turn':
          final now = s;
          if (now == null || m['n'] != now.handNumber || now.toAct != GameController.heroSeat) continue;
          turnHand = now.handNumber;
          analysis = _analyze(now);
          view.toAct = GameController.heroSeat;
          // Don't block the message loop: our action goes to the host, and
          // comes back as an 'act' like everyone else's.
          unawaited(_askHero(now).then((a) {
            if (!_disposed && turnHand == now.handNumber) c.act(now.handNumber, a.type.name, a.amount);
          }));
        case 'status':
          remoteTitle = m['title'] as String?;
          remoteStatus = m['status'] as String?;
          remotePool = m['pool'] as int? ?? 0;
          _notify();
        case 'out':
          final seat = _mirrorSeat(m['seat'] as int), place = m['place'] as int;
          if (place > 1) {
            view.seats[seat]
              ..outPlace = place
              ..label = ordinal(place);
          }
          if (seat == GameController.heroSeat || place == 1) {
            final players = c.settings.seats;
            if (seat == GameController.heroSeat) {
              outcome = TournamentOutcome(place: place, players: players, prize: 0, buyIn: 0, winnerName: '');
            } else if (outcome != null) {
              outcome = TournamentOutcome(
                  place: outcome!.place, players: players, prize: 0, buyIn: 0, winnerName: view.seats[seat].name);
            }
          }
          _notify();
        case 'end':
          remoteEnded = m['reason'] as String? ?? 'The game is over.';
          handOver = true;
          heroLegal = null;
          _notify();
          return;
      }
    }
  }
}

/// Puts [card] at [pos], moving whatever was there to [card]'s old place.
void _swapInto(List<int> deck, int pos, int card) {
  final at = deck.indexOf(card);
  if (at < 0 || pos >= deck.length) return;
  deck[at] = deck[pos];
  deck[pos] = card;
}
