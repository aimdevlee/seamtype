<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/logo-dark.svg">
    <img src="docs/media/logo-light.svg" width="150" alt="Seamtype: A, 아, あ">
  </picture>
</p>

<h1 align="center">Seamtype</h1>

<p align="center"><b>흐름대로 써진다 · 流れるままに · Type as it flows</b></p>

<p align="center"><a href="https://nyttastudio.com/seamtype/">웹사이트</a> · 한국어 · <a href="README.en.md">English</a></p>

모든 글을 영문(QWERTY) 자판으로 치세요. 한/영 키는 이제 누르지 않아도 됩니다.
Seamtype은 macOS 입력기로, **단어마다** 영어인지 한국어(두벌식)인지, 켜 두었다면 일본어(로마자)인지
판단해서 맞는 글자로 입력합니다.

```
Stay hungry, stay foolishsms wkqtmdml akfdlek.   →  Stay hungry, stay foolish는 잡스의 말이다.
wagahaihanekodearu␣sms thtpzldml thtjfdlek.      →  吾輩は猫である는 소세키의 소설이다.
Hello, worldhasaishonopuroguramudesu␣.           →  Hello, worldは最初のプログラムです。
```

<p align="center">
  <img src="docs/media/demo.gif" width="720" alt="입력 메뉴에서 Seamtype을 한 번 고른 뒤, 입력 소스를 다시 바꾸지 않고 Safari에 QWERTY로 치는 모습: Stay hungry, stay foolish는 잡스의 말이다. / 吾輩は猫である는 소세키의 소설이다. / Hello, worldは最初のプログラムです。">
</p>

## 만든 이유

