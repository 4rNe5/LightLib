// How a Korean translation's narration is told, read off its sentence
// endings: what happened in the past (-었다), an action in the present
// (-ㄴ다/-는다), how things are (아프다, 있다, 모르겠다), an explanation
// (-ㄴ 것이다). No morphological analyser: the last syllables and their
// jamo tell (checked against Kiwi on three translated light novels: the
// same class for 98.4-99.7% of narration sentences).
//
// Used to find the sentences where a past-tense narration slips into the
// present for one sentence (the owner's "~했다 하다가 갑자기 ~한다"),
// 그녀 standing where Korean names the person or says nothing, and
// paragraphs thick with word-for-word constructions.

/// How a Korean narration sentence ends.
enum KoreanEnding {
  /// -었다, -았다, -했다: what happened.
  past,

  /// -ㄴ다, -는다: someone does something, told in the present.
  actionPresent,

  /// 아프다, 있다, 없다, 모르겠다, 같다: how things are, what is felt or
  /// judged now. At home in a past-tense narration.
  statePresent,

  /// -ㄴ 것이다, -는 것이다: explains (のだ).
  explains,

  /// -ㄹ 것이다: a guess.
  guess,

  /// -라고 한다, -는 모양이다: hearsay, appearance.
  hearsay,

  /// -습니다, -요.
  polite,
  other,
}

final _trailing = RegExp(r'''[\s.!?…~”’"')\]―─\-♪]+$''');
final _sentenceEnd = RegExp(r'(?<=[.!?…。！？])\s+|\n');
final _dialogueStart = RegExp(r'''^[「『（(“‘"']''');

/// Whether [source] (a paragraph of the book) is speech or thought in
/// brackets, not narration.
bool isDialogue(String source) => _dialogueStart.hasMatch(source.trim());

/// The sentences of [text].
List<String> sentencesOf(String text) => [
      for (final s in text.split(_sentenceEnd))
        if (s.trim().isNotEmpty) s.trim(),
    ];

int _final(String ch) {
  final c = ch.codeUnitAt(0) - 0xAC00;
  return c < 0 || c >= 11172 ? -1 : c % 28;
}

final _quoted = RegExp(r'(라고|다고|냐고|자고) 한다$');
final _seems = RegExp(r'(모양|듯|것 같|셈|법)이?다$');
final _thing = RegExp(r'(것이|거)(다|었다|였다)$');
final _politeDa = RegExp(r'[습입합랍갑답]니다$');

/// How the Korean [sentence] ends.
KoreanEnding koreanEnding(String sentence) {
  final s = sentence.replaceAll(_trailing, '');
  if (s.length < 2) return KoreanEnding.other;
  if (!s.endsWith('다')) {
    return RegExp(r'(요|죠)$').hasMatch(s)
        ? KoreanEnding.polite
        : KoreanEnding.other;
  }
  final thing = _thing.firstMatch(s);
  if (thing != null) {
    final head = s.substring(0, thing.start);
    final spaced = head.endsWith(' ');
    final before = head.trimRight();
    // 증거다 ends in 거다 too: only 것이다, or 거다 as a word of its own.
    if (thing.group(1) == '것이' || spaced) {
      if (before.isNotEmpty && _final(before[before.length - 1]) == 8) {
        return KoreanEnding.guess; // -ㄹ 것이다
      }
      return KoreanEnding.explains;
    }
  }
  if (_politeDa.hasMatch(s) ||
      (s.endsWith('니다') && s.length >= 3 && _final(s[s.length - 3]) == 17)) {
    return KoreanEnding.polite;
  }
  if (_quoted.hasMatch(s) || _seems.hasMatch(s)) return KoreanEnding.hearsay;
  final last = s[s.length - 2];
  // 겠 and 있 end in ㅆ as the past does, and are not it.
  if (last == '겠' || last == '있') return KoreanEnding.statePresent;
  if (_final(last) == 20) return KoreanEnding.past;
  if (s.endsWith('는다') || _final(last) == 4) return KoreanEnding.actionPresent;
  return KoreanEnding.statePresent;
}

final _jaTrailing = RegExp(r'[\s。！？!?…―─」』）)♪]+$');
final _jaPast = RegExp(r'(た|だった)$');

/// Whether the Japanese [sentence] ends in the past (〜た, 〜だった).
bool japaneseEndsInPast(String sentence) =>
    _jaPast.hasMatch(sentence.replaceAll(_jaTrailing, ''));

