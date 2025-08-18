import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

// ======== Utils ========
T? getOrNull<T>(List<T> list, int index) {
  if (index < 0 || index >= list.length) return null;
  return list[index];
}

enum Seat { north, east, south, west }

enum Suit { spade, heart, diamond, club }

extension SeatHeb on Seat {
  String get heb => switch (this) {
        Seat.north => 'צפון',
        Seat.east => 'מזרח',
        Seat.south => 'דרום',
        Seat.west => 'מערב',
      };
}

extension SuitSym on Suit {
  String get sym => switch (this) {
        Suit.spade => '♠',
        Suit.heart => '♥',
        Suit.diamond => '♦',
        Suit.club => '♣',
      };
}

const List<String> rankOrder = [
  'A',
  'K',
  'Q',
  'J',
  'T',
  '9',
  '8',
  '7',
  '6',
  '5',
  '4',
  '3',
  '2'
];
int hcpOfRank(String r) => switch (r) {
      'A' => 4,
      'K' => 3,
      'Q' => 2,
      'J' => 1,
      _ => 0,
    };

// ======== Models ========
class Hand {
  final Map<Suit, List<String>> cards;
  Hand(this.cards);

  int get hcp =>
      cards.values.expand((c) => c).map(hcpOfRank).fold(0, (a, b) => a + b);
  int length(Suit s) => cards[s]?.length ?? 0;

  String fmtLine(Suit s) =>
      "${s.sym} ${cards[s]!.isEmpty ? '—' : cards[s]!.join()}";
  String shape() =>
      "${length(Suit.spade)}-${length(Suit.heart)}-${length(Suit.diamond)}-${length(Suit.club)}";
}

class Deal {
  final Map<Seat, Hand> hands;
  final Seat dealer;
  final String? vul; // None/NS/EW/Both
  Deal({required this.hands, required this.dealer, this.vul});
}

class Auction {
  final List<String> calls;
  Auction(this.calls);
}

class Trick {
  final List<String> cards; // 4 קלפים בסדר המשחק
  Trick(this.cards);
}

class PlayRecord {
  final List<Trick> tricks;
  PlayRecord(this.tricks);
}

class LinParseResult {
  final Deal deal;
  final Map<Seat, String> playerNames;
  final Auction auction;
  final PlayRecord play;
  final Seat declarer;
  final String contract; // e.g. 6H
  final String openingLead; // e.g. C4
  LinParseResult({
    required this.deal,
    required this.playerNames,
    required this.auction,
    required this.play,
    required this.declarer,
    required this.contract,
    required this.openingLead,
  });
}

// ניתוח לפי טריק
class TrickInsight {
  final int trickNumber;
  final Seat leader;
  final Seat winner;
  final Map<Seat, String> playsBySeat; // seat -> "S4"
  final List<String> notes; // טעויות/המלצות לאותו טריק
  TrickInsight({
    required this.trickNumber,
    required this.leader,
    required this.winner,
    required this.playsBySeat,
    required this.notes,
  });
}

// ======== Parser ========
class LinParser {
  static const List<String> _ranks = [
    'A',
    'K',
    'Q',
    'J',
    'T',
    '9',
    '8',
    '7',
    '6',
    '5',
    '4',
    '3',
    '2'
  ];

  static LinParseResult parse(String lin) {
    // names
    final pnMatch = RegExp(r"pn\|([^|]+)").firstMatch(lin);
    final names = (pnMatch?.group(1) ?? "North,East,South,West")
        .split(',')
        .map((s) => s.trim())
        .toList();
    final playerNames = <Seat, String>{
      Seat.north: getOrNull(names, 0) ?? 'North',
      Seat.east: getOrNull(names, 1) ?? 'East',
      Seat.south: getOrNull(names, 2) ?? 'South',
      Seat.west: getOrNull(names, 3) ?? 'West',
    };

    // dealer + hands
    final md = RegExp(r"md\|(\d)([^|]*)").firstMatch(lin);
    if (md == null) throw FormatException("LIN missing md| section");
    final dealerCode = int.parse(md.group(1)!);
    final dealer = switch (dealerCode) {
      1 => Seat.north,
      2 => Seat.east,
      3 => Seat.south,
      4 => Seat.west,
      _ => Seat.north
    };
    final handsPart = md.group(2)!; // after digit, until next |
    final tokens = handsPart.split(',');
    final order = _seatOrderFromDealer(dealer);
    final hands = <Seat, Hand>{};
    for (int i = 0; i < tokens.length && i < 4; i++) {
      hands[order[i]] = _parseHand(tokens[i]);
    }

    // --- השלמת יד/יים חסרות מתוך 52 קלפים ---
    final seen = <String>{};
    for (final e in hands.entries) {
      final h = e.value;
      for (final su in Suit.values) {
        for (final r in h.cards[su]!) {
          seen.add('${_suitLetter(su)}$r');
        }
      }
    }
    final missingCards = <String>[];
    for (final c in _deck()) {
      if (!seen.contains(c)) missingCards.add(c);
    }
    final missingSeats =
        Seat.values.where((s) => !hands.containsKey(s)).toList();
    if (missingSeats.isNotEmpty) {
      final bySuit = {
        Suit.spade: <String>[],
        Suit.heart: <String>[],
        Suit.diamond: <String>[],
        Suit.club: <String>[],
      };
      for (final c in missingCards) {
        final su = _suitFromChar(c[0])!;
        bySuit[su]!.add(_rankToT(c.substring(1)));
      }
      for (final su in bySuit.keys) {
        bySuit[su]!.sort(
            (a, b) => rankOrder.indexOf(a).compareTo(rankOrder.indexOf(b)));
      }
      if (missingSeats.length == 1) {
        hands[missingSeats.single] = Hand(
            {for (final su in Suit.values) su: List<String>.from(bySuit[su]!)});
      } else {
        int idx = 0;
        final tmp = {
          for (final s in missingSeats)
            s: {for (final su in Suit.values) su: <String>[]}
        };
        for (final su in Suit.values) {
          for (final r in bySuit[su]!) {
            final seat = missingSeats[idx % missingSeats.length];
            tmp[seat]![su]!.add(r);
            idx++;
          }
        }
        for (final s in missingSeats) {
          hands[s] = Hand({for (final su in Suit.values) su: tmp[s]![su]!});
        }
      }
    }
    // --- סוף השלמת ידיים ---

    // vul (optional)
    String? vul;
    final sv = RegExp(r"sv\|([noeb])").firstMatch(lin)?.group(1);
    if (sv != null) {
      vul = switch (sv) {
        'o' => 'None',
        'n' => 'NS',
        'e' => 'EW',
        'b' => 'Both',
        _ => null
      };
    }

    // auction
    final calls = RegExp(r"mb\|([^\|]+)")
        .allMatches(lin)
        .map((m) => m.group(1)!.trim())
        .toList();
    final auction = Auction(calls);

    // contract
    final mc = RegExp(r"mc\|([^\|]+)").firstMatch(lin)?.group(1);
    final contract = (mc != null && mc.isNotEmpty)
        ? _normalizeCall(mc)
        : _lastBid(calls) ?? 'Unknown';

    // declarer
    final declarer = _inferDeclarer(calls, dealer, contract);

    // play
    final played = RegExp(r"pc\|([^\|]+)")
        .allMatches(lin)
        .map((m) => m.group(1)!)
        .toList();
    final tricks = <Trick>[];
    for (int i = 0; i + 3 < played.length; i += 4) {
      tricks.add(Trick(played.sublist(i, i + 4)));
    }
    final play = PlayRecord(tricks);
    final openingLead = played.isNotEmpty ? played.first : '';

    final deal = Deal(hands: hands, dealer: dealer, vul: vul);
    return LinParseResult(
      deal: deal,
      playerNames: playerNames,
      auction: auction,
      play: play,
      declarer: declarer,
      contract: contract,
      openingLead: openingLead,
    );
  }