일본에 살면서 한국어·영어·일본어를 매일 섞어 씁니다. 입력 소스가 셋이다 보니 전환 키를 누르는 일도, 엉뚱한
언어로 쳐 버리는 일도 잦았습니다. 그러다 일본어와 영어를 전환 없이 섞어 치는
[Meltype](https://github.com/yksr-melt/Meltype)에서 영감을 받아, 세 언어를 한 번에 다루는 입력기를 만들었습니다.

## 설치

[`Seamtype.pkg`](https://github.com/aimdevlee/seamtype/releases/latest/download/Seamtype.pkg)를 받아
열고 안내대로 설치하세요. Apple Silicon과 Intel 모두에서 돌아가고, Apple 공증을 받았습니다.
`/Library/Input Methods`에 설치하고 입력 소스로 등록까지 하므로, 메뉴 막대의 입력 메뉴에서 Seamtype을
고르면 됩니다.

**일본어는 기본으로 꺼져 있습니다.** 위의 예시처럼 일본어도 섞어 쓰려면 입력 메뉴에서 **일본어 입력**을 켜세요.

입력 메뉴에 Seamtype이 없으면 **시스템 설정 → 키보드 → 입력 소스 → 편집… → + → 한국어 → Seamtype**을
추가하세요. 그래도 없으면 한 번 로그아웃했다가 다시 로그인하세요.

다른 방법도 있습니다. 모두 `~/Library/Input Methods`에 설치하고, 관리자 권한이 필요 없습니다.

- 터미널에서 한 줄로:
  ```sh
  curl -fsSL https://raw.githubusercontent.com/aimdevlee/seamtype/main/scripts/get.sh | sh
  ```
- [Releases](https://github.com/aimdevlee/seamtype/releases)의 `Seamtype.zip`(공증됨)을 받아 압축을 풀고
  `~/Library/Input Methods`에 넣기
- 소스에서 빌드(Xcode 또는 Command Line Tools, Swift 6.1 이상): `scripts/install.sh`가 빌드하고 자체
  점검한 뒤 설치합니다.

pkg와 다른 방법을 함께 쓰면 같은 입력기가 두 개 생깁니다. 하나만 쓰세요.

메모리는 ~50 MB(일본어를 켜면 일본어 사전 ~35 MB 추가), 앱 크기는 ~47 MB이고, 따로 실행되는 프로그램은
없습니다. 입력한 키는 입력기 밖으로 나가지 않습니다.

### 제거

설정 창의 **정보 → Seamtype 제거 → 제거…**를 누르세요. 두 Input Methods 폴더의 Seamtype을 모두 지우고
(pkg로 설치했다면 macOS가 암호를 묻습니다), 다른 입력 소스로 바꿉니다. 설정과 학습한 단어는 확인 창에서
체크했을 때만 지웁니다.

<details>
<summary>터미널에서 지우기</summary>

입력 소스 목록에서 Seamtype을 뺀 뒤:

```sh
pkill -x Seamtype
rm -rf ~/Library/Input\ Methods/Seamtype.app
rm -rf ~/Library/Application\ Support/Seamtype   # 설정과 학습한 단어까지 지울 때만
```

pkg로 설치했다면 앱은 `/Library/Input Methods/Seamtype.app`에 있습니다. `sudo rm -rf`로 지우고,
`sudo pkgutil --forget com.aimdevlee.inputmethod.Seamtype.pkg`로 설치 기록도 지우세요.

</details>

## 키

치고 있는 단어에는 밑줄이 그어지고, Seamtype이 예상한 언어로 보입니다.

| 키 | 영어·한국어 단어 | 일본어 구절 |
| --- | --- | --- |
| 글자 | 단어를 이어서 침 | 구절을 이어서 침 (가나로 미리 보기) |
| **Esc** | 읽기 바꾸기: 영어 → 영어+조사 → 한국어 → 일본어 | 같음 |
| **⇧Esc** | 읽기 바꾸기, 모든 앱에서 (Esc를 앱에 넘기도록 한 앱에서도) | 같음 |
| Delete | 영어: 마지막 글자 지우기. 한국어: 치고 있는 글자는 자모 하나씩, 그 앞 글자는 한 글자씩 (한국 → 한구 → 한ㄱ → 한 → 지움, 시스템 두벌식과 같음) | 가나 한 글자씩 (かんこく → かんこ) |
| **Space** | 확정, 그리고 띄어쓰기 | **한자로 변환** (후보 창) |
| `, . ? !` 등 기호 | 확정, 그리고 그 키 | 구절에 붙어 전각으로: 、。？！ （）＿ 「」(`[ ]`) ・(`/`) 〜(`~`) |
| `-` | 확정, 그리고 `-` | ー |
| Return | 확정만 (줄바꿈·전송은 한 번 더 누르기, 설정에서 바꿀 수 있음) | 보이는 대로 확정: 가나, 라이브 변환이면 한자 (줄바꿈 없음) |
| ⌃K / F7, ⌃J / F6 | (앱의 단축키) | 가타카나 / 히라가나 (Space로 전환, Return으로 확정) |
| Tab, 방향키, ⌘/⌃/⌥ | 확정, 앱이 그 키를 받음 | 같음 |
| **오른쪽 ⌘** (단독으로 눌렀다 떼기) | 이 입력창에서 일시정지 / 다시 켜기 | 같음 |

일본어 다음에 따로 친 기호도 일본어 입력기처럼 전각으로 밑줄 친 채 남습니다(`！`, `＿`, `「`). Return으로 확정하고(줄바꿈 없음), Space로 다른 모양(`!`, `‼︎`, `『`…)을 고르고, 글자를 이어 치면 확정되고 새 단어가 시작됩니다. 숫자 사이(`3.5`, `10:30`)는 반각 그대로이고, 전각으로 연 괄호는 영어 단어 뒤에서도 전각으로 닫힙니다(`日本語（English）`).

변환 중(후보 창이 열려 있을 때):

| 키 | 동작 |
| --- | --- |
| Space / ↓, ↑ | 다음 / 이전 후보 |
| ←, → | 첫 문절을 줄이기 / 늘리기 (`今日は｜いいてんき`) |
| 1–9 | 그 후보로 확정 |
| Return | 고른 후보로 확정 |
| Esc / Delete | 가나로 돌아가기 |
| 글자, 문장부호 | 확정하고 이어서 치기 |

변환은 문절 단위입니다. 읽기의 앞부분만 덮는 후보(きょうはいいてんきですね의 `今日は`)를 고르면 그
부분만 확정하고 나머지를 계속 변환합니다.

### 확정한 뒤에 고치기와 학습

Space나 문장부호로 단어를 확정한 직후 **Esc**를 누르면 그 단어가 다음 읽기로 바뀌고, 더 누르면 계속
돌아갑니다(Esc를 앱에 넘기는 앱에서는 ⇧Esc). 다른 키를 하나라도 누르면 고칠 수 없습니다. 커서가 그 단어
바로 뒤에 있고 앱이 그 자리의 글자를 알려 줄 때만 되며, 아니면 키가 앱으로 갑니다.

터미널처럼 확정한 단어를 되돌릴 수 없는 앱에서는 앱별 설정에서 **Space 뒤에도 단어 유지**를 켜세요
(`apps.json`의 `holdSpace`). Space를 눌러도 단어가 공백과 함께 밑줄 상태로 남아 있다가 다음 단어의 첫
글자에서 들어가므로, 그동안 Esc(또는 ⇧Esc)로 읽기를 바꿀 수 있고 Delete는 공백만 되돌립니다. 보지 않고
Space를 눌렀다가 Delete, ⇧Esc를 눌러도 단어가 바뀝니다. Return·Tab·문장부호·단축키는 지금처럼 단어를
확정합니다. 앱이 Space 키를 받지 않으므로 그 앱에서는 텍스트 대치가 동작하지 않습니다.

한 번 고친 것은 그 단어에만 적용되므로 실수로 누른 Esc는 남지 않습니다. 같은 키를 같은 쪽으로 두 번
고치면 그때부터 기억하고, Seamtype이 처음 고른 쪽으로 되돌리면 잊습니다.

### 텍스트 대치

시스템 설정 → 키보드 → 텍스트 대치에 넣은 약어 중 한국어·일본어로 읽히는 것(`주소`, `ㅈㅅ`, `よろ`)은
판단과 상관없이 그 언어로 보여서, Space를 치면 앱이 시스템 입력기에서처럼 바꿉니다. 영어 약어는 원래대로
판단합니다. 일본어 약어는 Space를 누르면 대치할 문구가 첫 후보로 나옵니다. 바꾸는 건 앱이라, 텍스트 대치를
지원하지 않는 앱(터미널, Chrome 등)에서는 일본어 후보 말고는 바뀌지 않습니다. 목록을 고치면 다음에 입력창을
누를 때 반영됩니다. 일본어 약어는 히라가나 읽기로 넣으세요(`よろ`, `ぐー`).

### Esc를 앱이 써야 할 때

편집기에서 팝업을 닫을 때처럼 Esc가 앱에 가야 한다면, 앱별 설정에서 그 앱(또는 기본값)의 Esc 키를
"앱으로"로 바꾸세요. 단어는 보이는 대로 들어가고 앱이 Esc를 받습니다. 읽기는 ⇧Esc로 바꿉니다.

### 일시정지

터미널의 lazygit, htop처럼 키 하나하나가 명령인 곳에서는 **오른쪽 ⌘**를 단독으로 눌렀다 떼세요. 치던
단어를 확정하고, 그 입력창에서는 키를 친 그대로 넘깁니다. 한 번 더 누르거나, 다른 앱·입력창으로 가거나,
설정을 바꾸면 다시 켜집니다.

누를 때마다 입력 소스를 바꿀 때처럼 커서 아래에 Seamtype 아이콘이 잠깐 뜹니다. 일시정지하면 빗금이
쳐져 있습니다. 메뉴 막대 아이콘은 바뀌지 않으므로, 나중에 확인하려면 입력 메뉴의 체크 표시를 보세요. 이
키는 설정 창의 일반에서 끌 수 있습니다.

### vim

neovim은 [`scripts/vim/seamtype.lua`](scripts/vim/seamtype.lua)를 `~/.config/nvim/plugin/`에,
Vim(8.2 이상, `+job`)은 [`scripts/vim/seamtype.vim`](scripts/vim/seamtype.vim)을 `~/.vim/plugin/`에
넣으세요. vim이 모드가 바뀔 때마다 Seamtype에 알려 주므로, 입력 모드에서만 단어를 판단하고 노멀·비주얼·
명령줄 모드에서는 키를 바로 vim에 보냅니다. `s`, `dd`, `ciw`, `:wq⏎`가 키마다 바로 실행됩니다. vim
안에서는 Esc가 늘 vim으로 가므로 앱별 설정은 필요 없고, vim을 끝내면 셸에서 다시 단어를 판단합니다.

<details>
<summary>동작 방식과 주의할 점</summary>

- 신호는 `Seamtype --vim insert|normal|off --app <번들 ID>`입니다. 키마다가 아니라 모드가 바뀔 때(입력
  모드 들어가기·나오기, 시작, 끝, 포커스)만 보냅니다.
- 번들 ID는 macOS가 앱마다 넣어 주는 `$__CFBundleIdentifier`라서 터미널(Ghostty, Terminal, iTerm2,
  VS Code 등)마다 따로 설정할 것이 없고, 신호는 그 앱의 입력창에만 갑니다. `--app` 없는 신호는 Esc를
  앱으로 보내는 앱에서만 받습니다.
- tmux 서버를 띄운 터미널과 다른 터미널에서 붙으면 번들 ID가 달라 신호가 무시됩니다.
- Vim이 터미널의 포커스 변화를 모르면, vim 패널에서 셸 패널로 옮겨도 Seamtype은 알 수 없습니다. 그럴
  때는 ⇧Esc를 누르면 다시 단어를 판단합니다.

</details>

## 설정

입력 메뉴(Seamtype을 고른 상태의 메뉴 막대)에서 할 수 있는 것:
- 이 입력창에서 일시정지(오른쪽 ⌘와 같음)
- 지금 앞에 있는 앱의 단어 변환 켜고 끄기, 그 앱의 변환 기준(보통·엄격하게), Esc 키(앱으로), Space 뒤에도 단어 유지 정하기, 그
  앱을 기본 설정으로 되돌리기. 단어 변환이 꺼져 있으면 변환 기준과 Esc 키는 흐리게 나옵니다
- 일본어 입력과 라이브 변환 켜고 끄기
- 마지막으로 학습한 단어 되돌리기, 입력해 보기, 기억한 단어, 설정 창 열기

설정 창에는 일반, 입력해 보기(단어마다 어떻게 판단했는지와 점수), 앱별 동작, 학습한 단어(하나씩 또는
전부 잊기), 정보가 있습니다. 한자 후보 순서 초기화는 일본어 항목 아래에 있습니다. 바꾼 내용은 바로
적용됩니다.

### 설정 파일

메뉴와 설정 창 모두 `~/Library/Application Support/Seamtype/settings.json`에 씁니다. 직접 고쳐도 되고,
없는 항목은 기본값을 따릅니다.

```json
{ "japanese": true, "liveConversion": true }
```

| 항목 | 기본값 | 내용 |
| --- | --- | --- |
| `japanese` | **꺼짐** | 로마자 일본어를 알아보고 변환합니다. |
| `liveConversion` | 꺼짐 | 일본어 구절을 치는 동안 가장 앞선 한자 후보를 보여 주고(`今日はいい天気でs`), Return을 누르면 보이는 대로 확정합니다. macOS의 실시간 변환과 같습니다. |
| `returnConfirmsOnly` | 켜짐 | 밑줄 친 단어에서 누른 Return은 확정만 합니다. 끄면 앱도 그 Return을 받습니다(일본어 구절은 그대로 확정만). |
| `rightCommandPause` | 켜짐 | 오른쪽 ⌘를 단독으로 눌러 일시정지합니다([일시정지](#일시정지) 참고). |

라이브 변환에서 Space는 다음 후보부터 후보 창을 열고, Esc는 가나를 보여 줍니다(한 번 더 누르면 언어를
바꿉니다). 짧은 읽기는 한자로만 바뀝니다(`と`는 그대로, `私`는 변환). 맨 앞 후보는 짧은 구절 5개 중 4개,
문장 전체 3개 중 2개꼴로 맞으니([평가 결과](#평가-결과-학습에-쓰지-않은-데이터)) Return 전에 한번
확인하세요. 변환은 키마다 8–21 ms 걸립니다.

앱별 동작은 같은 폴더의 `apps.json`에 있습니다. `"*"`는 모든 앱의 기본값이고, 앱(번들 ID, `.`으로 끝나는
키는 앞부분이 같은 앱 전부)에는 기본값과 다른 항목만 적습니다. 직접 넣지 않으면 어떤 앱도 들어 있지
않습니다.

```json
{ "*":                     { "escapeToApp": true },
  "com.apple.Terminal":    { "conversionThreshold": 0.97 },
  "com.example.Game":      { "enabled": false } }
```

| 항목 | 기본값 | 내용 |
| --- | --- | --- |
| `enabled` | `true` | `false`면 모든 키를 그대로 넘깁니다(영어만 입력). |
| `conversionThreshold` | `0.5` | 이만큼 확신할 때만 친 영문을 다른 글자로 바꿉니다. `0.97`(엄격하게)은 터미널에서 짧은 셸 명령이 한글로 바뀌지 않게 하고, `0.5`는 글을 쓸 때 한국어를 더 많이 바꿉니다. |
| `escapeToApp` | `false` | Esc는 앱으로 가고, ⇧Esc로 읽기를 바꿉니다(편집기용). |
| `holdSpace` | `false` | Space를 눌러도 단어를 확정하지 않고 공백과 함께 밑줄 상태로 두었다가, 다음 단어의 첫 글자에서 들어갑니다. 그동안 Esc로 읽기를 바꿀 수 있고 Delete는 공백만 되돌립니다. 확정한 단어를 고칠 수 없는 터미널용이며, 앱이 Space 키를 받지 않아 텍스트 대치는 동작하지 않습니다. |

파일을 직접 고친 뒤에는 입력기를 다시 시작하세요: `pkill -x Seamtype`.

## 판단 방식

모두 이 Mac 안에서, 아래 순서로 판단합니다. 키 하나의 미리 보기는 길어야 ~3 ms, 단어 하나의 최종 판단은
~7 ms이고, 구절이 70글자가 되어도 비슷합니다.

1. **사용자가 고친 것**(두 번 고친 것, [학습](#확정한-뒤에-고치기와-학습) 참고)이 항상 먼저입니다
   (`lexicon.json`).
2. **섞인 단어**를 나눕니다. 변환 기준이 엄격하게인 앱에서도 나눕니다.
   - 영어 + 조사: 앞이 영어로 보이고(또는 대문자로 쳤고) 끝이 한국어 조사·어미일 때.
     `githubdp` → `github에`, `UIrkxdmsrjs` → `UI같은건`
   - 영어 한 글자 + 조사(변수 이름 등): `xdp` → `x에`, `Xfmf` → `X를`. 소문자 뒤의 `도`·`나`는 영어에
     흔한 끝(`heh`, `tsk`)이라 나누지 않습니다(대문자는 `X도`).
   - 영어 + 한국어 단어: 앞이 아는 영어 단어(또는 대문자로 친 이름)이고 뒤가 한국어 단어 목록에 있을 때.
     전체가 영어와 전혀 닮지 않았으면 흔한 음절로 된 한글도 나눕니다. `hellodnjfem` → `hello월드`,
     `githubtjqj` → `github서버`
   - 한국어 뒤에 붙인 영어 단어: `dhsmfdmsgoogledptj` → `오늘은google에서`. 한국어 부분을 먼저 확정하고
     나머지를 이어서 칩니다.
   - 일본어를 켰을 때:
     - 아는 영어 단어 + 격조사 하나: `githubde` → `githubで`
     - 한국어 뒤에 붙인 일본어: `dlfurrireki` → `이력りれき`(Space로 `履歴`)
     - 일본어 뒤에 붙인 한국어 조사나 단어: `rirekifmf` → `りれき를`, `kyouhaehtlfkrdms` → `きょうは도시락은`.
       일본어 부분은 그 자리에서 확정되므로, 라이브 변환을 켜면 `履歴를`, `今日は도시락은`처럼 한자로
       들어갑니다.
     - 한국어 쪽이 깨지는 키일 때만 나누므로, 평소 일본어 문장은 자르지 않습니다.
3. **규칙:** 쌍자음이 없는 글자에 Shift를 누르면(`Hello`, `API`) 영어입니다.
4. **휴리스틱:** 키를 키 하나당 점수로 매겨 세 언어를 비교하고, 앞 단어의 언어 쪽으로 조금 기울입니다.
   - 영어: 글자 3-그램, 그리고 SCOWL 목록에 있는 단어는 얼마나 흔한지에 따른 하한 점수
   - 한국어: 두벌식 음절 빈도, 그리고 한국어 글에 나온 단어의 하한 점수
   - 일본어: 로마자 → 가나 3-그램. 구절 안의 영어 단어는 따로 떼어 냅니다.
   - 키가 앞 단어의 언어가 아닌 다른 언어의 단어라면 언어를 바꿔 치는 경우이므로, 앞 단어 쪽으로
     기울이는 정도를 줄입니다.
   - 아는 영어 단어는 일본어가 분명히 이길 때만 가나로 바뀝니다.

한자는 [AzooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter)의 사전 변환기에서 나오고,
일본어 문어 글자 3-그램 모델로 순서를 다시 매깁니다. AzooKey는 사용자가 고른 후보도 학습합니다.

### 평가 결과 (학습에 쓰지 않은 데이터)

모델을 만들 때 한 번도 쓰지 않은 문장에서 뽑은 영어 단어 2,011개, 한국어 단어 1,987개, 일본어 구절
2,000개입니다(`tools/prepare.sh`).

| | 일본어 끔 (영/한) | 일본어 켬 (영/한/일) |
| --- | --- | --- |
| 정확도 | 99.80% | 99.48% |

이 데이터는 단어를 한 번씩만 세고, 다른 언어 뒤에 오는 경우가 드뭅니다. 하지만 실제 글은 대부분 흔한
단어로 이루어지고, 문장 중간에 언어를 바꾸는 것이 이 입력기의 핵심입니다. 그래서 가장 흔한 영어·한국어
단어 10,000개를 각 언어의 단어 뒤에 두고도 쟀습니다(`tools/eval_context.py`, 일본어 켬). 아래는 상위
1,000개 / 상위 10,000개 가운데 틀린 수입니다.

| | 앞에 아무것도 없을 때 | 같은 언어 뒤 | 다른 언어 뒤 | 일본어 뒤 |
| --- | --- | --- | --- | --- |
| 한국어 단어 | 9 / 42 | 2 / 16 | 16 / 159 | 9 / 46 |
| 영어 단어 | 2 / 47 | 0 / 21 | 8 / 71 | 2 / 86 |

SCOWL 목록, 한국어 단어 목록, 언어 전환을 고려한 기울기를 넣기 전에는 모두 합쳐 94 / 785였고, 지금은
48 / 488입니다. 이 목록은 규칙을 다듬을 때 썼으므로 참고용 점수입니다. 남은 오답 중 상당수는 키 자체가
정말로 애매한 경우입니다: `so`/내, `go`/해, `did`/양.

한자 변환에서 맨 앞 후보가 원문과 정확히 같은 비율입니다(학습에 쓰지 않은 Tatoeba 문장).

| | AzooKey만 | + 순서 재조정 | 후보 목록 안에 정답 |
| --- | --- | --- | --- |
| 2–3단어 구절 | 69.5% | **81.0%** | 96.2% |
| 문장 전체 | 56.0% | **66.0%** | 82.2% |

정확히 같아야 맞은 것으로 세므로, 가나·한자 표기 차이(ひとまとめ와 一まとめ)도 틀린 것으로 칩니다.

## 알려진 한계

- 모든 앱에서 처음부터 끝까지 시험해 보지는 않았습니다. 보안 입력란(비밀번호)은 입력기를 거치지 않고,
  확정한 뒤에 고치기는 커서 위치와 글자를 알려 주는 앱에서만 됩니다. 터미널에서는 `"holdSpace": true`로
  Space 뒤에도 단어를 밑줄 상태로 두세요.
- Esc를 앱에 넘기지 않는 앱에서는, 단어 바로 뒤에 누른 Esc(예: 팝업 닫기)가 먼저 그 단어를 바꿉니다.
  반복하지 않으면 학습하지는 않습니다. 그런 앱은 `"escapeToApp": true`로 등록하세요.
- 일본어: ←/→로는 첫 문절만 크기를 바꿀 수 있습니다(Return으로 확정하면 나머지로 넘어갑니다). 드문
  단어는 여전히 후보 목록에서 골라야 합니다.

## 개발

```sh
swift test                     # 테스트: 조합기, 엔진, 세션, 설정, 처음부터 끝까지
scripts/install.sh             # 빌드하고 자체 점검한 뒤 ~/Library/Input Methods에 설치
scripts/typing-test/run.sh     # 설치된 Seamtype으로 TextEdit에 실제 키 입력
swift scripts/make-readme-logo.swift docs/media  # README 로고(애니메이션 SVG)
scripts/release.sh             # 릴리스용 범용(arm64 + x86_64) zip과 pkg; Developer ID가 있으면 서명·공증(앱과 pkg 모두)
tools/prepare.sh               # 정확도 (단어 목록, Tatoeba, SCOWL을 처음 한 번 내려받음)
tools/prepare.sh --models      # 먼저 Sources/SeamtypeCore/Data의 데이터를 다시 만듦(korean_vocabulary.txt 빼고)
SEAMTYPE_TIMING=1 swift run -c release seamtype-cli --decide --japanese < keys.tsv  # + 판단당 시간
swift run seamtype-cli -v "dkssud gksrmf hello"               # 영어/한국어, 점수와 함께
printf 'kyouhagoogledekensaku\t\n' | swift run seamtype-cli --decide --japanese
printf 'きょうはいいてんきですね\n' | swift run seamtype-cli --convert
```

| 경로 | 내용 |
| --- | --- |
| `Sources/SeamtypeCore` | 조합기, 엔진, 변환, `InputSession` (입력 로직 전부) |
| `Sources/Seamtype` | InputMethodKit 서버, `InputSession` 위의 얇은 컨트롤러, 후보 창, 설정 창 |
| `Sources/SeamtypeCore/Data` | 가나·일본어 문어 3-그램, 한국어 음절과 단어, 영어 단어 |
| `tools/` | 말뭉치 → 로마자, 모델 생성, 평가 데이터와 정확도 (python3, 추가 패키지 없음) |

## 라이선스와 데이터

Seamtype은 MIT 라이선스입니다([LICENSE](LICENSE)). 앱에 컴파일되거나 복사된 모든 것의 라이선스는
`Contents/Resources/ThirdPartyNotices.txt`에 들어 있고, `scripts/build-app.sh`가 모읍니다.

- AzooKey Kana-Kanji Converter: MIT, 사전: Apache-2.0.
- Tatoeba 문장(가나·일본어 문어 모델, 한국어 음절·단어 빈도, 평가): CC-BY 2.0 FR, https://tatoeba.org.
- 영어 단어와 빈도: [SCOWL](http://wordlist.aspell.net) (자유 라이선스, 고지는 앱에 포함).
  macOS의 `/usr/share/dict/words`로 실행할 때 글자 3-그램을 학습합니다.
- 영어·한국어 빈도 목록:
  [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords), CC-BY-SA 4.0.
  평가에 쓰고, 한국어 목록은 영어 + 한국어 단어 나누기용 `korean_vocabulary.txt`로도 같은 라이선스로
  앱에 들어갑니다(고지는 앱에 포함).
