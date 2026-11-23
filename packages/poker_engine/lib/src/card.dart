/// Cards are plain ints 0..51: `rank * 4 + suit`.
/// rank 0..12 = 2..A, suit 0..3 = clubs, diamonds, hearts, spades.
library;

const rankChars = '23456789TJQKA';
const suitChars = 'cdhs';
const suitSymbols = ['♣', '♦', '♥', '♠'];
const rankNames = [
  'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', //
  'Jack', 'Queen', 'King', 'Ace',
];
const rankPlurals = [
  'Twos', 'Threes', 'Fours', 'Fives', 'Sixes', 'Sevens', 'Eights', 'Nines', //
  'Tens', 'Jacks', 'Queens', 'Kings', 'Aces',
];

int cardRank(int card) => card >> 2;
int cardSuit(int card) => card & 3;
int makeCard(int rank, int suit) => rank * 4 + suit;

/// Parses "As", "Td", "2c".
int parseCard(String s) {
  if (s.length != 2) throw FormatException('Bad card: $s');
  final r = rankChars.indexOf(s[0].toUpperCase());
  final u = suitChars.indexOf(s[1].toLowerCase());
  if (r < 0 || u < 0) throw FormatException('Bad card: $s');
  return makeCard(r, u);
}

/// Parses "As Kd Qh" (spaces optional: "AsKdQh").
List<int> parseCards(String s) {
  final t = s.replaceAll(' ', '');
  return [for (var i = 0; i < t.length; i += 2) parseCard(t.substring(i, i + 2))];
}

String cardToString(int card) =>
    '${rankChars[cardRank(card)]}${suitChars[cardSuit(card)]}';

String cardsToString(Iterable<int> cards) => cards.map(cardToString).join(' ');

List<int> fullDeck() => List<int>.generate(52, (i) => i);