  static String _normalizeCall(String raw) {
    final c = raw.trim().toUpperCase();
    final m = RegExp(r'^([1-7])N(T)?$').firstMatch(c);
    if (m != null) return '${m.group(1)}N'; // N פנימי
    return c;
  }

  static List<Seat> _seatOrderFromDealer(Seat dealer) => switch (dealer) {
        Seat.north => [Seat.north, Seat.east, Seat.south, Seat.west],
        Seat.east => [Seat.east, Seat.south, Seat.west, Seat.north],
        Seat.south => [Seat.south, Seat.west, Seat.north, Seat.east],
        Seat.west => [Seat.west, Seat.north, Seat.east, Seat.south],
      };

  static Hand _parseHand(String s) {
    final map = <Suit, List<String>>{
      Suit.spade: [],
      Suit.heart: [],
      Suit.diamond: [],
      Suit.club: []
    };
    Suit? cur;
    final buf = <String>[];
    void flush() {
      if (cur != null) map[cur] = List.of(buf);
      buf.clear();
    }

    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == 'S') {
        flush();
        cur = Suit.spade;
      } else if (ch == 'H') {
        flush();
        cur = Suit.heart;
      } else if (ch == 'D') {
        flush();
        cur = Suit.diamond;
      } else if (ch == 'C') {
        flush();
        cur = Suit.club;
      } else {
        // תמיכה ב-"10" או "T"
        if (i + 1 < s.length && ch == '1' && (s[i + 1] == '0')) {
          buf.add('T');
          i++; // דילוג על '0'
        } else if (RegExp(r'[2-9TJQKA]', caseSensitive: false).hasMatch(ch)) {
          buf.add(ch.toUpperCase());
        } else {
          // ignore stray chars/spaces
        }
      }
    }
    flush();

    for (final su in map.keys) {
      map[su] = map[su]!.map((r) => r == '10' ? 'T' : r).toList();
      map[su]!
          .sort((a, b) => rankOrder.indexOf(a).compareTo(rankOrder.indexOf(b)));
    }
    return Hand(map);
  }

  static String? _lastBid(List<String> calls) {
    for (int i = calls.length - 1; i >= 0; i--) {
      final c = _normalizeCall(calls[i]);
      if (RegExp(r'^[1-7][SHDCN]$').hasMatch(c)) return c;
    }
    return null;
  }

  static Seat _next(Seat s) => switch (s) {
        Seat.north => Seat.east,
        Seat.east => Seat.south,
        Seat.south => Seat.west,
        Seat.west => Seat.north
      };

  static Seat _inferDeclarer(List<String> calls, Seat dealer, String contract) {
    final m = RegExp(r'^[1-7]([SHDCN])$').firstMatch(_normalizeCall(contract));
    if (m == null) return dealer;
    final strain = m.group(1)!;
    Seat turn = dealer;
    Seat? declarer;
    bool? nsDeclaring;

    for (final raw in calls) {
      final c = _normalizeCall(raw);
      final isBid = RegExp(r'^[1-7][SHDCN]$').hasMatch(c);
      if (isBid) {
        final sideNS = (turn == Seat.north || turn == Seat.south);
        if (c.endsWith(strain)) {
          nsDeclaring ??= sideNS;
          if (nsDeclaring == sideNS && declarer == null) {
            declarer = turn;
          }
        }
      }
      turn = _next(turn);
    }
    return declarer ?? dealer;
  }

  // ----- Helpers for deck completion -----
  static Iterable<String> _deck() sync* {
    for (final s in ['S', 'H', 'D', 'C']) {
      for (final r in _ranks) yield '$s$r';
    }
  }

  static String _rankToT(String r) => (r == '10') ? 'T' : r;

  static String _suitLetter(Suit s) => switch (s) {
        Suit.spade => 'S',
        Suit.heart => 'H',
        Suit.diamond => 'D',
        Suit.club => 'C',
      };

  static Suit? _suitFromChar(String c) => switch (c) {
        'S' => Suit.spade,
        'H' => Suit.heart,
        'D' => Suit.diamond,
        'C' => Suit.club,
        _ => null
      };
}

// ======== Analyzer (היוריסטיקה) ========
class Analyzer {
  final LinParseResult data;
  Analyzer(this.data);

  Map<String, int> hcpAnalysis() {
    int h(Seat s) => data.deal.hands[s]?.hcp ?? 0;
    return {
      'N': h(Seat.north),
      'E': h(Seat.east),
      'S': h(Seat.south),
      'W': h(Seat.west),
      'NS': (data.deal.hands[Seat.north]?.hcp ?? 0) +
          (data.deal.hands[Seat.south]?.hcp ?? 0),
      'EW': (data.deal.hands[Seat.east]?.hcp ?? 0) +
          (data.deal.hands[Seat.west]?.hcp ?? 0),
    };
  }

  Map<String, dynamic> fitAnalysis() {
    int len(Seat s, Suit t) => data.deal.hands[s]?.length(t) ?? 0;
    int nsLen(Suit t) => len(Seat.north, t) + len(Seat.south, t);
    int ewLen(Suit t) => len(Seat.east, t) + len(Seat.west, t);

    Suit bestNS = Suit.spade;
    int bestNSLen = nsLen(Suit.spade);
    for (final s in [Suit.heart, Suit.diamond, Suit.club]) {
      final L = nsLen(s);
      if (L > bestNSLen) {
        bestNSLen = L;
        bestNS = s;
      }
    }
    Suit bestEW = Suit.spade;
    int bestEWLen = ewLen(Suit.spade);
    for (final s in [Suit.heart, Suit.diamond, Suit.club]) {
      final L = ewLen(s);
      if (L > bestEWLen) {
        bestEWLen = L;
        bestEW = s;
      }
    }

    return {
      'NS_best': {'suit': bestNS.sym, 'length': bestNSLen},
      'EW_best': {'suit': bestEW.sym, 'length': bestEWLen},
      'NS_lengths': {
        '♠': nsLen(Suit.spade),
        '♥': nsLen(Suit.heart),
        '♦': nsLen(Suit.diamond),
        '♣': nsLen(Suit.club)
      },
      'EW_lengths': {
        '♠': ewLen(Suit.spade),
        '♥': ewLen(Suit.heart),
        '♦': ewLen(Suit.diamond),
        '♣': ewLen(Suit.club)
      },
    };
  }

