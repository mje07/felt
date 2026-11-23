import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../app/controller.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import 'common.dart';
import 'playing_card.dart';

/// Positions of everything on the table for a given size.
class TableGeometry {
  TableGeometry(this.size, this.seatCount, {required this.heroSeat}) {
    final w = size.width, h = size.height;
    felt = Rect.fromCenter(
      center: Offset(w / 2, h * 0.47),
      width: w - 220,
      height: h - 172,
    );
    boardCardWidth = (felt.width * 0.07).clamp(44.0, 72.0);
  }

  double get heroCardWidth => boardCardWidth * 1.05;
  double get botCardWidth => boardCardWidth * 0.66;

  final Size size;
  final int seatCount, heroSeat;
  late final Rect felt;
  late final double boardCardWidth;

  Offset get center => felt.center;

  double _angle(int seat) {
    final k = (seat - heroSeat + seatCount) % seatCount;
    return math.pi / 2 + k * 2 * math.pi / seatCount;
  }

  /// Centre of a seat's nameplate, on the rail.
  Offset seat(int i) {
    final a = _angle(i);
    final rx = felt.width / 2 + 18, ry = felt.height / 2 + 8;
    var p = Offset(center.dx + rx * math.cos(a), center.dy + ry * math.sin(a));
    if (i == heroSeat) p = Offset(center.dx, felt.bottom + 22);
    return p;
  }

  /// Where a seat's bet sits, between the seat and the centre.
  Offset bet(int i) {
    if (i == heroSeat) {
      // To the upper right of the hero's cards.
      return Offset(center.dx + heroCardWidth + 70, felt.bottom - heroCardWidth / cardAspect * 0.55);
    }
    return Offset.lerp(seat(i), center, 0.42)!;
  }

  /// Dealer button position for a seat.
  Offset dealerButton(int i) {
    final a = _angle(i) + 0.32;
    final rx = felt.width / 2 - 34, ry = felt.height / 2 - 30;
    return Offset(center.dx + rx * math.cos(a), center.dy + ry * math.sin(a));
  }

  Offset get pot => center.translate(0, -boardCardWidth / cardAspect * 0.5 - 30);

  Offset resolve(Anchor a) => switch (a) {
        SeatAnchor(:final seat) => this.seat(seat),
        BetAnchor(:final seat) => bet(seat),
        PotAnchor() => pot,
      };
}

class PokerTable extends StatelessWidget {
  const PokerTable({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final g = TableGeometry(constraints.biggest, controller.view.seats.length,
          heroSeat: GameController.heroSeat);
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final v = controller.view;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(rect: g.felt, child: const _Felt()),
              // Board + pot + headline.
              Positioned(
                left: g.center.dx - g.boardCardWidth * 2.5 - 24,
                width: g.boardCardWidth * 5 + 48,
                top: g.center.dy - g.boardCardWidth / cardAspect / 2,
                child: _Board(view: v, cardWidth: g.boardCardWidth),
              ),
              _at(g.pot, _PotLabel(amount: v.pot)),
              Positioned(
                left: 0,
                right: 0,
                top: g.center.dy + g.boardCardWidth / cardAspect / 2 + 14,
                child: Center(child: _Headline(text: v.headline)),
              ),
              if (v.button >= 0) _DealerButton(position: g.dealerButton(v.button)),
              for (final s in v.seats)
                if (s.bet > 0) _at(g.bet(s.index), ChipAmount(amount: s.bet), key: ValueKey('bet${s.index}')),
              for (final s in v.seats)
                _at(
                  g.seat(s.index),
                  s.isHuman
                      ? HeroSeat(seat: s, view: v, cardWidth: g.heroCardWidth)
                      : BotSeat(seat: s, view: v, cardWidth: g.botCardWidth),
                  key: ValueKey('seat${s.index}'),
                ),
              for (final f in controller.flights) _Flight(key: ValueKey(f.id), flight: f, geometry: g),
            ],
          );
        },
      );
    });
  }
}

/// Centres [child] on [p] without knowing its size.
Widget _at(Offset p, Widget child, {Key? key}) => Positioned(
      key: key,
      left: p.dx - 320,
      top: p.dy - 180,
      width: 640,
      height: 360,
      child: Center(child: child),
    );

