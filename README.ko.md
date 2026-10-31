<div align="center">

<img src="assets/icons/appIcon.png" width="150">

# LightLib

**일본 라이트노벨을 위한 안드로이드 전자책 서재·리더 <br/> 책 본래의 조판 그대로, 읽으면서 번역하고, 어디까지 읽었는지 기억합니다.**

[English](README.md) | **한국어**

[![made-with-flutter](https://img.shields.io/badge/Made%20with-Flutter-FF6B9D.svg?style=for-the-badge)](https://flutter.dev/)
[![AGPLv3 License](https://img.shields.io/badge/License-AGPL%20v3-e63946.svg?style=for-the-badge)](https://www.gnu.org/licenses/agpl-3.0.html)
[![Latest release](https://img.shields.io/github/release/4rNe5/LightLib.svg?style=for-the-badge)](https://github.com/4rNe5/LightLib/releases/latest)

[<img src="github_releases.png"
     alt="GitHub에서 받기"
     height="110">](https://github.com/4rNe5/LightLib/releases/latest)

**[📖 자주 묻는 질문](./FAQ.ko.md)**
</div>

## 기능 ✨

### 읽기
- **책을 만든 그대로 보여주는 리더** — [foliate-js](https://github.com/johnfactotum/foliate-js) 기반. 책 본래의 조판·삽화·표지, 세로쓰기(縦書き)와 가로쓰기, 루비(후리가나), 페이지 넘김과 스크롤. 글꼴·크기·간격·테마를 한국어·일본어·라틴 문자별로 따로 정할 수 있고, 스타일은 [Readest](https://github.com/readest/readest)를 따릅니다.
- **폴더블·태블릿** — 화면이 넓어지면 표지 그리드의 열이 늘어나고, 펼친 화면에서도 하단 탭바는 휴대폰 크기를 유지합니다.

### 번역
- **읽으면서 번역** — 일본어 책을 열면 한국어(또는 14개 언어 중 하나)로 문단마다 번역됩니다. 한국어용으로 다듬은 라노벨 문체: 과거형 서술, 캐릭터마다의 존댓말·반말, 책이 읽는 대로의 이름.
- **엔진은 둘, 번역은 하나** — 휴대폰 안에서 Gemma 4로([LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) GPU, 또는 [llamadart](https://pub.dev/packages/llamadart)의 llama.cpp로 GGUF 모델), 혹은 **Google Gemini**로 한 권을 몇 분 만에. 두 엔진이 같은 번역에 이어서 쓰기 때문에 언제든 바꿔도 이어집니다.
- **책마다 용어집** — 등장인물·성별·지명·용어를 책 본문과 루비에서 한 번 모아 두고, 직접 고칠 수 있으며, 모든 페이지에서 똑같이 씁니다.
- **보여주기 전에 검사** — 일본어가 남았거나, 같은 말을 반복하거나, 문장을 빠뜨리거나, 이름이 틀렸거나, 존댓말이 반말로 바뀐 번역은 문제를 알려 주고 한 번 더 받아 더 나은 쪽을 씁니다.
- **이 책 끝까지 번역** — 책 화면에서 한 번 누르면 그 책을 먼저, 끝까지 번역합니다. 앱을 켜 두면 최대 속도로, 백그라운드에서는 무리하지 않게. 읽으려고 앉았을 땐 이미 준비돼 있습니다.
- **백그라운드 번역** — 원하면 나머지 서재도 조금씩 번역합니다. 휴대폰이 따뜻해지면 속도를 낮추고 배터리가 부족하면 쉬며, 진행 상황은 알림창에 보입니다.
- **번역본 EPUB** — 번역이 들어간 일반 EPUB으로 내보내 보관하거나 다른 리더 앱에서 열 수 있습니다. 가로쓰기, 번역 언어로 설정돼 나옵니다.

### Gemini를 쓴다면
[Google AI Studio](https://aistudio.google.com/apikey)에서 받은 본인 키를 넣고 모델을 고르면 됩니다(무료 등급으로 하루 여러 권). 설정에서 오늘 사용량과 한도·초기화 시각·유료 기준 비용을 볼 수 있고, 생각 비중(속도·균형·퀄리티)과 안전 필터를 정할 수 있습니다. 필터는 기본으로 꺼져 있어 15세·성인 등급 책도 끝까지 번역됩니다. 하루 한도를 다 쓰거나 번역이 안 되는 문단은 휴대폰 모델이 이어 받습니다.

### 서재
- **내 책을 한눈에** — 책에서 읽어 온 고화질 표지, 읽기 상태, 태그와 장르, 검색과 필터, 그리고 독서 기록: 체크포인트, 연속 독서일, 4주간 활동, 이달의 기록과 장르 구성.
- **표지 가리기** — 책마다 골라서 서재·책 화면·위젯에서 가릴 수 있습니다.
- **둘러보기** — 지금 BOOK☆WALKER에서 잘 팔리는 라노벨·웹소설 출간작·만화와 장르별 목록, 영미권 인기작.
- **홈 화면 위젯** — *이어 읽기*와 *독서 기록*, 1×1부터 큰 크기까지, 접어도 펼쳐도 크기에 맞게.

### 그리고
- **이 저장소에서 바로 업데이트** — 앱이 최신 릴리즈를 확인해 Wi-Fi로 받고(SHA-256 검증), 바뀐 점을 보여준 뒤 한 번에 설치합니다.
- **6개 언어** — English, 한국어, 日本語, Deutsch, Español, Français.

## 내 데이터 🔒

서재, 읽던 위치, 용어집, 번역은 휴대폰(과 백업)에 남습니다. 휴대폰 안에서 번역하면 모든 게 그대로 기기 안에 머뭅니다. Gemini를 고르면 번역 중인 문단이 본인 키로 Google에 전달되는데, Gemini를 쓰는 앱이라면 모두 같은 방식입니다. Google 무료 등급에서는 서비스 개선에 쓰일 수 있고, 유료 키에서는 쓰이지 않습니다. 키는 이 기기에만 보관되고 백업에는 들어가지 않습니다.

## 스크린샷 🖼️

[<img src="screenshots/library.jpg" width=180 alt="내 서재">](screenshots/library.jpg)
[<img src="screenshots/reader.jpg" width=180 alt="세로쓰기 리더">](screenshots/reader.jpg)
[<img src="screenshots/search.jpg" width=180 alt="검색">](screenshots/search.jpg)
[<img src="screenshots/settings.jpg" width=180 alt="설정">](screenshots/settings.jpg)

## 설치 📦

[최신 릴리즈](https://github.com/4rNe5/LightLib/releases/latest)에서 `LightLib-<버전>-build.<n>-arm64.apk`를 받아 설치하세요. 릴리즈마다 바뀐 점과 APK의 SHA-256이 적혀 있습니다.

- **안드로이드, arm64** (최근 몇 년 사이의 64비트 휴대폰).
- 모든 릴리즈가 같은 키로 서명되어 새 빌드가 기존 앱 위에 설치되고 서재가 유지됩니다. 처음 설치한 뒤에는 앱에서 업데이트됩니다.
- 휴대폰에서 번역하려면 *설정 → 기기 내 번역*에서 모델(Gemma 4 E2B 또는 E4B)을 받으세요. Gemini로 번역하려면 같은 곳에서 키를 넣으면 됩니다.

## 개발 🛠️

Flutter 3.47 (Dart 3.13).

```bash
git clone https://github.com/4rNe5/LightLib.git
cd LightLib
flutter pub get
flutter run
```

- 리더의 웹 부분은 `reader_web/`에 있고 `assets/reader/`로 빌드됩니다(`reader_web/README.md` 참고).
- `main`에 마크다운 외 변경을 푸시하면 `.github/workflows/android-release.yml`이 테스트·서명된 arm64 빌드·`v<버전>-build.<n>` 릴리즈를 만듭니다.
- 첫 빌드는 [SETUP.md](SETUP.md), 기여 안내는 [CONTRIBUTING.md](CONTRIBUTING.md)를 보세요.

## 크레딧 🙏

- [Openlib](https://github.com/dstark5/Openlib)(dstark5)과 그 포크 [OpenlibExtended](https://github.com/warreth/OpenlibExtended)(warreth)를 바탕으로 만들었습니다.
- 리더: [foliate-js](https://github.com/johnfactotum/foliate-js) (MIT), [Readest](https://github.com/readest/readest) (AGPL-3.0).
- 번역: [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM), [llamadart](https://pub.dev/packages/llamadart), [Gemma](https://ai.google.dev/gemma) 모델, [Gemini API](https://ai.google.dev/gemini-api).
- 용어집과 품질 검사의 접근 방식: [Glossarion](https://github.com/Shirochi-stack/Glossarion) (AGPL-3.0).

## 라이선스 📜

[AGPL v3.0](https://www.gnu.org/licenses/agpl-3.0.html).

## 고지 ⚠️

LightLib은 앱에서 볼 수 있는 책을 소유하거나 그와 관련이 있지 않습니다. 모든 책은 각 권리자의 소유이며 저작권법의 보호를 받습니다. LightLib은 앱에서 볼 수 있는 책의 이용으로 생길 수 있는 저작권 등 지식재산권 침해에 책임지지 않습니다. 앱을 사용함으로써 책을 개인적·비상업적 목적으로, 관련 법령을 지키며 이용하는 데 동의하는 것으로 봅니다. 이 앱을 Play 스토어에 올리는 것은 스토어 약관 위반입니다.