  List<String> conventionHints() {
    final calls =
        data.auction.calls.map((c) => LinParser._normalizeCall(c)).toList();
    final hints = <String>[];

    final idx1H = calls.indexWhere((c) => c == '1H');
    if (idx1H >= 0) {
      final c2 = getOrNull(calls, idx1H + 2);
      if (c2 != null && RegExp(r'^3[SDC]$').hasMatch(c2)) {
        final suit = c2[1];
        hints.add(
            "חשד ל-Splinter אחרי 1♥ → $c2 (תמיכת ♥ + קוצר ב-${_strainName(suit)}).");
      }
    }
    final idx1S = calls.indexWhere((c) => c == '1S');
    if (idx1S >= 0) {
      final c2 = getOrNull(calls, idx1S + 2);
      if (c2 != null && RegExp(r'^3[HDC]$').hasMatch(c2)) {
        final suit = c2[1];
        hints.add(
            "חשד ל-Splinter אחרי 1♠ → $c2 (תמיכת ♠ + קוצר ב-${_strainName(suit)}).");
      }
    }

    final idx4N = calls.indexWhere((c) => c == '4N' || c == '4NT' || c == '4N');
    if (idx4N >= 0) {
      hints.add(
          "4NT מזוהה כ-RKCB (1430): 5♣=1/4, 5♦=3/0, 5♥=2 ללא Q של השליט, 5♠=2 עם Q.");
      final resp = getOrNull(calls, idx4N + 1);
      if (resp != null && RegExp(r"^5[SHDC]$").hasMatch(resp)) {
        final meaning = switch (resp) {
          '5C' => '1 או 4 מפתחות',
          '5D' => '3 או 0 מפתחות',
          '5H' => '2 מפתחות בלי Q של השליט',
          '5S' => '2 מפתחות עם Q של השליט',
          _ => 'תגובה ל-RKCB',
        };
        hints.add("תגובה ל-RKCB: $resp = $meaning.");
      }
    }
    return hints;
  }

  Map<String, dynamic> loserCountEstimate() {
    final m = RegExp(r'^[1-7]([SHDCN])$')
        .firstMatch(LinParser._normalizeCall(data.contract));
    if (m == null) return {'note': 'חוזה לא מזוהה'};

    final strain = m.group(1)!;
    if (strain == 'N') {
      return {'note': 'בחוזה NT נהוג להעריך מקורות לקיחות ועוצרים במקום LTC.'};
    }

    final trump = _suitFromStrain(strain)!;
    final dec = data.declarer;
    final dum = _partner(dec);

    final decHand = data.deal.hands[dec];
    final dumHand = data.deal.hands[dum];
    if (decHand == null || dumHand == null) {
      return {'note': 'לא נמצאו ידיים מלאות לדקלרטור/דאמי.'};
    }

    int losersHand(Hand h, Suit s) {
      final r = h.cards[s] ?? const <String>[];
      // מכובדים A/K/Q מפחיתים עד 3 מפסידים אפשריים
      int cnt = 3;
      if (r.contains('A')) cnt--;
      if (r.contains('K')) cnt--;
      if (r.contains('Q')) cnt--;
      final len = r.length.clamp(0, 3);
      return cnt.clamp(0, len);
    }

    final lDec = {for (final s in Suit.values) s: losersHand(decHand, s)};
    final lDum = {for (final s in Suit.values) s: losersHand(dumHand, s)};

    int total = 0;
    final perSuit = <String, int>{};
    for (final s in Suit.values) {
      final sum = lDec[s]! + lDum[s]!;
      perSuit[s.sym] = sum;
      total += sum;
    }

    return {
      'trump': trump.sym,
      'estimated_losers': total,
      'by_suit': perSuit,
      'note': 'LTC קלאסי (אומדן; ללא התאמות קיצור/רפים).',
    };
  }

  List<String> safetyPlanSuggestions() {
    final tips = <String>[];
    final m = RegExp(r'^[1-7]([SHDCN])$')
        .firstMatch(LinParser._normalizeCall(data.contract));
    if (m == null) return ['חוזה לא מזוהה.'];
    final strain = m.group(1)!;

    if (strain == 'N') {
      tips.add(
          'NT: תכנן מקורות לקיחות (סדרה ארוכה), ושמור כניסות בין היד לשולחן.');
      tips.add('שקול עיכוב זכייה (hold-up) כדי לנתק תקשורת בהגנה.');
    } else {
      tips.add(
          'בשליט: בדוק פיצול טראמפ מוקדם (לקיחה עליונה אחת) לפני משיכה מלאה.');
      tips.add('חפש רַף בסדרה קצרה אצלך כדי לצמצם מפסידים.');
      tips.add('שמור כניסות לדאמי/יד כדי לבצע פינסים/רַפים/השלכות.');
    }
    if (data.openingLead.isNotEmpty) {
      tips.add(
          'נהל את הסדרה המובלת בזהירות – לפעמים כדאי לעכב זכייה בלקיחה הראשונה.');
    }
    return tips;
  }

