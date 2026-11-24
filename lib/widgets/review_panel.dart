import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/theme.dart';

/// Status colours (reserved for state, never series) plus an icon, so a grade
/// never relies on colour alone.
(Color, IconData) gradeStyle(Grade g, Palette p) => switch (g) {
      Grade.best => (const Color(0xFF0CA30C), CupertinoIcons.star_fill),
      Grade.good => (p.secondaryLabel, CupertinoIcons.checkmark_alt_circle_fill),
      Grade.inaccuracy => (const Color(0xFFE0A000), CupertinoIcons.exclamationmark_circle_fill),
      Grade.mistake => (const Color(0xFFEC835A), CupertinoIcons.question_circle_fill),
      Grade.blunder => (const Color(0xFFD03B3B), CupertinoIcons.xmark_octagon_fill),
    };

class GradeBadge extends StatelessWidget {
  const GradeBadge({super.key, required this.grade, this.compact = false});
  final Grade grade;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (color, icon) = gradeStyle(grade, p);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? 0.22 : 0.13),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: compact ? 12 : 14, color: color),
        const SizedBox(width: 4),
        Text(grade.label,
            style: Typo.caption(p.label).copyWith(fontWeight: FontWeight.w600, fontSize: compact ? 11 : 12)),
      ]),
    );
  }
}

/// "Accuracy 82% · 1 mistake" summary for a hand's reviews.
String reviewSummary(List<DecisionReview> reviews) {
  final acc = accuracyOf(reviews);
  if (acc == null) return 'No graded decisions';
  final bad = <Grade, int>{};
  for (final r in reviews) {
    if (r.grade.index >= Grade.inaccuracy.index) bad[r.grade] = (bad[r.grade] ?? 0) + 1;
  }
  if (bad.isEmpty) return 'Accuracy ${acc.round()}%';
  final worst = bad.keys.reduce((a, b) => a.index > b.index ? a : b);
  final n = bad[worst]!;
  final noun = switch (worst) {
    Grade.inaccuracy => n == 1 ? 'inaccuracy' : 'inaccuracies',
    _ => n == 1 ? worst.label.toLowerCase() : '${worst.label.toLowerCase()}s',
  };
  return 'Accuracy ${acc.round()}% · $n $noun';
}

/// Decisions of one hand, grouped by street.
class HandReviewList extends StatelessWidget {
  const HandReviewList({super.key, required this.reviews, this.hole});
  final List<DecisionReview> reviews;
  final List<int>? hole;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (reviews.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Text('No decisions were graded in this hand.', style: Typo.body(p.secondaryLabel)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, r) in reviews.indexed) ...[
          if (i > 0) Container(height: 0.5, color: p.separator, margin: const EdgeInsets.symmetric(vertical: 12)),
          _ReviewRow(review: r),
        ],
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review});
  final DecisionReview review;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = review;
    final street = '${r.street.name[0].toUpperCase()}${r.street.name.substring(1)}';
    final agreed = r.grade == Grade.best || r.taken == r.recommended || (r.bySolver && r.grade == Grade.good);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(street.toUpperCase(), style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 0.8)),
          const SizedBox(width: Space.s),
          GradeBadge(grade: r.grade, compact: true),
          if (r.bySolver) ...[
            const SizedBox(width: 6),
            _SolverTag(color: p.accent),
          ],
          const Spacer(),
          if (r.lossBb != null && r.lossBb! >= 0.5)
            Text('−${r.lossBb!.toStringAsFixed(1)} bb', style: Typo.number(p.secondaryLabel, size: 12)),
        ]),
        const SizedBox(height: 6),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'You: ', style: Typo.callout(p.secondaryLabel)),
          TextSpan(text: r.taken, style: Typo.callout(p.label).copyWith(fontWeight: FontWeight.w600)),
          if (!agreed) ...[
            TextSpan(text: r.bySolver ? '   Solver: ' : '   Coach: ', style: Typo.callout(p.secondaryLabel)),
            TextSpan(text: r.recommended, style: Typo.callout(p.accent).copyWith(fontWeight: FontWeight.w600)),
          ],
        ])),
        const SizedBox(height: 4),
        Text(r.explanation, style: Typo.body(p.secondaryLabel).copyWith(height: 1.4)),
        if (r.equity != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: Space.m, children: [
            _Fact('Equity', '${(r.equity! * 100).round()}%'),
            if (r.requiredEquity != null) _Fact('Needed', '${(r.requiredEquity! * 100).round()}%'),
          ]),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Text.rich(TextSpan(children: [
      TextSpan(text: '$label ', style: Typo.caption(p.tertiaryLabel)),
      TextSpan(text: value, style: Typo.number(p.label, size: 12)),
    ]));
  }
}

/// Marks a decision graded against an exact solve rather than the equity model.
class _SolverTag extends StatelessWidget {
  const _SolverTag({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Graded against a game-theory solve of this exact spot',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.scope, size: 11, color: color),
            const SizedBox(width: 3),
            Text('Solver', style: Typo.caption(color).copyWith(fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