// What a present-tense sentence says when it does not tell an event of
// the scene: a habit (-곤 한다, 매번, いつも), what may or must be
// (-ㄹ지도 모른다, -야 한다), what someone feels, knows or wishes
// (좋아한다, 안다, -었으면 한다, 기분이 든다), what a word means. The
// book has these in the present on purpose, and so does the Korean.
final _notAnEventKo = RegExp(r'(곤 한다|기 마련이다'
    r'|(ㄹ|을|를|일|할|될|닐|킬|릴|울|줄|올|갈|볼)지(도)? 모른다'
    r'|[가-힣]지(도)? 모른다'
    r'|야 한다|야만 한다|(으면|면) 한다|(으면|면) 싶다'
    r'|(좋아|싫어|사랑|미워|원|동경|존경|이해|기억|확신|생각|짐작|걱정|기대|후회|감사|부러워)한다'
    r'|(바란|믿는|안|모른|느낀|여긴|보인|들린)다'
    r'|(기분|생각|느낌|예감|마음|의문|확신|직감)(이|도|마저|까지|만)? ?든다'
    r'|(을|를|이|가) (뜻|의미|말|가리)(한|킨)다'
    r'|(두근거린|설렌|긴장된|떨린|쑤신|저린|아려 온|울렁거린)다'
    r'|(이|가)? ?(아닌가|일까|걸까) 싶다)$');
final _habitKo = RegExp(
    r'(항상|언제나|늘 |매번|매일|매주|매년|자주|종종|가끔|때때로|이따금|때마다|'
    r'보통|대개|대체로|으레|평소|원래|본래|일반적으로)');
final _habitJa = RegExp(
    r'(いつも|毎回|毎日|毎朝|毎晩|毎週|毎年|たびに|度に|都度|時々|ときどき|'
    r'たまに|普段|ふだん|大抵|たいてい|常に|基本的に|もともと|元々)');
final _notAnEventJa = RegExp(
    r'(かもしれない|かも知れない|だろう|であろう|はずだ|と思う|気がする|気もする|'
    r'好きだ|嫌いだ|苦手だ|得意だ|のことだ|ものだ|ことがある|こともある|'
    r'てほしい|て欲しい|たい|なければならない|ねばならない|べきだ|らしい|ようだ|'
    r'そうだ|みたいだ|のである|わけだ)$');

/// Whether the Korean narration sentence [sentence] tells an event of the
/// scene in the present (-ㄴ다/-는다): something done or happening there
/// and then - the kind Korean narration in the past tense tells in the
/// past. Not a habit, a general fact, or what someone feels, knows,
/// wishes or supposes ([source]: the book's sentence it translates, when
/// known - it may say so where the Korean does not).
bool tellsEventInPresent(String sentence, {String? source}) {
  if (koreanEnding(sentence) != KoreanEnding.actionPresent) return false;
  final s = sentence.replaceAll(_trailing, '');
  if (_notAnEventKo.hasMatch(s) || _habitKo.hasMatch(s)) return false;
  if (source != null) {
    final j = source.replaceAll(_jaTrailing, '');
    if (_habitJa.hasMatch(j) || _notAnEventJa.hasMatch(j)) return false;
  }
  return true;
}

/// Whether [translation] (of the narration paragraph [source]) tells an
/// event in the present tense ([tellsEventInPresent]): the check a
/// paragraph sent back for a slip of tense has to pass.
bool hasActionPresent(String source, String translation) {
  if (isDialogue(source)) return false;
  final ko = sentencesOf(translation), ja = sentencesOf(source);
  final habit = _habitJa.hasMatch(source);
  for (var k = 0; k < ko.length; k++) {
    if (tellsEventInPresent(ko[k],
        source: ko.length == ja.length ? ja[k] : null)) {
      // Sentences that do not pair up: a habit said anywhere in the
      // book's paragraph covers them all.
      if (ko.length != ja.length && habit) continue;
      return true;
    }
  }
  return false;
}