  // ========= ניתוח שלב-אחר-שלב =========
  List<TrickInsight> analyzePlayStepByStep() {
    final insights = <TrickInsight>[];
    if (data.play.tricks.isEmpty) return insights;

    final m = RegExp(r'^[1-7]([SHDCN])$')
        .firstMatch(LinParser._normalizeCall(data.contract));
    final strain = (m != null) ? m.group(1)! : 'N';
    final trump = _suitFromStrain(strain); // null ב-NT

    // עותק של הידיים לעקיבה אחרי קלפים שנשחקו
    final rem = <Seat, Map<Suit, List<String>>>{};
    for (final seat in Seat.values) {
      final h = data.deal.hands[seat];
      rem[seat] = {
        for (final su in Suit.values) su: List<String>.from(h?.cards[su] ?? [])
      };
    }

    Seat leader = LinParser._next(data.declarer); // LHO מוביל בפתיחה
    bool anyDefenderRuff = false;
    int trumpsLedByDecl = 0;

    for (int t = 0; t < data.play.tricks.length; t++) {
      final trick = data.play.tricks[t].cards;
      final order = [
        leader,
        LinParser._next(leader),
        LinParser._next(LinParser._next(leader)),
        LinParser._next(LinParser._next(LinParser._next(leader)))
      ];

      final leadCard = trick.isNotEmpty ? trick[0] : '';
      final leadSuitChar =
          leadCard.isNotEmpty ? leadCard[0].toUpperCase() : 'X';
      final leadSuit = LinParser._suitFromChar(leadSuitChar);

      Seat? winner;
      String? winningCard;
      final playsBySeat = <Seat, String>{};
      final notes = <String>[];

      // ביקורת על הובלה בלקיחה 1
      if (t == 0 && leadSuit != null) {
        notes.addAll(
            _openingLeadFeedback(leader, leadSuit, _cardRank(leadCard)));
      }

      for (int i = 0; i < 4 && i < trick.length; i++) {
        final seat = order[i];
        final cardRaw = trick[i];
        if (cardRaw.isEmpty) continue;

        final sChar = cardRaw[0].toUpperCase();
        final r = _cardRank(cardRaw);
        final suit = LinParser._suitFromChar(sChar);
        playsBySeat[seat] = "$sChar$r";

        // עקיבת קלפים/חובת הליכה
        if (i > 0 && leadSuit != null && suit != leadSuit) {
          final hadLead = (rem[seat]![leadSuit] ?? const <String>[]).isNotEmpty;
          if (hadLead) {
            notes.add(
                "${seat.heb}: נראה שלא עקב בסדרה מובלת למרות שהיה צבע – חשד ל-revoke.");
          }
        }

        // זיהוי רַף של ההגנה
        if (i > 0 &&
            leadSuit != null &&
            trump != null &&
            suit == trump &&
            leadSuit != trump) {
          final isDeclSide =
              (seat == data.declarer || seat == _partner(data.declarer));
          if (!isDeclSide) anyDefenderRuff = true;
        }

        // Second hand low
        if (i == 1 && leadSuit != null && suit == leadSuit) {
          final leadIsLow = !_isHonor(_cardRank(leadCard));
          if (_isHonor(r) && leadIsLow) {
            final thirdCard = (trick.length >= 3) ? trick[2] : '';
            if (thirdCard.isNotEmpty) {
              final thirdSuit =
                  LinParser._suitFromChar(thirdCard[0].toUpperCase());
              final thirdRank = _cardRank(thirdCard);
              if (thirdSuit == leadSuit && _rankHigher(thirdRank, r)) {
                notes.add(
                    "${seat.heb}: כלל 'Second hand low' – עדיף לשמור מכובד; שלישי ממילא כיסה במכובד גבוה יותר.");
              }
            }
          }
        }

        // Cover an honor (RHO מול דאמי)
        if (i == 1 && leadSuit != null && suit == leadSuit) {
          final dummy = _partner(data.declarer);
          if (leader == dummy && _isHonor(_cardRank(leadCard))) {
            final oppHasHigher = rem[seat]![leadSuit]!
                .any((x) => _isHigherHonor(x, _cardRank(leadCard)));
            if (oppHasHigher && !_isHonor(r)) {
              notes.add(
                  "${seat.heb}: לא כיסה מכובד של דאמי – לעיתים כדאי לכסות כדי למנוע הקמת הסדרה.");
            }
          }
        }

        // החמצת פינס (פשטני)
        if (i == 2 && leadSuit != null && suit == leadSuit) {
          final leaderIsDecl = (leader == data.declarer);
          final dummy = _partner(data.declarer);
          if (leaderIsDecl && order[2] == dummy) {
            final secondLow = !_isHonor(_cardRank(trick[1]));
            final dummyHadMiddleHonor =
                rem[dummy]![leadSuit]!.any((x) => x == 'Q' || x == 'J');
            final played = _cardRank(trick[2]);
            if (secondLow &&
                dummyHadMiddleHonor &&
                (played == 'A' || played == 'K')) {
              notes.add(
                  "דאמי: ייתכן שהוחמצה פינס לכיוון ${leadSuit.sym}. במקום לעלות ב-$played, עדיף לבדוק Q/J אם המכובד אצל RHO.");
            }
          }
        }

        // קביעת הזוכה
        if (suit != null) {
          if (winner == null) {
            winner = seat;
            winningCard = "$sChar$r";
          } else {
            final winCardSuit = LinParser._suitFromChar(winningCard![0]);
            final winCardRank = _cardRank(winningCard);
            final beats =
                _beatsCurrent(suit, r, winCardSuit!, winCardRank, trump);
            if (beats) {
              winner = seat;
              winningCard = "$sChar$r";
            }
          }
        }

        // הסר את הקלף מהיתרה
        if (suit != null) rem[seat]![suit]!.remove(r);
      }

      // "לא משך שליטים"
      if (trump != null) {
        final ledIsTrump = (leadSuit == trump);
        final declSideLedTrump = ledIsTrump &&
            (leader == data.declarer || leader == _partner(data.declarer));
        if (declSideLedTrump) trumpsLedByDecl++;

        if (t == 2 && trumpsLedByDecl == 0) {
          notes.add(
              "דקלרטור: טרם משכת שליטים בשלוש הלקיחות הראשונות. אם אין צורך דחוף ברַפים/השלכות – עדיף למשוך מוקדם.");
        }
        if (anyDefenderRuff && t <= 3) {
          notes.add(
              "ההגנה ביצעה רַף מוקדם. משיכת שליטים מוקדמת הייתה יכולה לצמצם רַפים כאלה.");
        }
      }

      final win = winner ?? leader;
      insights.add(TrickInsight(
        trickNumber: t + 1,
        leader: leader,
        winner: win,
        playsBySeat: playsBySeat,
        notes: notes,
      ));

      leader = win; // המנצח מוביל לטריק הבא
    }

    // --- תכנון סדר משחק (הערות כלליות לדקלרטור) ---
    final planningNotes = <String>[];
    if (trump != null) {
      if (trumpsLedByDecl == 0 && data.play.tricks.length >= 3) {
        planningNotes.add(
            "דקלרטור: משיכת שליטים מאוחרת יחסית – שקול למשוך מוקדם אם אין צורך דחוף ברַפים/השלכות.");
      }
      if (anyDefenderRuff &&
          trumpsLedByDecl >= 2 &&
          data.play.tricks.length >= 4) {
        planningNotes.add(
            "דקלרטור: משיכת שליטים מוקדמת ייתכן ופגעה ביכולת לבצע רַפים בצד הקצר.");
      }
    } else {
      // NT
      if (data.play.tricks.isNotEmpty) {
        final firstTrick = data.play.tricks.first.cards;
        bool wonHigh = firstTrick.any((c) {
          final r = _cardRank(c);
          return (r == 'A' || r == 'K');
        });
        if (wonHigh) {
          planningNotes.add(
              "NT: ייתכן שהוחמצה עיכוב (hold-up) בלקיחה הראשונה כדי לנתק תקשורת בהגנה.");
        }
      }
    }
    if (planningNotes.isNotEmpty) {
      insights.insert(
        0,
        TrickInsight(
          trickNumber: 0,
          leader: data.declarer,
          winner: data.declarer,
          playsBySeat: const {},
          notes: planningNotes,
        ),
      );
    }

    return insights;
  }

