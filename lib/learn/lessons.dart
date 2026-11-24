import 'package:poker_engine/poker_engine.dart';

/// What a lesson, drill or decision trains. Each has its own rating.
enum Skill {
  maths('Poker maths', 'Pot odds, outs and equity'),
  preflop('Preflop', 'Opening, 3-betting and defending'),
  postflop('Flop & turn', 'C-bets, board texture and draws'),
  river('River play', 'Value bets, bluffs and bluff-catching'),
  pushFold('Short stacks', 'Shove-or-fold tournament play'),
  icm('Tournament pressure', 'ICM, bubbles and final tables'),
  reading('Reading players', 'Stats, styles and exploits');

  const Skill(this.label, this.blurb);
  final String label, blurb;
}

/// An illustration made from real cards and ranges.
class LessonFigure {
  const LessonFigure({this.hole, this.board, this.range, this.caption});

  /// Card text such as "Ah Kd"; range notation such as "22+, AJs+".
  final String? hole, board, range, caption;
  List<int> get holeCards => hole == null ? const [] : parseCards(hole!);
  List<int> get boardCards => board == null ? const [] : parseCards(board!);
}

class LessonPage {
  const LessonPage(this.title, this.body, {this.figure});
  final String title;
  final List<String> body;
  final LessonFigure? figure;
}

/// A multiple-choice check. Exactly one option is right.
class LessonCheck {
  const LessonCheck(this.question, this.options, this.answer, this.why, {this.figure});
  final String question;
  final List<String> options;
  final int answer;
  final String why;
  final LessonFigure? figure;
}

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.summary,
    required this.skill,
    required this.pages,
    required this.checks,
    this.drill,
    this.trainerStreet,
  });

  final String id, title, summary;
  final Skill skill;
  final List<LessonPage> pages;
  final List<LessonCheck> checks;

  /// Where to practise afterwards: a drill, or the Spot Trainer on a street
  /// ('flop', 'turn' or 'river').
  final DrillKind? drill;
  final String? trainerStreet;

  int get minutes => 2 + pages.length + checks.length;
}

class Unit {
  const Unit(this.title, this.blurb, this.lessons);
  final String title, blurb;
  final List<Lesson> lessons;
}