class _Felt extends StatelessWidget {
  const _Felt();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, c) {
      final radius = BorderRadius.circular(c.maxHeight / 2);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: p.rail,
          boxShadow: [
            BoxShadow(
                color: Color(p.isDark ? 0x99000000 : 0x33000000), blurRadius: 40, offset: const Offset(0, 18)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 1.05,
                colors: [p.feltCenter, p.feltEdge],
              ),
              border: Border.all(color: const Color(0x1FFFFFFF), width: 1),
            ),
            child: Center(
              child: Opacity(
                opacity: 0.14,
                child: Text('FELT',
                    style: TextStyle(
                        fontFamily: Typo.display,
                        fontSize: 15,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFFFFFF))),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.view, required this.cardWidth});
  final TableView view;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final h = cardWidth / cardAspect;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: cardWidth,
              height: h,
              child: i < view.board.length
                  ? DealIn(
                      key: ValueKey('board${view.handNumber}-$i'),
                      from: const Offset(0, -0.4),
                      child: PlayingCard(
                        card: view.board[i],
                        width: cardWidth,
                        dimmed: view.showdownHighlight && !view.highlight.contains(view.board[i]),
                        lifted: view.showdownHighlight && view.highlight.contains(view.board[i]),
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(cardWidth * 0.11),
                        border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

class _PotLabel extends StatelessWidget {
  const _PotLabel({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return AnimatedSwitcher(
      duration: settings.scaled(Motion.fast),
      child: amount > 0
          ? Column(
              key: const ValueKey('pot'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('POT', style: Typo.caption(const Color(0x99FFFFFF)).copyWith(letterSpacing: 1.2)),
                const SizedBox(height: 3),
                ChipAmount(amount: amount, large: true),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return AnimatedSwitcher(
      duration: settings.scaled(Motion.medium),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child),
      ),
      child: text == null
          ? const SizedBox(height: 32)
          : DecoratedBox(
              key: ValueKey(text),
              decoration: BoxDecoration(
                color: const Color(0x66000000),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(text!, style: Typo.headline(const Color(0xFFFFFFFF))),
              ),
            ),
    );
  }
}

class _DealerButton extends StatelessWidget {
  const _DealerButton({required this.position});
  final Offset position;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    const size = 24.0;
    return AnimatedPositioned(
      duration: settings.scaled(Motion.slow),
      curve: Motion.spring,
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFFFFFFF),
          boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 1.5))],
        ),
        alignment: Alignment.center,
        child: Text('D',
            style: TextStyle(
                fontFamily: Typo.display, fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1D1D1F))),
      ),
    );
  }
}

/// A chip stack gliding between two anchors along a slight arc.
class _Flight extends StatelessWidget {
  const _Flight({super.key, required this.flight, required this.geometry});
  final ChipFlight flight;
  final TableGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final from = geometry.resolve(flight.from), to = geometry.resolve(flight.to);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: flight.duration,
      curve: Curves.easeInOutCubic,
      builder: (context, t, child) {
        final lift = math.sin(t * math.pi) * 18;
        final p = Offset.lerp(from, to, t)!.translate(0, -lift);
        return Positioned(
          left: p.dx - 10,
          top: p.dy - 10,
          child: Opacity(opacity: t < 0.85 ? 1 : (1 - t) / 0.15, child: child),
        );
      },
      child: IgnorePointer(
        child: SizedBox(
          width: 20,
          height: 26,
          child: Stack(children: [
            for (var i = 0; i < 3; i++)
              Positioned(top: 6.0 - i * 3, child: ChipDisc(amount: flight.amount, size: 20)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- seats

class _ActionTag extends StatelessWidget {
  const _ActionTag({required this.text, this.winner = false});
  final String? text;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = SettingsScope.of(context);
    return AnimatedSwitcher(
      duration: settings.scaled(Motion.fast),
      transitionBuilder: (c, a) => FadeTransition(
          opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: c)),
      child: text == null
          ? const SizedBox(height: 22, key: ValueKey('none'))
          : DecoratedBox(
              key: ValueKey(text),
              decoration: BoxDecoration(
                color: winner ? p.positive : (text == 'All-in' ? p.destructive : const Color(0xF2FFFFFF)),
                borderRadius: BorderRadius.circular(Radii.pill),
                boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(text!,
                    style: Typo.caption(winner || text == 'All-in' ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F))
                        .copyWith(fontWeight: FontWeight.w600, fontSize: 11.5)),
              ),
            ),
    );
  }
}

class _Nameplate extends StatelessWidget {
  const _Nameplate({required this.seat, required this.active, this.subtitle});
  final SeatView seat;
  final bool active;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GlassPanel(
      radius: Radii.pill,
      padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(name: seat.name, size: 38, ring: active ? p.accent : (seat.winner ? p.positive : null)),
          const SizedBox(width: 8),
          Flexible(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: seat.name, style: Typo.callout(p.label).copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  TextSpan(text: '  $subtitle', style: Typo.caption(p.tertiaryLabel)),
              ]), maxLines: 1, overflow: TextOverflow.ellipsis),
              AnimatedCount(value: seat.stack, style: Typo.number(p.secondaryLabel, size: 12.5)),
            ],
          )),
        ],
      ),
    );
  }
}