  // ======== עזרי ניתוח ========
  List<String> _openingLeadFeedback(
      Seat leader, Suit leadSuit, String leadRank) {
    final notes = <String>[];
    final leaderHand = data.deal.hands[leader];
    if (leaderHand == null) return notes;

    final m = RegExp(r'^[1-7]([SHDCN])$')
        .firstMatch(LinParser._normalizeCall(data.contract));
    final strain = (m != null) ? m.group(1)! : 'N';
    final isNT = (strain == 'N');

    final ranks = leaderHand.cards[leadSuit] ?? const <String>[];
    final len = ranks.length;

    bool hasSeq(String r1, String r2, [String? r3]) {
      final set = ranks.toSet();
      if (r3 == null) return set.containsAll([r1, r2]);
      return set.containsAll([r1, r2, r3]);
    }

    final topOfSeq = (leadRank == 'A' && hasSeq('A', 'K')) ||
        (leadRank == 'K' && (hasSeq('K', 'Q') || hasSeq('K', 'Q', 'J'))) ||
        (leadRank == 'Q' && hasSeq('Q', 'J')) ||
        (leadRank == 'J' && hasSeq('J', 'T'));

    if (isNT) {
      if (len <= 3 && !topOfSeq) {
        notes.add(
            "הובלה ל-NT מסדרה קצרה/ללא רצף אינה מומלצת לרוב. עדיף להוביל מרביעית הארוכה ('רביעי מלמעלה').");
      }
      if (leadRank == 'A' && !ranks.contains('K')) {
        notes.add(
            "הובלה מ-A ללא K ב-NT עלולה לתת לקיחה לדקלרטור. שקול להוביל מרצף (QJ10) או מרביעית הארוכה.");
      }
    } else {
      // חוזה שליט
      if (leadRank == 'K' && !ranks.contains('Q')) {
        notes.add(
            "הובלת K ללא Q נגד חוזה שליט אינה מועדפת לרוב. העדף רצפים או סינגלטון/דאבלט לקראת רַף.");
      }
    }

    return notes;
  }

  Suit? _suitFromStrain(String s) => switch (s) {
        'S' => Suit.spade,
        'H' => Suit.heart,
        'D' => Suit.diamond,
        'C' => Suit.club,
        'N' => null,
        _ => null
      };

  Seat _partner(Seat s) => switch (s) {
        Seat.north => Seat.south,
        Seat.south => Seat.north,
        Seat.east => Seat.west,
        Seat.west => Seat.east
      };

  String _cardRank(String pc) {
    final raw = pc.substring(1).toUpperCase();
    if (raw == '10') return 'T';
    return raw;
  }

  bool _isHonor(String r) => (r == 'A' || r == 'K' || r == 'Q' || r == 'J');

  bool _isHigherHonor(String have, String ledHonor) {
    final hi = ['A', 'K', 'Q', 'J'];
    final idx = hi.indexOf(have);
    final ledIdx = hi.indexOf(ledHonor);
    if (idx == -1 || ledIdx == -1) return false;
    return idx < ledIdx; // קטן = גבוה יותר
  }

  bool _rankHigher(String r1, String r2) =>
      rankOrder.indexOf(r1) < rankOrder.indexOf(r2);

  bool _beatsCurrent(
      Suit suit, String rank, Suit winSuit, String winRank, Suit? trump) {
    if (trump != null) {
      if (suit == trump && winSuit != trump) return true;
      if (suit != trump && winSuit == trump) return false;
      if (suit == winSuit) return _rankHigher(rank, winRank);
      return false;
    } else {
      if (suit != winSuit) return false;
      return _rankHigher(rank, winRank);
    }
  }

  String _strainName(String c) => switch (c) {
        'S' => '♠',
        'H' => '♥',
        'D' => '♦',
        'C' => '♣',
        'N' => 'NT',
        _ => c
      };
}

// ======== Heatmap helpers (מודלים) ========
enum MistakeType {
  openingLead, // הובלת פתיחה לא טובה
  revokeSuspect, // חשד ל-revoke
  secondHandLow, // Second hand low שהופרה
  missedCoverHonor, // לא כיסה מכובד
  missedFinesse, // החמצת פינס
  lateTrump, // איחור במשיכת שליטים
  defenderRuff, // רַף מוקדם של ההגנה
  other, // אחר
}

class _TopMistake {
  final Seat seat;
  final MistakeType type;
  final int count;
  _TopMistake(this.seat, this.type, this.count);
}

class _HeatData {
  final Map<Seat, Map<MistakeType, int>> counts;
  final Map<Seat, int> totals;
  final int maxCell;
  final List<_TopMistake> top3;
  _HeatData(this.counts, this.totals, this.maxCell, this.top3);
}

// ======== UI ========
void main() => runApp(const BridgeAnalyzerApp());

class BridgeAnalyzerApp extends StatelessWidget {
  const BridgeAnalyzerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bridge LIN Analyzer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981)),
      ),
      home: const AnalyzerScreen(),
    );
  }
}

class AnalyzerScreen extends StatefulWidget {
  const AnalyzerScreen({super.key});
  @override
  State<AnalyzerScreen> createState() => _AnalyzerScreenState();
}

class _AnalyzerScreenState extends State<AnalyzerScreen> {
  LinParseResult? data;
  Map<String, int>? hcp;
  Map<String, dynamic>? fit;
  List<String>? hints;
  Map<String, dynamic>? ltc;
  List<String>? tips;
  List<TrickInsight>? steps;

  // פילטרים למפת חום
  Set<MistakeType> _activeTypes = {...MistakeType.values};

  bool _loading = false;

  String? _fileName; // שם הקובץ המנותח

  // ---- פילטרים: פעולות ----
  void _toggleType(MistakeType t) {
    setState(() {
      if (_activeTypes.contains(t)) {
        _activeTypes.remove(t);
        if (_activeTypes.isEmpty) _activeTypes.add(t);
      } else {
        _activeTypes.add(t);
      }
    });
  }

  void _selectAllTypes() =>
      setState(() => _activeTypes = {...MistakeType.values});
  void _clearTypesKeepOne() =>
      setState(() => _activeTypes = {MistakeType.values.first});

  // ---- Heatmap עזר ----
  String _mistakeHeb(MistakeType t) => switch (t) {
        MistakeType.openingLead => 'הובלת פתיחה',
        MistakeType.revokeSuspect => 'חשד ל־Revoke',
        MistakeType.secondHandLow => 'Second hand low',
        MistakeType.missedCoverHonor => 'לא כיסה מכובד',
        MistakeType.missedFinesse => 'הוחמצה פינס',
        MistakeType.lateTrump => 'איחור משיכת שליטים',
        MistakeType.defenderRuff => 'רַף מוקדם בהגנה',
        MistakeType.other => 'אחר',
      };

  MistakeType _classifyNote(String n) {
    final s = n.toLowerCase();
    if (s.contains('revoke')) return MistakeType.revokeSuspect;
    if (s.contains('second hand low')) return MistakeType.secondHandLow;
    if (s.contains('לא כיסה מכובד')) return MistakeType.missedCoverHonor;
    if (s.contains('הוחמצה פינס')) return MistakeType.missedFinesse;
    if (s.contains('טרם משכת שליטים')) return MistakeType.lateTrump;
    if (s.contains('רַף מוקדם')) return MistakeType.defenderRuff;
    if (s.contains('הובלה')) return MistakeType.openingLead;
    return MistakeType.other;
  }