const course = [
  Unit('Fundamentals', 'The rules of value: hands, position and the maths of calling.', [
    Lesson(
      id: 'hand-ranks',
      title: 'Hand rankings',
      summary: 'What beats what, and why kickers matter.',
      skill: Skill.maths,
      drill: DrillKind.showdown,
      pages: [
        LessonPage('The ladder', [
          'From strongest to weakest: straight flush, four of a kind, full house, flush, straight, three of a kind, two pair, one pair, high card.',
          'Your hand is always the best five cards from your two hole cards and the five on the board. You can use both, one or neither of your hole cards.',
        ]),
        LessonPage('Kickers decide ties', [
          'When two players make the same pair, the next-highest cards (kickers) decide it, one by one, until one is higher.',
          'If the best five cards are identical, the pot is split. When the board itself is the best hand, everyone still in "plays the board".',
        ], figure: LessonFigure(board: 'Ks Kd 7c 2h 3s', caption: 'A paired board: kickers will decide most showdowns.')),
      ],
      checks: [
        LessonCheck('Which hand wins: a flush or a straight?', ['The straight', 'The flush', 'It\'s a split'], 1,
            'A flush ranks above a straight. Five cards of one suit are rarer than five in a row.'),
        LessonCheck('The board is K♠ K♦ 7♣ 2♥ 3♠. Who wins: A♥ Q♥ or A♣ 9♦?', ['A♥ Q♥', 'A♣ 9♦', 'Split pot'], 0,
            'Both have kings with an ace kicker. The next kicker decides it: queen beats nine, so A-Q wins.',
            figure: LessonFigure(board: 'Ks Kd 7c 2h 3s')),
        LessonCheck('Which is stronger: a full house or four of a kind?', ['Full house', 'Four of a kind'], 1,
            'Four of a kind beats a full house. Only a straight flush beats quads.'),
      ],
    ),
    Lesson(
      id: 'position',
      title: 'Position',
      summary: 'Why acting last is worth so much.',
      skill: Skill.preflop,
      drill: DrillKind.preflop,
      pages: [
        LessonPage('Who acts when', [
          'Preflop, action starts left of the big blind (under the gun, UTG) and ends with the blinds. After the flop, the player closest to the left of the button acts first and the button acts last.',
          'At six-handed tables the seats are UTG, HJ (hijack), CO (cutoff), BTN (button), SB and BB.',
        ]),
        LessonPage('Why last is best', [
          'Acting last means you see what everyone did before you decide: you can bet when they check weakly, take free cards, and control the size of the pot.',
          'So you can play more hands in late position and fewer in early position, where several players still act after you and any of them may have a big hand.',
        ]),
      ],
      checks: [
        LessonCheck('After the flop, who acts last?', ['The big blind', 'The button', 'Under the gun'], 1,
            'The button acts last on every street after the flop. That\'s why it\'s the most profitable seat.'),
        LessonCheck('Why should you play fewer hands from early position?', [
          'The blinds are bigger there',
          'More players act after you, so someone is more likely to hold a strong hand',
          'You can\'t raise from early position',
        ], 1, 'With more players behind, your hand needs to be stronger to be ahead, and you\'ll often play the pot out of position.'),
        LessonCheck('Six-handed, which seat is directly to the right of the button?', ['Cutoff', 'Hijack', 'Small blind'], 0,
            'The order is UTG, HJ, CO, BTN, SB, BB. The cutoff sits just before the button.'),
      ],
    ),
    Lesson(
      id: 'pot-odds',
      title: 'Pot odds',
      summary: 'How much equity a call needs.',
      skill: Skill.maths,
      drill: DrillKind.potOdds,
      pages: [
        LessonPage('The formula', [
          'To call, you need at least: call ÷ (pot after your call). That\'s the share of the final pot you\'re paying for.',
          'Example: the pot is 100 and your opponent bets 50. You call 50 into a pot that becomes 200, so you need 50 ÷ 200 = 25% equity.',
        ]),
        LessonPage('Bet sizes you\'ll see', [
          'Third pot: you need 20%. Half pot: 25%. Two-thirds pot: about 29%. Pot: 33%. Twice the pot: 40%.',
          'Bigger bets need more equity to call, which is why big bets make draws fold.',
        ]),
      ],
      checks: [
        LessonCheck('The pot is 60 and your opponent bets 30. What equity do you need to call?', ['20%', '25%', '33%'], 1,
            'You call 30 and the pot becomes 60 + 30 + 30 = 120. 30 ÷ 120 = 25%.'),
        LessonCheck('Your opponent bets the size of the pot. What equity do you need?', ['25%', '33%', '50%'], 1,
            'Call 1 to win a pot that becomes 3: 1 ÷ 3 = 33%.'),
        LessonCheck('You have 30% equity and face a half-pot bet. Call or fold?', ['Call', 'Fold'], 0,
            'A half-pot bet needs 25%. With 30% you\'re getting the right price to call.'),
      ],
    ),
    Lesson(
      id: 'outs',
      title: 'Outs and the rule of 2 and 4',
      summary: 'Turning draws into percentages.',
      skill: Skill.maths,
      drill: DrillKind.outs,
      pages: [
        LessonPage('Counting outs', [
          'Outs are the unseen cards that make your hand. A flush draw has 9 (13 of a suit minus the 4 you can see). An open-ended straight draw has 8. A gutshot has 4.',
          'A flush draw plus an open-ender has 15 outs: 9 + 8, minus the 2 cards counted twice.',
        ], figure: LessonFigure(hole: 'Jh Th', board: '9h 8h 2c', caption: 'J♥ T♥ on 9♥ 8♥ 2♣: a flush draw and an open-ender, 15 outs.')),
        LessonPage('Quick percentages', [
          'On the flop, with two cards to come, multiply your outs by 4. On the turn, with one card to come, multiply by 2.',
          'So 9 outs is about 36% from the flop (exactly 35%) and about 18% from the turn (exactly 19.6%).',
        ]),
      ],
      checks: [
        LessonCheck('How many outs does a flush draw have?', ['8', '9', '12'], 1,
            'Thirteen cards of the suit, minus the four you can already see: nine.'),
        LessonCheck('On the turn you have 8 outs. About how often do you hit on the river?', ['8%', '16%', '32%'], 1,
            'Rule of 2: 8 × 2 = 16%. The exact figure is 8 ÷ 46 ≈ 17%.'),
        LessonCheck('You hold J♥ T♥ on 9♥ 8♥ 2♣. How many outs to a straight or flush?', ['9', '12', '15'], 2,
            'Nine hearts plus the six non-heart sevens and queens: 15.',
            figure: LessonFigure(hole: 'Jh Th', board: '9h 8h 2c')),
      ],
    ),
  ]),
  Unit('Preflop', 'Which hands to play, and how.', [
    Lesson(
      id: 'opening',
      title: 'Opening ranges',
      summary: 'Raise first in, wider from later seats.',
      skill: Skill.preflop,
      drill: DrillKind.preflop,
      pages: [
        LessonPage('Raise, don\'t limp', [
          'When nobody has entered the pot, raise (about 2.5 big blinds) or fold. Limping just calls the big blind, invites everyone in, and gives up the chance to win the blinds straight away.',
        ]),
        LessonPage('Wider as you get closer to the button', [
          'Under the gun you might open around 15% of hands; on the button around 45%. The fewer players behind you, the less likely someone has a big hand, and the more often you\'ll have position after the flop.',
        ], figure: LessonFigure(range: '22+, A2s+, K5s+, Q8s+, J8s+, T8s+, 97s+, 86s+, 75s+, 65s, 54s, A8o+, KTo+, QTo+, JTo', caption: 'A typical button opening range.')),
      ],
      checks: [
        LessonCheck('Everyone folds to you on the button with A♠ 5♠. What\'s best?', ['Fold', 'Limp', 'Raise'], 2,
            'A5s is a comfortable button open: it plays well and can make the nut flush.'),
        LessonCheck('Which seat should open the widest range?', ['Under the gun', 'Cutoff', 'Button'], 2,
            'The button has the fewest players behind and position on every later street.'),
        LessonCheck('Why is open-limping a leak?', [
          'It\'s against the rules',
          'You can\'t win the blinds right away and you invite several players in',
          'It costs more than raising',
        ], 1, 'Raising can win the pot immediately and usually leaves you heads-up with the initiative.'),
      ],
    ),
    Lesson(
      id: 'three-bet',
      title: '3-betting',
      summary: 'Re-raising for value, and as a bluff.',
      skill: Skill.preflop,
      drill: DrillKind.preflop,
      pages: [
        LessonPage('Value and bluffs', [
          'A 3-bet is the first re-raise. Value 3-bets use hands that want a big pot: QQ+, AK. Bluff 3-bets use hands that play well when called and block strong hands, like A5s.',
          'Mixing both means opponents can\'t just fold everything but their best hands.',
        ]),
        LessonPage('Sizing', [
          'In position, 3-bet to about 3 times the open. Out of position, closer to 4 times, because you\'ll play the rest of the hand at a disadvantage.',
        ]),
      ],
      checks: [
        LessonCheck('The cutoff opens to 2.5 bb. You\'re on the button. About how big should a 3-bet be?', ['5 bb', '7.5 bb', '15 bb'], 1,
            'In position, about three times the open: 7.5 big blinds.'),
        LessonCheck('Why is A5s a good 3-bet bluff?', [
          'It\'s a strong hand that wants a big pot',
          'It blocks aces and plays well when called',
          'It always makes the best hand',
        ], 1, 'Holding an ace makes opponents less likely to have AA or AK, and the wheel and nut-flush potential help when you\'re called.'),
        LessonCheck('Which hand is a value 3-bet against most opens?', ['K♠ Q♦', 'Q♥ Q♣', '7♦ 6♦'], 1,
            'QQ is ahead of almost every opening range.'),
      ],
    ),
    Lesson(
      id: 'blind-defence',
      title: 'Defending the big blind',
      summary: 'You already have chips in: you get a discount.',
      skill: Skill.preflop,
      drill: DrillKind.preflop,
      pages: [
        LessonPage('The price', [
          'Facing a 2.5 bb open, the pot is 1 + 0.5 + 2.5 = 4 bb and you call 1.5 bb more. You need 1.5 ÷ 5.5 ≈ 27% equity, so you can defend many more hands than you would open.',
        ]),
        LessonPage('Against whom?', [
          'Defend widest against the button, which opens wide, and tighter against early-position raisers, whose ranges are strong.',
        ]),
      ],
      checks: [
        LessonCheck('The button opens to 2.5 bb. What equity does calling from the big blind need?', ['About 17%', 'About 27%', 'About 40%'], 1,
            'You call 1.5 bb into a pot that becomes 5.5 bb: about 27%.'),
        LessonCheck('Against which opener should you defend the most hands?', ['Under the gun', 'The button'], 1,
            'The button opens the widest range, so more of your hands are ahead of it.'),
        LessonCheck('In the big blind, is it fine to call a raise with some hands you\'d never open yourself?', ['Yes', 'No'], 0,
            'Yes: the chips you\'ve already posted give you a discount on the call.'),
      ],
    ),
    Lesson(
      id: 'facing-3bet',
      title: 'Facing a 3-bet',
      summary: 'Fold, call or 4-bet.',
      skill: Skill.preflop,
      drill: DrillKind.preflop,
      pages: [
        LessonPage('Most of your range folds', [
          'When you open and face a 3-bet, fold the weaker part of your opening range. Call with hands that play well (pairs like JJ-TT, suited broadways, AQ) and 4-bet your strongest (KK+, sometimes AK).',
          'Folding too often lets people 3-bet you light; calling too often puts you in big pots with dominated hands.',
        ]),
      ],
      checks: [
        LessonCheck('You opened K♣ 9♦ from the cutoff and the button 3-bets. Usually best?', ['Fold', 'Call', '4-bet'], 0,
            'K9 offsuit is dominated by most 3-betting hands and plays poorly in a bigger pot.'),
        LessonCheck('You opened K♥ K♠ and face a 3-bet. Usually best?', ['Call', '4-bet'], 1,
            'Kings want to build the pot: 4-bet for value.'),
        LessonCheck('What happens if you fold too much to 3-bets?', [
          'Opponents can 3-bet you with any two cards profitably',
          'You win more pots',
          'Nothing',
        ], 0, 'Over-folding hands opponents a free profit every time they re-raise.'),
      ],
    ),
  ]),
  Unit('After the flop', 'Continuation bets, textures and draws.', [
    Lesson(
      id: 'cbet',
      title: 'Continuation bets',
      summary: 'When the preflop raiser should keep betting.',
      skill: Skill.postflop,
      trainerStreet: 'flop',
      pages: [
        LessonPage('Range advantage', [
          'The preflop raiser usually holds more strong hands, especially on high, dry boards like K♠ 7♦ 2♣. There you can bet small (about a third of the pot) with most of your range.',
        ], figure: LessonFigure(board: 'Ks 7d 2c', caption: 'Dry and king-high: good for the preflop raiser.')),
        LessonPage('When to slow down', [
          'Low, connected or two-tone boards like 9♥ 8♥ 7♣ hit the caller\'s range of suited connectors and small pairs. Bet less often, and bigger with the hands you do bet.',
        ], figure: LessonFigure(board: '9h 8h 7c', caption: 'Wet and connected: it favours the caller.')),
      ],
      checks: [
        LessonCheck('You raised preflop and the flop is K♠ 7♦ 2♣. A good default?', [
          'Check almost always',
          'Bet small with much of your range',
          'Go all-in',
        ], 1, 'This board favours your range, so a small, frequent bet does well.', figure: LessonFigure(board: 'Ks 7d 2c')),
        LessonCheck('Which board favours the big blind caller?', ['A♠ K♦ 3♣', '9♥ 8♥ 7♣', 'K♣ K♦ 4♠'], 1,
            'Connected, suited middle cards hit the hands the big blind defends with.'),
        LessonCheck('On wet boards you bet less often. When you do bet, size it…', ['Smaller', 'Bigger'], 1,
            'Bigger bets charge the many draws and protect your hand.'),
      ],
    ),
    Lesson(
      id: 'texture',
      title: 'Board texture',
      summary: 'Dry, wet and dynamic boards.',
      skill: Skill.postflop,
      trainerStreet: 'flop',
      pages: [
        LessonPage('Reading a board', [
          'Dry boards have few draws: K♣ 8♦ 3♠. Wet boards have many: J♥ T♥ 8♣ offers flush and straight draws.',
          'On wet boards hand strength changes a lot by the river, so made hands should bet to deny equity and draws gain value.',
        ], figure: LessonFigure(board: 'Jh Th 8c')),
      ],
      checks: [
        LessonCheck('Which flop is the driest?', ['J♥ T♥ 8♣', 'K♣ 8♦ 3♠', '7♠ 6♠ 5♦'], 1,
            'Rainbow, unconnected cards: very few draws.'),
        LessonCheck('You hold top pair on J♥ T♥ 8♣. Why bet?', [
          'To make better hands fold',
          'To charge draws and protect your hand',
          'Betting is required',
        ], 1, 'Many turn cards are bad for you; betting makes draws pay to see them.', figure: LessonFigure(board: 'Jh Th 8c')),
        LessonCheck('Which hand gains the most on a wet board?', ['A strong draw', 'Ace-high with no draw'], 0,
            'Draws have equity against made hands and can win by betting or by hitting.'),
      ],
    ),
    Lesson(
      id: 'draws',
      title: 'Playing draws',
      summary: 'Semi-bluffs and when a draw is a favourite.',
      skill: Skill.postflop,
      drill: DrillKind.equity,
      pages: [
        LessonPage('Semi-bluffs', [
          'Betting or raising with a draw wins two ways: opponents fold now, or you hit later. That\'s why strong draws are some of the best hands to bet aggressively with.',
        ]),
        LessonPage('Big draws are favourites', [
          'A flush draw plus an open-ended straight draw (15 outs) has more equity than a single pair on the flop: about 54% against one pair with two cards to come.',
        ], figure: LessonFigure(hole: 'Jh Th', board: '9h 8h 2c')),
      ],
      checks: [
        LessonCheck('What\'s a semi-bluff?', [
          'A bet with a weak hand that has no chance',
          'A bet with a draw that can win now or improve later',
          'A half-sized bluff',
        ], 1, 'It\'s not a pure bluff: you have real equity if called.'),
        LessonCheck('J♥ T♥ on 9♥ 8♥ 2♣ against a pair of aces, flop to river. Who\'s ahead?', ['The aces', 'The draw', 'It\'s exactly even'], 1,
            'With 15 outs and two cards to come, the draw is a slight favourite (about 54%).',
            figure: LessonFigure(hole: 'Jh Th', board: '9h 8h 2c')),
        LessonCheck('Facing a big all-in on the turn with a gutshot (4 outs), usually…', ['Call', 'Fold'], 1,
            'About 9% to hit with one card to come: far less than a big bet\'s price.'),
      ],
    ),
    Lesson(
      id: 'value-bluff',
      title: 'Value or bluff?',
      summary: 'Every bet needs a reason.',
      skill: Skill.river,
      trainerStreet: 'river',
      pages: [
        LessonPage('Two reasons to bet', [
          'Value: worse hands will call. Bluff: better hands will fold. If neither is true, checking is usually better.',
          'A bet with a medium hand that only gets called by better and folds out worse is a "turning your hand into a bluff" mistake.',
        ]),
        LessonPage('Thin value', [
          'Against players who call too much, bet more medium-strength hands for value. Against tight players, value-bet only strong hands and bluff more.',
        ]),
      ],
      checks: [
        LessonCheck('On the river, worse hands won\'t call and better hands won\'t fold. Best?', ['Bet', 'Check'], 1,
            'With no reason to bet, checking keeps the pot small and lets you see a showdown.'),
        LessonCheck('Against a calling station, you should…', ['Bluff more', 'Value-bet thinner'], 1,
            'Stations call with worse hands too often, so bet more of your decent hands and bluff less.'),
        LessonCheck('A value bet is a bet that…', ['Gets called by worse hands', 'Gets better hands to fold'], 0,
            'That\'s value. Getting better hands to fold is a bluff.'),
      ],
    ),
  ]),
  Unit('Advanced theory', 'Sizing, bluffing ratios and blockers.', [
    Lesson(
      id: 'sizing',
      title: 'Bet sizing',
      summary: 'Big bets for polarised ranges, small for merged.',
      skill: Skill.river,
      trainerStreet: 'river',
      pages: [
        LessonPage('Polarised or merged', [
          'A polarised range is strong hands and bluffs, with little in between: bet big. A merged range is many medium-strength hands: bet small to get called by worse.',
          'Rivers are often polarised; flops are often merged.',
        ]),
      ],
      checks: [
        LessonCheck('Your river range is the nuts or nothing. Better sizing?', ['Small', 'Large'], 1,
            'A polarised range wants big bets: maximum value from the nuts, maximum fold pressure with bluffs.'),
        LessonCheck('Your flop range is lots of medium pairs. Better sizing?', ['Small', 'Large'], 0,
            'Small bets get called by worse and keep the pot manageable.'),
        LessonCheck('Which street is most often polarised?', ['Flop', 'River'], 1,
            'By the river, draws have missed or hit, so ranges split into strong hands and air.'),
      ],
    ),
    Lesson(
      id: 'bluff-ratio',
      title: 'Bluff ratios and MDF',
      summary: 'How often to bluff, and how often to defend.',
      skill: Skill.river,
      trainerStreet: 'river',
      pages: [
        LessonPage('How often to bluff', [
          'On the river, a balanced betting range has bluffs = bet ÷ (pot + 2 × bet) of its bets. With a pot-size bet that\'s one third; with half pot, one quarter.',
          'Then the caller can\'t profit by always calling or always folding.',
        ]),
        LessonPage('Minimum defence frequency', [
          'To stop any two cards from bluffing profitably, defend at least pot ÷ (pot + bet) of your range. Against a pot-size bet that\'s 50%; against half pot, about 67%.',
          'Felt\'s solver plays to these numbers. Study a river spot and you\'ll see them.',
        ]),
      ],
      checks: [
        LessonCheck('You bet the pot on the river. What share of your bets should be bluffs?', ['One quarter', 'One third', 'One half'], 1,
            '1 ÷ (1 + 2) = one third.'),
        LessonCheck('Facing a half-pot bet, the minimum defence frequency is about…', ['33%', '50%', '67%'], 2,
            'Pot ÷ (pot + bet) = 1 ÷ 1.5 ≈ 67%.'),
        LessonCheck('Facing a pot-size bet, how much of your range should continue?', ['About 50%', 'About 75%', 'About 25%'], 0,
            '1 ÷ (1 + 1) = 50%.'),
      ],
    ),
    Lesson(
      id: 'blockers',
      title: 'Blockers',
      summary: 'Cards in your hand change what they can have.',
      skill: Skill.reading,
      trainerStreet: 'river',
      pages: [
        LessonPage('Removing combinations', [
          'If you hold the A♠ on a board with three spades, your opponent can\'t have the nut flush. That makes your bluff more likely to work and their big bet more likely to be a bluff.',
          'Choose bluffs that block your opponent\'s strong hands and unblock their folding hands.',
        ], figure: LessonFigure(hole: 'As 4d', board: 'Ks 9s 5s 2c 7h')),
      ],
      checks: [
        LessonCheck('On K♠ 9♠ 5♠ 2♣ 7♥ you hold A♠ 4♦. What does the A♠ block?', ['Two pair', 'The nut flush', 'A straight'], 1,
            'Nobody else can hold the ace of spades, so nobody else has the nut flush.',
            figure: LessonFigure(hole: 'As 4d', board: 'Ks 9s 5s 2c 7h')),
        LessonCheck('A good river bluff usually…', [
          'Blocks the hands that would call',
          'Blocks the hands that would fold',
        ], 0, 'Blocking strong calling hands makes a fold more likely.'),
        LessonCheck('Holding K♥ K♣ preflop, how likely is your opponent to hold kings?', ['More likely', 'Less likely', 'No change'], 1,
            'Only one king is left, so there\'s just one combination of KK for them.'),
      ],
    ),
    Lesson(
      id: 'river',
      title: 'Bluff-catching',
      summary: 'Calling when they bluff enough.',
      skill: Skill.river,
      trainerStreet: 'river',
      pages: [
        LessonPage('Hands that only beat bluffs', [
          'A bluff-catcher beats bluffs and loses to value. Call when the pot odds say your opponent bluffs often enough, and use reads: some players never bluff, others bluff far too much.',
        ]),
      ],
      checks: [
        LessonCheck('Facing a pot-size river bet, a bluff-catcher needs the bettor to bluff at least…', ['25% of the time', '33% of the time', '50% of the time'], 1,
            'You risk 1 to win 2: you need to be right one time in three.'),
        LessonCheck('Against a player who never bluffs, a bluff-catcher should…', ['Call', 'Fold'], 1,
            'If they never bluff, your hand only beats hands they don\'t have.'),
        LessonCheck('Against a maniac who bluffs constantly, you should call…', ['More', 'Less'], 0,
            'Their range has more bluffs, so more of your hands beat it.'),
      ],
    ),
  ]),
  Unit('Tournaments', 'Short stacks, ICM and final tables.', [
    Lesson(
      id: 'stacks',
      title: 'Stack sizes',
      summary: 'Think in big blinds.',
      skill: Skill.pushFold,
      drill: DrillKind.pushFold,
      pages: [
        LessonPage('Big blinds, not chips', [
          '3,000 chips is a lot at 25/50 (60 big blinds) and very little at 400/800 (under 4). How you play depends on your stack in big blinds.',
          'Around 100 bb, play normally. Under 25 bb, avoid raise-folding and look for re-shoves. Under about 15 bb, mostly shove or fold.',
        ]),
      ],
      checks: [
        LessonCheck('You have 4,000 chips at 200/400. How many big blinds?', ['4', '10', '20'], 1, '4,000 ÷ 400 = 10 big blinds.'),
        LessonCheck('At 12 big blinds with an unopened pot, your usual options are…', ['Limp or call', 'Shove or fold', 'Min-raise'], 1,
            'Short stacks get the most from all-in shoves: fold equity plus no awkward post-flop decisions.'),
        LessonCheck('Why does stack depth matter?', [
          'It changes which hands and plays are profitable',
          'It changes the hand rankings',
        ], 0, 'Deep stacks reward playability; short stacks reward raw strength and fold equity.'),
      ],
    ),
    Lesson(
      id: 'push-fold',
      title: 'Push or fold',
      summary: 'Shoving ranges and calling them.',
      skill: Skill.pushFold,
      drill: DrillKind.pushFold,
      pages: [
        LessonPage('Shove wider late, call tighter', [
          'With 10 bb on the button you can shove around 30% of hands. Under the gun, far fewer.',
          'Calling a shove needs a stronger range than shoving: the shover has fold equity, and you don\'t.',
        ], figure: LessonFigure(range: '22+, A2s+, K7s+, Q9s+, J9s+, T9s, A7o+, KTo+, QJo', caption: 'Roughly a button shoving range at 10 big blinds.')),
      ],
      checks: [
        LessonCheck('10 bb on the button with K♦ 7♦, folded to you. Usually best?', ['Fold', 'Shove'], 1,
            'K7s is comfortably inside a 10 bb button shoving range.'),
        LessonCheck('Compared with shoving ranges, calling ranges are…', ['Wider', 'Tighter'], 1,
            'The shover wins when you fold; you can only win by calling and having the best hand.'),
        LessonCheck('8 bb under the gun at a full table with 9♣ 4♦. Usually best?', ['Shove', 'Fold'], 1,
            'With eight players behind, 9-4 offsuit is far too weak.'),
      ],
    ),
    Lesson(
      id: 'icm',
      title: 'ICM: chips aren\'t money',
      summary: 'Why busting costs more than doubling gains.',
      skill: Skill.icm,
      drill: DrillKind.pushFold,
      pages: [
        LessonPage('The Independent Chip Model', [
          'In tournaments, your share of the prize pool depends on your chips, but not in a straight line. Doubling your stack doesn\'t double your prize equity, while busting drops it to zero.',
          'So near pay jumps you need more equity to call all-ins than chip maths alone suggests. Felt\'s coach grades these spots with ICM.',
        ]),
      ],
      checks: [
        LessonCheck('Near the bubble, compared with chip-EV, you should call all-ins…', ['More', 'Less'], 1,
            'Losing costs more prize money than winning gains, so you need a stronger hand to call.'),
        LessonCheck('If you double your chips, your prize equity…', ['Doubles', 'Grows by less than double'], 1,
            'Prizes are spread over several places, so chips have diminishing value.'),
        LessonCheck('Who feels ICM pressure the most on the bubble?', ['The chip leader', 'Medium stacks', 'Nobody'], 1,
            'Medium stacks risk busting before the money while shorter stacks might bust first.'),
      ],
    ),
    Lesson(
      id: 'final-table',
      title: 'Bubbles and final tables',
      summary: 'Applying pressure, and when to tighten up.',
      skill: Skill.icm,
      drill: DrillKind.pushFold,
      pages: [
        LessonPage('Big stacks attack', [
          'On the bubble the chip leader can open and shove more, because medium stacks must fold all but their best hands.',
          'Medium stacks should avoid confrontations with bigger stacks. Short stacks shove when they still have fold equity.',
        ]),
      ],
      checks: [
        LessonCheck('You\'re the chip leader on the bubble. Generally…', ['Tighten up', 'Open and pressure more'], 1,
            'Others can\'t afford to call you light, so your steals succeed more often.'),
        LessonCheck('A medium stack facing the chip leader\'s shove on the bubble should call with…', ['A wide range', 'Only strong hands'], 1,
            'ICM makes calls much more expensive for them.'),
        LessonCheck('At a final table, each place usually pays…', ['The same', 'More than the one below'], 1,
            'Pay jumps grow towards the top, which keeps ICM pressure high.'),
      ],
    ),
  ]),
  Unit('Reading opponents', 'Stats, styles and how to exploit them.', [
    Lesson(
      id: 'stats',
      title: 'VPIP, PFR and aggression',
      summary: 'Three numbers that describe a player.',
      skill: Skill.reading,
      pages: [
        LessonPage('The numbers', [
          'VPIP is how often a player puts money in preflop voluntarily. PFR is how often they raise preflop. Aggression factor compares bets and raises with calls.',
          'A winning style is often around 22-28% VPIP with PFR close behind. Big gaps between VPIP and PFR mean a lot of calling.',
        ]),
      ],
      checks: [
        LessonCheck('VPIP 45%, PFR 8%. This player…', ['Raises a lot', 'Calls a lot', 'Plays very few hands'], 1,
            'They play almost half their hands but rarely raise: a calling station.'),
        LessonCheck('What does PFR measure?', ['How often they raise preflop', 'How often they fold to bets'], 0,
            'Pre-flop raise: the share of hands they raise before the flop.'),
        LessonCheck('VPIP 12%, PFR 10%. This player is…', ['Loose', 'Tight'], 1, 'They play only 12% of hands: very tight.'),
      ],
    ),
    Lesson(
      id: 'styles',
      title: 'Player types',
      summary: 'Rocks, sharks, mavericks, stations and wildcards.',
      skill: Skill.reading,
      pages: [
        LessonPage('Five styles', [
          'Rock: tight and passive, bets only strong hands. Shark: tight and aggressive. Maverick: loose and aggressive. Station: loose and passive, calls too much. Wildcard: bets and raises nearly everything.',
          'Felt\'s bots play these styles. Turn off "Show opponent styles" in Settings to practise spotting them.',
        ]),
      ],
      checks: [
        LessonCheck('Plays few hands but bets and raises them hard:', ['Rock', 'Shark', 'Station'], 1, 'Tight and aggressive: a shark.'),
        LessonCheck('Calls almost every bet but rarely raises:', ['Wildcard', 'Station'], 1, 'Loose and passive: a calling station.'),
        LessonCheck('A rock suddenly raises the river. Usually they have…', ['A bluff', 'A strong hand'], 1, 'Rocks rarely bluff.'),
      ],
    ),
    Lesson(
      id: 'exploits',
      title: 'Exploiting styles',
      summary: 'Adjusting to who you\'re playing.',
      skill: Skill.reading,
      pages: [
        LessonPage('Simple adjustments', [
          'Stations: value-bet thinner and bigger, bluff rarely. Rocks: steal their blinds, bluff more, fold to their aggression. Wildcards: call down lighter, let them bluff.',
          'Felt\'s Shark and Maverick bots make these adjustments against you, so mix it up.',
        ]),
      ],
      checks: [
        LessonCheck('Against a station, your river bluffs should be…', ['More frequent', 'Rarer'], 1, 'They don\'t fold, so bluffs lose money.'),
        LessonCheck('Against a rock, stealing their blinds is…', ['Profitable', 'A mistake'], 0, 'They fold too often.'),
        LessonCheck('A wildcard bets big on the river. With a decent bluff-catcher…', ['Call more', 'Fold more'], 0,
            'Their range is full of bluffs.'),
      ],
    ),
    Lesson(
      id: 'patterns',
      title: 'Betting patterns',
      summary: 'What lines and sizes tell you.',
      skill: Skill.reading,
      pages: [
        LessonPage('Lines tell stories', [
          'Check-calling flop and turn, then leading big on the river, often means a draw got there. A player who bets every street small may be protecting a medium hand.',
          'Felt\'s opponents narrow your range the same way: every action changes what they think you hold.',
        ]),
      ],
      checks: [
        LessonCheck('A passive player who check-called two streets suddenly bets big when the flush completes. Often they…', ['Made the flush', 'Are bluffing'], 0,
            'Passive players rarely turn hands into bluffs; the completing card is the likely reason.'),
        LessonCheck('Small bets on every street from a cautious player often mean…', ['The nuts', 'A medium-strength hand'], 1,
            'Small bets keep the pot manageable for hands that want a showdown.'),
        LessonCheck('Do your own actions narrow your range in opponents\' eyes?', ['Yes', 'No'], 0, 'Every action tells a story to a thinking player.'),
      ],
    ),
  ]),
];

/// Every lesson in course order.
final List<Lesson> allLessons = [for (final u in course) ...u.lessons];

Lesson? lessonById(String id) => allLessons.where((l) => l.id == id).firstOrNull;
