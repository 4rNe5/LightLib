# A small vertical Japanese EPUB 3 for the web E2E test.
import sys, zipfile
out = sys.argv[1]
paras = [
 '春の朝、少女は駅のホームで電車を待っていた。',
 '「今日こそ、あの人に話しかけるんだ」と彼女は小さく呟いた。',
 '風が吹いて、桜の花びらが線路の上に舞い落ちる。',
 'やがて電車が来て、扉が開いた。',
 '彼女は深呼吸をして、一歩を踏み出した。',
] * 6
body = '\n'.join(f'<p>{p}</p>' for p in paras)
chap = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ja">
<head><title>第一章</title><style>html {{ writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }}</style></head>
<body><h1>第一章 春の駅</h1>
{body}
</body></html>'''
opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid" xml:lang="ja">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="uid">urn:uuid:5b1d1f2e-0000-4000-8000-lightlibtest</dc:identifier>
<dc:title>春の駅(テスト)</dc:title><dc:creator>テスト作者</dc:creator><dc:language>ja</dc:language>
<meta property="dcterms:modified">2026-11-09T00:00:00Z</meta>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
</manifest>
<spine page-progression-direction="rtl"><itemref idref="c1"/></spine>
</package>'''
nav = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目次</title></head>
<body><nav epub:type="toc"><ol><li><a href="c1.xhtml">第一章 春の駅</a></li></ol></nav></body></html>'''
container = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'''
with zipfile.ZipFile(out, 'w') as z:
    z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml', container, compress_type=zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/content.opf', opf, compress_type=zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/nav.xhtml', nav, compress_type=zipfile.ZIP_DEFLATED)
    z.writestr('OEBPS/c1.xhtml', chap, compress_type=zipfile.ZIP_DEFLATED)
print(out)