const _plateH = 48.0;

class BotSeat extends StatelessWidget {
  const BotSeat({super.key, required this.seat, required this.view, required this.cardWidth});
  final SeatView seat;
  final TableView view;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    if (!seat.inHand && seat.stack == 0) return const SizedBox.shrink();
    final active = view.toAct == seat.index;
    final showCards = seat.inHand && !seat.folded && seat.cardsDealt > 0;
    // The nameplate is centred on the seat anchor; cards peek out above it
    // and the action tag hangs below.
    return AnimatedOpacity(
      opacity: seat.folded || !seat.inHand ? 0.45 : 1,
      duration: settings.scaled(Motion.medium),
      child: SizedBox(
        width: 250,
        height: _plateH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (showCards)
              Positioned(
                left: 0,
                right: 0,
                bottom: _plateH - 14,
                child: Center(
                  child: SizedBox(
                    height: cardWidth / cardAspect,
                    width: cardWidth * 1.72,
                    child: Stack(children: [
                      for (var i = 0; i < seat.cardsDealt.clamp(0, 2); i++)
                        Positioned(
                          left: i * cardWidth * 0.72,
                          child: Transform.rotate(
                            angle: (i == 0 ? -1 : 1) * 0.06,
                            child: DealIn(
                              key: ValueKey('c${view.handNumber}-${seat.index}-$i'),
                              from: const Offset(0, 0.5),
                              child: PlayingCard(
                                card: seat.hole.length > i ? seat.hole[i] : null,
                                width: cardWidth,
                                faceUp: seat.revealed,
                                dimmed: view.showdownHighlight &&
                                    seat.revealed &&
                                    !view.highlight.contains(seat.hole[i]),
                                lifted: view.showdownHighlight && view.highlight.contains(seat.hole[i]),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            Center(child: _Nameplate(seat: seat, active: active, subtitle: seat.style)),
            Positioned(
              left: -70,
              right: -70,
              top: _plateH + 4,
              child: Center(
                child: _ActionTag(
                  text: seat.revealed && seat.handLabel != null ? seat.handLabel : seat.label,
                  winner: seat.winner,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HeroSeat extends StatelessWidget {
  const HeroSeat({super.key, required this.seat, required this.view, required this.cardWidth});
  final SeatView seat;
  final TableView view;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final active = view.toAct == seat.index;
    final cardH = cardWidth / cardAspect;
    return SizedBox(
      width: 560,
      height: _plateH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (seat.cardsDealt > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: _plateH + 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < seat.cardsDealt.clamp(0, 2); i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: DealIn(
                        key: ValueKey('h${view.handNumber}-$i'),
                        from: const Offset(0, -1.2),
                        child: PlayingCard(
                          card: seat.hole[i],
                          width: cardWidth,
                          dimmed: seat.folded ||
                              (view.showdownHighlight && !view.highlight.contains(seat.hole[i])),
                          lifted: view.showdownHighlight && view.highlight.contains(seat.hole[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _plateH + 12 + cardH,
            child: Center(child: _ActionTag(text: seat.label, winner: seat.winner)),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Nameplate(seat: seat, active: active),
                if (seat.handLabel != null && !seat.folded && seat.inHand) ...[
                  const SizedBox(width: 10),
                  GlassPanel(
                    radius: Radii.pill,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text(seat.handLabel!, style: Typo.callout(p.label)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
