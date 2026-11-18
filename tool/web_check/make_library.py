# A made-up library for the web tests: N small vertical Japanese EPUBs with
# covers (drawn here), the rows the account would list, and each book's
# small cover. One book is padded to several MB so its download shows.
import sys, os, io, json, zipfile, hashlib, random, colorsys
from PIL import Image, ImageDraw, ImageFont
out = sys.argv[1]; n = int(sys.argv[2])
os.makedirs(f'{out}/files', exist_ok=True)
random.seed(7)
serif = '/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc'
titles = ['春の駅', '月影の図書館', '星を拾う少年', '雨上がりの約束', '白い猫と時計塔', '最果ての灯台守', '硝子の森の魔女', '夜明け前の航路',
          '風待ちの丘', '銀色の手紙', '眠れる竜の庭', '七番目の扉', '夏空と自転車', '雪国の調律師', '砂時計の王女', '迷子の郵便屋',
          '海辺の古書店', '黄昏の天文台', '錆びた歯車の歌', '青い鳥の地図', '紅茶と幽霊', '路地裏の錬金術師', '千の夜の語り部', '灯りを運ぶ人',
          '霧の町の探偵', '花降る国の旅人', '機械仕掛けの春', '氷の城の司書']
authors = ['水無月 蒼', '桐谷 灯', '秋津 遥', '白崎 凛', '真柴 朔', '羽鳥 澪']
paras = ['春の朝、少女は駅のホームで電車を待っていた。', '「今日こそ、あの人に話しかけるんだ」と彼女は小さく呟いた。',
         '風が吹いて、桜の花びらが線路の上に舞い落ちる。', 'やがて電車が来て、扉が開いた。', '彼女は深呼吸をして、一歩を踏み出した。']
def cover(title, author, i):
    w, h = 1200, 1700
    hue = (i * 0.137) % 1
    a = tuple(int(c * 255) for c in colorsys.hls_to_rgb(hue, 0.30, 0.55))
    b = tuple(int(c * 255) for c in colorsys.hls_to_rgb((hue + 0.08) % 1, 0.62, 0.50))
    im = Image.new('RGB', (w, h)); px = im.load()
    for y in range(h):
        t = y / h
        row = tuple(int(a[k] * (1 - t) + b[k] * t) for k in range(3))
        for x in range(w): px[x, y] = row
    d = ImageDraw.Draw(im)
    for _ in range(26):
        x, y, r = random.randint(0, w), random.randint(0, h), random.randint(30, 220)
        d.ellipse([x - r, y - r, x + r, y + r], outline=(255, 255, 255), width=3)
    f = ImageFont.truetype(serif, 150); y = 240
    for ch in title[:8]:
        d.text((w - 330, y), ch, font=f, fill=(255, 255, 255)); y += 168
    d.text((120, h - 220), author, font=ImageFont.truetype(serif, 64), fill=(255, 255, 255))
    buf = io.BytesIO(); im.save(buf, 'JPEG', quality=88)
    small = im.resize((600, 850), Image.LANCZOS); sb = io.BytesIO(); small.save(sb, 'JPEG', quality=82)
    return buf.getvalue(), sb.getvalue()
rows = []
for i in range(n):
    title = titles[i % len(titles)] + ('' if i < len(titles) else f' {i // len(titles) + 1}')
    author = authors[i % len(authors)]
    full, small = cover(title, author, i)
    body = '\n'.join(f'<p>{p}</p>' for p in paras * (6 + i % 5))
    chap = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ja">
<head><title>第一章</title><style>html {{ writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }}</style></head>
<body><h1>第一章 {title}</h1>
{body}
</body></html>'''
    desc = f'{title}。{author}が描く、静かな町の小さな奇跡の物語。' * (1 + i % 4)
    opf = f'''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid" xml:lang="ja">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="uid">urn:uuid:5b1d1f2e-0000-4000-8000-{i:012d}</dc:identifier>
<dc:title>{title}</dc:title><dc:creator>{author}</dc:creator><dc:language>ja</dc:language>
<dc:publisher>テスト文庫</dc:publisher><dc:description>{desc}</dc:description>
<meta property="dcterms:modified">2026-11-09T00:00:00Z</meta>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
{'<item id="pad" href="pad.bin" media-type="application/octet-stream"/>' if i == 3 else ''}
</manifest>
<spine page-progression-direction="rtl"><itemref idref="c1"/></spine>
</package>'''
    nav = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目次</title></head>
<body><nav epub:type="toc"><ol><li><a href="c1.xhtml">第一章 {title}</a></li></ol></nav></body></html>'''
    container = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'''
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w') as z:
        z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        z.writestr('META-INF/container.xml', container, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('OEBPS/content.opf', opf, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('OEBPS/nav.xhtml', nav, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('OEBPS/c1.xhtml', chap, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('OEBPS/cover.jpg', full, compress_type=zipfile.ZIP_STORED)
        if i == 3: z.writestr('OEBPS/pad.bin', random.randbytes(7 * 1024 * 1024), compress_type=zipfile.ZIP_STORED)
    data = buf.getvalue(); md5 = hashlib.md5(data).hexdigest()
    open(f'{out}/files/{md5}.epub', 'wb').write(data)
    has_cover = i % 11 != 9
    if has_cover: open(f'{out}/files/{md5}.cover.jpg', 'wb').write(small)
    rows.append({'md5': md5, 'book_id': f'local_{md5}', 'file_name': f'{title}_{md5[:6]}.epub', 'title': title, 'author': author,
                 'format': 'epub', 'size_bytes': len(data), 'has_file': True, 'deleted_at': None, 'publisher': 'テスト文庫',
                 'description': desc, 'cover_at': '2026-11-10T00:00:00+00:00' if has_cover else None,
                 'added_at': f'2026-11-{1 + i % 9:02d}T0{i % 9}:00:00+00:00'})
progress = []
for i, frac in [(0, 0.42), (3, 0.08), (5, 1.0), (8, 0.77)]:
    if i < n:
        progress.append({'md5': rows[i]['md5'], 'position': '', 'completed': frac >= 1, 'fraction': frac,
                         'updated_at': f'2026-11-10T1{i}:00:00+00:00'})
translations = [{'md5': rows[i]['md5'], 'lang': 'ko', 'style': 'shared', 'entry_count': c, 'updated_at': '2026-11-10T09:00:00+00:00', 'entries': {}}
                for i, c in [(0, 1234), (8, 87)] if i < n]
json.dump({'books': rows, 'progress': progress, 'translations': translations}, open(f'{out}/library.json', 'w'), ensure_ascii=False, indent=1)
print(n, 'books', sum(r['size_bytes'] for r in rows) // 1024, 'KB')