  Seat? _seatFromNotePrefix(String note, Seat declarer) {
    if (note.startsWith('צפון:')) return Seat.north;
    if (note.startsWith('מזרח:')) return Seat.east;
    if (note.startsWith('דרום:')) return Seat.south;
    if (note.startsWith('מערב:')) return Seat.west;
    if (note.startsWith('דקלרטור:')) return declarer;
    if (note.startsWith('דאמי:')) return _partnerOf(declarer);
    return null;
  }

  Seat _partnerOf(Seat s) => switch (s) {
        Seat.north => Seat.south,
        Seat.south => Seat.north,
        Seat.east => Seat.west,
        Seat.west => Seat.east
      };

  _HeatData _buildHeatData() {
    final seats = Seat.values;
    final types = MistakeType.values;

    final counts = {
      for (final s in seats) s: {for (final t in types) t: 0}
    };
    final totals = {for (final s in seats) s: 0};
    int maxCell = 0;

    if (steps == null || data == null)
      return _HeatData(counts, totals, maxCell, const []);

    final declarer = data!.declarer;
    final defenders =
        seats.where((s) => s != declarer && s != _partnerOf(declarer)).toList();

    for (final step in steps!) {
      for (final note in step.notes) {
        final t = _classifyNote(note);
        Seat? target = _seatFromNotePrefix(note, declarer);

        // Opening lead -> למוביל של אותו טריק
        if (target == null && t == MistakeType.openingLead) {
          target = step.leader;
        }

        // Defender ruff -> לשני המגינים
        if (target == null && t == MistakeType.defenderRuff) {
          for (final def in defenders) {
            counts[def]![t] = counts[def]![t]! + 1;
            totals[def] = totals[def]! + 1;
            final v = counts[def]![t]!;
            if (v > maxCell) maxCell = v;
          }
          continue;
        }

        // נסה לשייך לפי מחרוזת שם
        target ??= (() {
          final s = note;
          if (s.contains('צפון')) return Seat.north;
          if (s.contains('מזרח')) return Seat.east;
          if (s.contains('דרום')) return Seat.south;
          if (s.contains('מערב')) return Seat.west;
          return null;
        })();

        target ??= declarer;

        counts[target]![t] = counts[target]![t]! + 1;
        totals[target] = totals[target]! + 1;
        final v = counts[target]![t]!;
        if (v > maxCell) maxCell = v;
      }
    }

    // חישוב TOP 3 (ללא פילטרים)
    final allCells = <_TopMistake>[];
    for (final s in seats) {
      for (final t in types) {
        final c = counts[s]![t]!;
        if (c > 0) allCells.add(_TopMistake(s, t, c));
      }
    }
    allCells.sort((a, b) => b.count.compareTo(a.count));
    final top3 = allCells.take(3).toList();

    return _HeatData(counts, totals, maxCell, top3);
  }

