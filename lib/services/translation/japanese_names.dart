// What a reading alone does not give a name's Korean form: the common
// noun a place or school name ends in (栄華高校 is 에이가 고등학교, not
// 에이가코코), and the places of Japan Korean already has a name for
// (東京 is 도쿄, not 토쿄) or that a book rarely gives a reading (上野).

/// A common noun a proper name ends in: its kanji, how it is read there,
/// and the Korean word. The part before it is the name itself.
class NameSuffix {
  const NameSuffix(this.kanji, this.readings, this.korean);
  final String kanji;
  final List<String> readings;
  final String korean;
}

/// Longest first where one ends in another (高等学校 before 学校).
const nameSuffixes = [
  NameSuffix('高等学校', ['こうとうがっこう'], '고등학교'),
  NameSuffix('女子高校', ['じょしこうこう'], '여자고등학교'),
  NameSuffix('高校', ['こうこう'], '고등학교'),
  NameSuffix('中学校', ['ちゅうがっこう'], '중학교'),
  NameSuffix('中学', ['ちゅうがく'], '중학교'),
  NameSuffix('小学校', ['しょうがっこう'], '초등학교'),
  NameSuffix('女学院', ['じょがくいん'], '여학원'),
  NameSuffix('大学', ['だいがく'], '대학교'),
  NameSuffix('学園', ['がくえん'], '학원'),
  NameSuffix('学院', ['がくいん'], '학원'),
  NameSuffix('商店街', ['しょうてんがい'], '상점가'),
  NameSuffix('公園', ['こうえん'], '공원'),
  NameSuffix('神社', ['じんじゃ'], '신사'),
  NameSuffix('病院', ['びょういん'], '병원'),
  NameSuffix('通り', ['どおり', 'とおり'], '거리'),
  NameSuffix('駅', ['えき'], '역'),
  NameSuffix('線', ['せん'], '선'),
  NameSuffix('県', ['けん'], '현'),
  NameSuffix('市', ['し'], '시'),
  NameSuffix('区', ['く'], '구'),
  NameSuffix('湖', ['こ'], '호'),
  NameSuffix('城', ['じょう'], '성'),
];

/// [source] read [reading] as a name and the common noun it ends in, or
/// null when it ends in none (or is nothing but the noun).
({String reading, String korean})? splitNameSuffix(
    String source, String reading) {
  for (final s in nameSuffixes) {
    if (!source.endsWith(s.kanji) || source.length == s.kanji.length) continue;
    for (final r in s.readings) {
      if (reading.endsWith(r) && reading.length > r.length) {
        return (
          reading: reading.substring(0, reading.length - r.length),
          korean: s.korean,
        );
      }
    }
  }
  return null;
}

/// Places Korean writes its own way, whatever the rule for names says.
const japanPlaceNames = {
  '東京': '도쿄',
  '京都': '교토',
  '大阪': '오사카',
  '神戸': '고베',
  '名古屋': '나고야',
  '北海道': '홋카이도',
  '九州': '규슈',
  '四国': '시코쿠',
  '本州': '혼슈',
  '関東': '간토',
  '関西': '간사이',
  '新潟': '니가타',
  '富士山': '후지산',
  '琵琶湖': '비와호',
};

/// Well-known places and how they are read: written by the rule for
/// names (上野 → 우에노), so a book that gives them no reading still
/// gets them right. Prefectures, the big cities, and the parts of Tokyo,
/// Osaka and Kyoto stories are set in. Not the ones that are everyday
/// words as well (大分 "quite", 三重 "threefold", 日光 "sunlight", 両国
/// "both countries", 東北 "north-east").
const japanPlaceReadings = {
  // Tokyo and around.
  '新宿': 'しんじゅく', '渋谷': 'しぶや', '池袋': 'いけぶくろ',
  '上野': 'うえの', '秋葉原': 'あきはばら', '原宿': 'はらじゅく',
  '銀座': 'ぎんざ', '六本木': 'ろっぽんぎ', '品川': 'しながわ',
  '浅草': 'あさくさ', 'お台場': 'おだいば', '吉祥寺': 'きちじょうじ',
  '下北沢': 'しもきたざわ', '恵比寿': 'えびす', '代官山': 'だいかんやま',
  '表参道': 'おもてさんどう', '赤坂': 'あかさか', '目黒': 'めぐろ',
  '五反田': 'ごたんだ', '日暮里': 'にっぽり', '巣鴨': 'すがも',
  '高田馬場': 'たかだのばば', '新橋': 'しんばし', '有楽町': 'ゆうらくちょう',
  '錦糸町': 'きんしちょう', '立川': 'たちかわ',
  '八王子': 'はちおうじ', '町田': 'まちだ', '羽田': 'はねだ',
  '成田': 'なりた', '横浜': 'よこはま', '川崎': 'かわさき',
  '鎌倉': 'かまくら', '江ノ島': 'えのしま', '湘南': 'しょうなん',
  '箱根': 'はこね', '熱海': 'あたみ', '伊豆': 'いず',
  '軽井沢': 'かるいざわ', '大宮': 'おおみや',
  // Prefectures.
  '青森': 'あおもり', '岩手': 'いわて', '宮城': 'みやぎ',
  '秋田': 'あきた', '山形': 'やまがた', '福島': 'ふくしま',
  '茨城': 'いばらき', '栃木': 'とちぎ', '群馬': 'ぐんま',
  '埼玉': 'さいたま', '千葉': 'ちば', '神奈川': 'かながわ',
  '富山': 'とやま', '石川': 'いしかわ', '福井': 'ふくい',
  '山梨': 'やまなし', '長野': 'ながの', '岐阜': 'ぎふ',
  '静岡': 'しずおか', '愛知': 'あいち',
  '滋賀': 'しが', '兵庫': 'ひょうご', '奈良': 'なら',
  '和歌山': 'わかやま', '鳥取': 'とっとり', '島根': 'しまね',
  '岡山': 'おかやま', '広島': 'ひろしま', '山口': 'やまぐち',
  '徳島': 'とくしま', '香川': 'かがわ', '愛媛': 'えひめ',
  '高知': 'こうち', '福岡': 'ふくおか', '佐賀': 'さが',
  '長崎': 'ながさき', '熊本': 'くまもと',
  '宮崎': 'みやざき', '鹿児島': 'かごしま', '沖縄': 'おきなわ',
  // Cities and quarters elsewhere.
  '札幌': 'さっぽろ', '函館': 'はこだて', '仙台': 'せんだい',
  '金沢': 'かなざわ', '博多': 'はかた', '那覇': 'なは',
  '梅田': 'うめだ', '難波': 'なんば', '心斎橋': 'しんさいばし',
  '天王寺': 'てんのうじ', '道頓堀': 'どうとんぼり', '嵐山': 'あらしやま',
  '祇園': 'ぎおん', '伏見': 'ふしみ', '宇治': 'うじ',
};