/// Which of [translations] (of the consecutive paragraphs [sources]) slip
/// out of a past-tense narration: a narration sentence that tells an
/// event of the scene in the present ([tellsEventInPresent])
///  - between two sentences in the past (the one before may be the end of
///    [before], the translation of what came just before), or
///  - where the book's own sentence is in the past (〜た).
/// A run of present-tense sentences is a scene told that way, and is left
/// alone; so is how things are (아프다, 모르겠다), and so is a habit, a
/// general fact or a feeling the book itself says in the present
/// (いつもからかってくる → 늘 놀리곤 한다): measured on three books, an
/// engine never turned a sentence the book has in the past into the
/// present - every present-tense sentence was the book's own - so only
/// the events are put in the past, as Korean narration has them.
Set<int> tenseSlips(List<String> sources, List<String?> translations,
    {List<String?> before = const []}) {
  // The narration's sentences in order: (paragraph, ending, whether it
  // tells an event of the scene in the present).
  final stream = <(int, KoreanEnding, bool)>[];
  for (final t in before) {
    if (t == null || t.isEmpty || isDialogue(t)) continue;
    for (final s in sentencesOf(t)) {
      stream.add((-1, koreanEnding(s), false));
    }
  }
  final slips = <int>{};
  for (var i = 0; i < sources.length; i++) {
    final t = translations[i];
    if (t == null || t.isEmpty || isDialogue(sources[i])) continue;
    final ko = sentencesOf(t);
    final ja = sentencesOf(sources[i]);
    final paired = ko.length == ja.length;
    // Sentences that do not pair up: a habit said anywhere in the book's
    // paragraph covers them all.
    final habit = !paired && _habitJa.hasMatch(sources[i]);
    for (var k = 0; k < ko.length; k++) {
      final ending = koreanEnding(ko[k]);
      stream.add((
        i,
        ending,
        !habit && tellsEventInPresent(ko[k], source: paired ? ja[k] : null),
      ));
      // The book's sentence is in the past and the Korean is not: the
      // translation changed the tense, whatever the sentence says.
      if (ending == KoreanEnding.actionPresent &&
          paired &&
          japaneseEndsInPast(ja[k])) {
        slips.add(i);
      }
    }
  }
  bool tensed(KoreanEnding e) =>
      e == KoreanEnding.past || e == KoreanEnding.actionPresent;
  final told = [for (final s in stream) if (tensed(s.$2)) s];
  for (var k = 1; k + 1 < told.length; k++) {
    if (told[k].$1 >= 0 &&
        told[k].$3 &&
        told[k - 1].$2 == KoreanEnding.past &&
        told[k + 1].$2 == KoreanEnding.past) {
      slips.add(told[k].$1);
    }
  }
  return slips;
}

final _she = RegExp(r'그녀(는|가|의|를|에게|도|와|한테)?');

/// How many times [translation] says 그녀.
int sheCount(String translation) => _she.allMatches(translation).length;

/// Whether [translation] carries 彼女 over as 그녀 where Korean would name
/// the person or leave the subject out: the source says 彼女 and the
/// translation 그녀, more than once in the paragraph or as its very
/// subject.
bool leansOnShe(String source, String translation) {
  if (!source.contains('彼女')) return false;
  final n = sheCount(translation);
  if (n == 0) return false;
  return n >= 2 || RegExp(r'^[“‘"]?그녀(는|가)').hasMatch(translation.trim());
}

/// Word-for-word constructions and what each weighs: 〜ている as -고
/// 있(었)다, 〜と思う as -라고 생각하다, 〜てしまう as -어 버리다, and the
/// like. One alone is ordinary Korean; several in a paragraph read as a
/// translation.
final _stiffPatterns = <(RegExp, int)>[
  (RegExp(r'고 있(었다|다|는|던|었)'), 1),
  (RegExp(r'(라고|다고|이라고) 생각(했|한|하)'), 1),
  (RegExp(r'(아|어|여|해) ?버(렸|리|린)'), 1),
  (RegExp(r'에(게)? 있어(서)?'), 2),
  (RegExp(r'지 않으면 안 ?(된다|돼|되)'), 2),
  (RegExp(r'에 다름 ?아니'), 2),
  (RegExp(r'에 틀림없'), 1),
  (RegExp(r'(되어지|되어진|지어지|어지게 되)'), 2),
  (RegExp(r'하는 것이 가능'), 2),
  (RegExp(r'(을|ㄹ)까나'), 2),
  (RegExp(r'[가-힣]+의 [가-힣]+의 [가-힣]+의'), 2),
  (RegExp(r'에 대(해|한|해서)'), 1),
  (RegExp(r'(라는|다는) 것(이|을|은)'), 1),
];

/// How thick [translation] is with word-for-word constructions (0: none).
int stiffness(String translation) {
  var score = 0;
  for (final (pattern, weight) in _stiffPatterns) {
    score += pattern.allMatches(translation).length * weight;
  }
  return score;
}

/// Whether a paragraph is stiff enough to be worth writing again: three
/// such constructions, or two in a short paragraph.
bool readsStiff(String translation) {
  final score = stiffness(translation);
  return score >= 3 || (score >= 2 && translation.length < 60);
}