  // ---- UI helpers ----
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showError(String title, Object e, [StackTrace? st]) async {
    // ignore: avoid_print
    print("$title: $e");
    if (st != null) print(st);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(e.toString())),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('סגור'))
        ],
      ),
    );
  }

  Future<void> _pickAndAnalyze() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lin', 'LIN'],
        withData: true, // חשוב ל-Web
      );
      if (res == null || res.files.isEmpty) {
        _showSnack('לא נבחר קובץ.');
        return;
      }

      final file = res.files.single;
      _fileName = file.name; // שם הקובץ לתצוגה
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError(
            'ב-Web יש לקרוא את הקובץ מ-bytes. ודא שהוגדר withData: true.');
      }

      final content = String.fromCharCodes(bytes);
      if (!content.contains('md|')) {
        throw FormatException('קובץ LIN לא תקין: חסר md| (חלוקת ידיים).');
      }

      final parsed = LinParser.parse(content);
      final analyzer = Analyzer(parsed);

      setState(() {
        data = parsed;
        hcp = analyzer.hcpAnalysis();
        fit = analyzer.fitAnalysis();
        hints = analyzer.conventionHints();
        ltc = analyzer.loserCountEstimate();
        tips = analyzer.safetyPlanSuggestions();
        steps = analyzer.analyzePlayStepByStep();
      });

      _showSnack('הקובץ נטען בהצלחה (${content.length} תווים).');
    } catch (e, st) {
      await _showError('שגיאה בטעינת/פענוח הקובץ', e, st);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ניתוח משחק ברידג׳ מקובץ LIN'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(24),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _fileName == null ? '' : 'קובץ: ${_fileName!}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading ? null : _pickAndAnalyze,
          icon: _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(_loading ? 'טוען...' : 'פתח קובץ LIN'),
        ),
        body: data == null ? _empty() : _report(),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.upload_file, size: 72),
              SizedBox(height: 12),
              Text('בחר/י קובץ ‎.LIN‎ לניתוח', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );

  // ---------- Auction rows aligned to dealer + הסבר לכל הכרזה ----------
  List<DataRow> _buildAuctionRows() {
    if (data == null) return [];
    final calls = data!.auction.calls.map(LinParser._normalizeCall).toList();

    int dealerOffset = switch (data!.deal.dealer) {
      Seat.west => 0,
      Seat.north => 1,
      Seat.east => 2,
      Seat.south => 3,
    };

    final totalSlots = dealerOffset + calls.length;
    final rowsCount = (totalSlots / 4).ceil();

    final grid = List.generate(
        rowsCount, (_) => List.filled(4, '', growable: false),
        growable: false);

    for (int i = 0; i < calls.length; i++) {
      final slot = dealerOffset + i;
      final r = slot ~/ 4;
      final c = slot % 4;
      grid[r][c] = _prettyCall(calls[i]);
    }

    final lastIdx = calls.isEmpty ? -1 : calls.length - 1;
    final lastPretty = lastIdx >= 0 ? _prettyCall(calls[lastIdx]) : '';

    List<DataRow> rows = [];
    for (final row in grid) {
      rows.add(DataRow(cells: [
        for (int c = 0; c < 4; c++)
          DataCell(Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: (row[c].isNotEmpty && row[c] == lastPretty)
                  ? Colors.teal.withValues(alpha: 0.10)
                  : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Tooltip(
              message: _explainCallSimple(row[c], calls),
              child: Text(row[c]),
            ),
          )),
      ]));
    }
    return rows;
  }

  List<DataColumn> _auctionHeader() {
    final dealer = data!.deal.dealer;
    final headerLabels = const {
      Seat.west: 'מערב',
      Seat.north: 'צפון',
      Seat.east: 'מזרח',
      Seat.south: 'דרום',
    };
    return [
      for (final s in [Seat.west, Seat.north, Seat.east, Seat.south])
        DataColumn(
          label: Row(
            children: [
              Text(headerLabels[s]!),
              if (s == dealer) const SizedBox(width: 6),
              if (s == dealer)
                const Icon(Icons.circle, size: 8, color: Colors.teal),
            ],
          ),
        ),
    ];
  }

  String _explainCallSimple(String call, List<String> context) {
    final c = LinParser._normalizeCall(call);
    if (c.isEmpty) return '';
    if (c == 'P') return 'פס – ללא הצעה.';
    if (c == 'X' || c == 'D')
      return 'כפול – לרוב Takeout בשלבים מוקדמים או ענישתי בהמשך.';
    if (c == 'XX' || c == 'R') return 'כפול-כפול – לרוב להעניש/להוסיף מחויבות.';
    final m = RegExp(r'^([1-7])([SHDCN])$').firstMatch(c);
    if (m != null) {
      final lvl = m.group(1)!;
      final s = m.group(2)!;
      final strain = switch (s) {
        'S' => '♠',
        'H' => '♥',
        'D' => '♦',
        'C' => '♣',
        'N' => 'NT',
        _ => s
      };
      if (s == 'N') {
        return '$lvl$strain – הצעה טבעית (יד מאוזנת). טווח שכיח: 1NT≈15–17; 2NT≈20–22 (תלוי שיטה).';
      } else {
        return '$lvl$strain – הצעה טבעית/תחרותית בסדרת $strain, לרוב 5+ קלפים (תלוי שיטה).';
      }
    }
    return 'הכרזה מיוחדת/מוסכמות – המשמעות תלויה בשיטה.';
  }

  String _prettyCall(String raw) {
    final c = raw.trim().toUpperCase();
    if (c == 'P') return 'פס';
    if (c == 'X' || c == 'D') return 'כפול';
    if (c == 'XX' || c == 'R') return 'כפול-כפול';
    final m = RegExp(r'^([1-7])N(T)?$').firstMatch(c);
    if (m != null) return '${m.group(1)}NT';
    return c;
  }

  String _vulHeb(String? v) => switch (v) {
        'None' => 'אף אחד',
        'NS' => 'צפון-דרום',
        'EW' => 'מזרח-מערב',
        'Both' => 'שניהם',
        _ => '—',
      };

  Widget _report() {
    final d = data!;
    Widget chipWithTooltip(String text) => Tooltip(
          message: text,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Chip(
              label: Text(
                text,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        );

    Widget handCard(String title, Seat seat, Hand? h) {
      final isDealer = seat == d.deal.dealer;
      return Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: h == null
              ? const Text('—')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        if (isDealer) const SizedBox(width: 6),
                        if (isDealer)
                          const Icon(Icons.circle, size: 8, color: Colors.teal),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(h.fmtLine(Suit.spade)),
                    Text(h.fmtLine(Suit.heart)),
                    Text(h.fmtLine(Suit.diamond)),
                    Text(h.fmtLine(Suit.club)),
                    const SizedBox(height: 6),
                    Text("HCP: ${h.hcp}   Shape: ${h.shape()}"),
                  ],
                ),
        ),
      );
    }

    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
          child: Text(t,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        );

    // הכרזות – מיושר לדילר
    final auctionRows = _buildAuctionRows();

    // טריקים עם הצגת מושב ליד כל קלף
    List<DataRow> trickRows = [];
    Seat leader = LinParser._next(d.declarer);
    for (int t = 0; t < d.play.tricks.length; t++) {
      final trick = d.play.tricks[t].cards;
      final order = [
        leader,
        LinParser._next(leader),
        LinParser._next(LinParser._next(leader)),
        LinParser._next(LinParser._next(LinParser._next(leader))),
      ];
      trickRows.add(DataRow(cells: [
        for (int i = 0; i < 4; i++)
          DataCell(Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(order[i].heb, style: const TextStyle(fontSize: 12)),
              ),
              Text(getOrNull(trick, i) ?? ''),
            ],
          )),
      ]));

      final insight = steps?.firstWhere(
        (s) => s.trickNumber == t + 1,
        orElse: () => TrickInsight(
          trickNumber: t + 1,
          leader: leader,
          winner: leader,
          playsBySeat: const {},
          notes: const [],
        ),
      );
      leader = insight?.winner ?? leader;
    }

    final w = MediaQuery.of(context).size.width;
    final cols = w >= 1100 ? 4 : (w >= 700 ? 2 : 1);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          chipWithTooltip("חוזה: ${_prettyCall(d.contract)}"),
          chipWithTooltip("דקלרטור: ${d.declarer.heb}"),
          chipWithTooltip("הובלה: ${_prettyCard(d.openingLead)}"),
          if (d.deal.vul != null)
            chipWithTooltip("פגיעות: ${_vulHeb(d.deal.vul)}"),
        ]),
        section('שחקנים'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          chipWithTooltip("צפון: ${d.playerNames[Seat.north] ?? '—'}"),
          chipWithTooltip("מזרח: ${d.playerNames[Seat.east] ?? '—'}"),
          chipWithTooltip("דרום: ${d.playerNames[Seat.south] ?? '—'}"),
          chipWithTooltip("מערב: ${d.playerNames[Seat.west] ?? '—'}"),
        ]),
        section('ידיים'),
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            handCard('צפון', Seat.north, d.deal.hands[Seat.north]),
            handCard('מזרח', Seat.east, d.deal.hands[Seat.east]),
            handCard('דרום', Seat.south, d.deal.hands[Seat.south]),
            handCard('מערב', Seat.west, d.deal.hands[Seat.west]),
          ],
        ),
        section('הכרזות (מיושר לדילר: מערב / צפון / מזרח / דרום)'),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Directionality(
            textDirection: TextDirection.ltr, // מונע החלפת מושבים ב-RTL
            child: DataTable(
              columns: _auctionHeader(),
              rows: auctionRows,
            ),
          ),
        ),
        if (d.play.tricks.isNotEmpty) ...[
          section('טריקים (לפי סדר)'),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Directionality(
              textDirection: TextDirection.ltr, // מונע החלפת מושבים ב-RTL
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Lead')),
                  DataColumn(label: Text('2nd')),
                  DataColumn(label: Text('3rd')),
                  DataColumn(label: Text('4th')),
                ],
                rows: trickRows,
              ),
            ),
          ),
        ],
        section('ניתוח נקודות והתאמות'),
        _bullet(
            "HCP – N:${hcp?['N']}  E:${hcp?['E']}  S:${hcp?['S']}  W:${hcp?['W']} | NS:${hcp?['NS']}  EW:${hcp?['EW']}"),
        _bullet(
            "התאמה מיטבית NS: ${fit?['NS_best']?['suit']} ${fit?['NS_best']?['length']} קלפים"),
        _bullet(
            "התאמה מיטבית EW: ${fit?['EW_best']?['suit']} ${fit?['EW_best']?['length']} קלפים"),
        if (hints != null && hints!.isNotEmpty) ...[
          section('רמזים קונבנציונליים'),
          ...hints!.map(_bullet),
        ],
        section('אומדן מפסידים (LTC)'),
        _bullet(
            "שליט: ${ltc?['trump'] ?? '-'} | סה\"כ משוער: ${ltc?['estimated_losers'] ?? '-'}"),
        _bullet("לפי סדרות: ${ltc?['by_suit'] ?? {}}"),
        if (ltc?['note'] != null) _bullet(ltc!['note']),
        section('תוכנית משחק בטוחה – הצעות'),
        ...?tips?.map(_bullet),
        if (steps != null) ...[
          section('טעויות והמלצות – שלב אחר שלב'),
          ...steps!.map((s) => Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.trickNumber == 0)
                        const Text("סיכום תכנון הכרוז",
                            style: TextStyle(fontWeight: FontWeight.w600))
                      else
                        Text(
                            "טריק ${s.trickNumber} • מוביל: ${s.leader.heb} • זכה: ${s.winner.heb}",
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      if (s.playsBySeat.isNotEmpty)
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final entry in s.playsBySeat.entries)
                            Chip(
                                label: Text(
                                    "${entry.key.heb}: ${_prettyCard(entry.value)}")),
                        ]),
                      const SizedBox(height: 8),
                      if (s.notes.isEmpty)
                        _bullet("— לא זוהו טעויות ברורות —")
                      else
                        ...s.notes.map(_bullet),
                    ],
                  ),
                ),
              )),
        ],
        section('מפת חום של טעויות לפי מושב וסוג'),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _heatmap(),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _bullet(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const Text('• '), Expanded(child: Text(t))]),
      );

  String _prettyCard(String pc) {
    if (pc.isEmpty) return '—';
    final s = switch (pc[0].toUpperCase()) {
      'S' => '♠',
      'H' => '♥',
      'D' => '♦',
      'C' => '♣',
      _ => '?'
    };
    String r = pc.substring(1).toUpperCase();
    if (r == '10') r = 'T';
    return "$s$r";
  }

  // ===== Heatmap UI =====
  Color _heatColor(double x) {
    // מדרג לבן→ורוד→אדום לנראות טובה
    final mid = Color.lerp(Colors.white, Colors.pink, x.clamp(0, 0.6))!;
    return Color.lerp(mid, Colors.red, (x - 0.6).clamp(0, 0.4) / 0.4)!;
  }

  Widget _legendHeatmap() {
    return Row(
      children: [
        const Text('מפת חום טעויות: ',
            style: TextStyle(fontWeight: FontWeight.w600)),
        for (int i = 0; i <= 10; i++)
          Expanded(child: Container(height: 10, color: _heatColor(i / 10))),
        const SizedBox(width: 8),
        const Text('נמוך'),
        const SizedBox(width: 4),
        const Text('→'),
        const SizedBox(width: 4),
        const Text('גבוה'),
      ],
    );
  }

  Widget _mistakeFiltersBar(_HeatData heat) {
    int countForType(MistakeType t) {
      int sum = 0;
      for (final s in Seat.values) {
        sum += heat.counts[s]![t]!;
      }
      return sum;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in MistakeType.values)
              FilterChip(
                selected: _activeTypes.contains(t),
                label: Text("${_mistakeHeb(t)} (${countForType(t)})"),
                onSelected: (_) => _toggleType(t),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
                onPressed: _selectAllTypes,
                icon: const Icon(Icons.select_all),
                label: const Text('בחר הכול')),
            const SizedBox(width: 8),
            TextButton.icon(
                onPressed: _clearTypesKeepOne,
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('אפס (השאר אחת)')),
          ],
        ),
      ],
    );
  }

  Widget _heatmap() {
    final dataReady = steps != null && steps!.isNotEmpty;
    if (!dataReady) {
      return _bullet('אין מה לשרטט מפת חום – לא נמצאו טריקים או הערות.');
    }

    final heat = _buildHeatData();

    // סוגים נראים כרגע (לפי פילטרים)
    final visibleTypes = [
      for (final t in MistakeType.values)
        if (_activeTypes.contains(t)) t
    ];

    // מקסימום מקומי לצביעה (על סוגים נראים)
    int localMax = 0;
    for (final s in Seat.values) {
      for (final t in visibleTypes) {
        final v = heat.counts[s]![t]!;
        if (v > localMax) localMax = v;
      }
    }

    // TOP 3 לפי תצוגה נוכחית
    final allCells = <_TopMistake>[];
    for (final s in Seat.values) {
      for (final t in visibleTypes) {
        final c = heat.counts[s]![t]!;
        if (c > 0) allCells.add(_TopMistake(s, t, c));
      }
    }
    allCells.sort((a, b) => b.count.compareTo(a.count));
    final top3 = allCells.take(3).toList();

    // בר חיווי + פילטרים
    final headerWidgets = <Widget>[
      _legendHeatmap(),
      const SizedBox(height: 8),
      _mistakeFiltersBar(heat),
      const SizedBox(height: 8),
    ];

    // כותרת טבלה
    final headerRow = TableRow(
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('מושב', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final t in visibleTypes)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_mistakeHeb(t),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('סה״כ',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );

    TableRow rowForSeat(Seat s) {
      final cells = <Widget>[
        Padding(
          padding: const EdgeInsets.all(8),
          child:
              Text(s.heb, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ];

      final topKeys =
          top3.map((tm) => "${tm.seat.index}-${tm.type.index}").toSet();

      for (final t in visibleTypes) {
        final v = heat.counts[s]![t]!;
        final norm = (localMax == 0) ? 0.0 : (v / localMax);
        final isTop = topKeys.contains("${s.index}-${t.index}");

        cells.add(Stack(
          alignment: Alignment.center,
          children: [
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _heatColor(norm),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(
                '$v',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: (norm > 0.55) ? Colors.white : Colors.black87,
                ),
              ),
            ),
            if (isTop)
              const Positioned(
                right: 4,
                top: 2,
                child: Icon(Icons.warning_amber_rounded, size: 16),
              ),
          ],
        ));
      }

      // סכום לפי סוגים נראים בלבד
      int seatTotal = 0;
      for (final t in visibleTypes) {
        seatTotal += heat.counts[s]![t]!;
      }

      cells.add(Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.black.withValues(alpha: 0.04),
        child: Text('$seatTotal',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ));

      return TableRow(children: cells);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...headerWidgets,
        Table(
          border: TableBorder.all(color: Colors.black12, width: 1),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {0: IntrinsicColumnWidth()},
          children: [
            headerRow,
            rowForSeat(Seat.north),
            rowForSeat(Seat.east),
            rowForSeat(Seat.south),
            rowForSeat(Seat.west),
          ],
        ),
        const SizedBox(height: 12),
        if (top3.isNotEmpty) ...[
          const Text('TOP 3 טעויות (לפי פילטרים פעילים):',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final tm in top3)
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      "${tm.seat.heb} • ${_mistakeHeb(tm.type)} — ${tm.count} אירועים",
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
        ],
      ],
    );
  }
}
