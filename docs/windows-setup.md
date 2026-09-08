# Windows에서 설치하기

> 개발자가 아니어도 따라 할 수 있도록, 클릭·복붙 단위로 적었습니다.
> 5분 정도면 끝납니다.

## 한 줄 요약

**Windows에서 이 플러그인을 제대로 쓰려면 준비물이 하나 있습니다 — Git for Windows.**
이게 없으면 플러그인의 자동 안내·자동 검증 기능(세션 시작 브리핑, 빌드 안 하고 끝내면
막아주는 기능 등)이 **에러 메시지 하나 없이 조용히 전혀 작동하지 않습니다.** "설치는
됐는데 뭔가 이상하다"의 가장 흔한 원인이 이것입니다.

Mac이나 Linux를 쓰신다면 이 문서는 필요 없습니다 — 그냥 [README](../README.md)의
Quick Start로 가시면 됩니다.

---

## 나는 어디에 해당하나요?

아래 중 하나를 고르세요.

| 나는... | 해야 할 일 |
| --- | --- |
| Windows는 처음 써보고, "WSL"이 뭔지도 모른다 | **방법 A**로 진행 (Git for Windows 설치) |
| 이미 개발 관련 프로그램(Git, VS Code 등)을 좀 써봤다 | **방법 A**로 진행 — 가장 간단하고 흔한 방법 |
| 이미 WSL(리눅스 환경)을 설치해서 쓰고 있다 | **방법 B**로 진행 — 지금 하시는 그대로 쓰시면 됩니다 |

둘 중 뭘 골라야 할지 모르겠으면 **방법 A**를 고르세요. 대부분의 Windows 사용자에게
맞는 선택입니다.

---

## 방법 A — Git for Windows 설치 (권장)

### 1단계. 다운로드

1. 브라우저에서 https://git-scm.com/downloads/win 접속
2. **"Click here to download"** 버튼 클릭 (자동으로 64-bit 버전이 받아집니다)
3. 다운로드된 `Git-x.xx.x-64-bit.exe` 파일 실행

### 2단계. 설치

설치 마법사가 여러 화면을 보여줍니다. **모든 화면에서 기본값 그대로 두고 "Next"만
누르면 됩니다.** 딱히 바꿀 것이 없습니다. 마지막에 "Install" → 설치 완료 후 "Finish".

> 화면이 10개 가까이 나와서 당황할 수 있는데, 전부 기본 설정을 그대로 써도 이 플러그인
> 사용에는 문제없습니다. 정확히 뭘 하는 도구인지 알고 싶다면 나중에 찾아봐도 늦지 않습니다.

### 3단계. 확인

1. 윈도우 시작 메뉴에서 **"Git Bash"** 를 검색해 실행 — 검은 배경의 터미널 창이 뜹니다
2. 아래 명령을 입력하고 Enter (마우스로 복사 → 창에서 우클릭 → 붙여넣기)

```bash
bash --version
```

3. `GNU bash, version ...` 같은 글자가 나오면 성공입니다. `command not found` 같은
   에러가 나오면 설치가 안 된 것이니 2단계를 다시 확인하세요.

---

## jq 설치 (방법 A / B 공통 — 필수)

Git for Windows에는 터미널(`bash`)과 기본 명령어들은 들어있지만, 이 플러그인이 쓰는
**`jq`(JSON을 다루는 도구)는 따로 설치해야 합니다.** (`jq`가 정확히 뭘 하는 도구인지는
[하네스 지도 Q&A](../README.md)에서 다뤘던 내용과 같습니다 — 없어도 설치는 되지만,
플러그인의 안전장치 절반이 조용히 꺼집니다.)

가장 쉬운 방법 — Git Bash 말고 **일반 PowerShell**(시작 메뉴에서 "PowerShell" 검색)을
열어서:

```powershell
winget install jqlang.jq
```

Windows 10(2021년 이후 업데이트) 이상이면 `winget`이 이미 깔려 있어서 이 한 줄이면
끝납니다. `winget`이 없다는 에러가 나오면, 아래 대안을 쓰세요:

1. https://jqlang.org/download/ 접속
2. **Windows** 항목의 `jq-windows-amd64.exe` 다운로드
3. 파일 이름을 `jq.exe`로 바꾸고, `C:\Windows\System32\` 폴더에 복사
   (복사 시 "관리자 권한이 필요합니다" 창이 뜨면 "계속" 클릭)

### 확인

Git Bash 창에서:

```bash
jq --version
```

`jq-1.x.x` 같은 버전이 나오면 성공입니다.

---

## 방법 B — WSL 사용 (이미 WSL을 쓰고 있다면)

이미 WSL(Windows Subsystem for Linux)로 개발 환경을 쓰고 계시다면 별도 조치가 거의
필요 없습니다. WSL 안은 실제 Linux 환경이라 Mac/Linux 사용자와 동일하게 작동합니다.

1. WSL 터미널(Ubuntu 등)을 엽니다
2. `jq`가 있는지 확인:
   ```bash
   jq --version
   ```
3. 없다면 설치:
   ```bash
   sudo apt update && sudo apt install -y jq
   ```
4. Claude Code도 **WSL 터미널 안에서** 설치하고 실행해야 합니다 (PowerShell이나 CMD가
   아니라 WSL 창에서 `claude` 명령을 씁니다).

아직 WSL이 없는데 굳이 쓰고 싶다면, PowerShell을 관리자 권한으로 열고 `wsl --install`을
실행한 뒤 재부팅하면 됩니다 — 다만 처음이라면 **방법 A**가 훨씬 간단합니다.

---

## Claude Code 설치

준비물이 끝났으면 Claude Code 자체를 설치합니다. **PowerShell**(WSL을 골랐다면 WSL
터미널)을 열고:

```powershell
irm https://claude.ai/install.ps1 | iex
```

설치가 끝나면 아무 폴더에서나 `claude`라고 입력해 로그인 화면이 뜨는지 확인하세요.

---

## 플러그인 설치

이제부터는 Mac/Linux 사용자와 동일합니다 — [README의 Quick Start](../README.md#quick-start)를
그대로 따라가면 됩니다.

```
claude plugin install epcc-devkit
```

---

## 제대로 됐는지 최종 확인

작업할 프로젝트 폴더에서 `claude`를 실행하면, 세션이 시작되자마자 **"EPCC 운영 규칙"**
이라는 안내 문구가 화면에 나타나야 합니다. 이게 뜨면 훅이 정상 작동 중이라는 뜻입니다.

체크리스트:

| 확인 항목 | 방법 | 정상이면 |
| --- | --- | --- |
| Git Bash 설치됨 | Git Bash 창에서 `bash --version` | 버전 문자열 출력 |
| jq 설치됨 | 같은 창에서 `jq --version` | `jq-1.x.x` 출력 |
| Claude Code 설치됨 | 아무 터미널에서 `claude --version` | 버전 번호 출력 |
| 플러그인 훅 작동 | 프로젝트 폴더에서 `claude` 실행 | 세션 시작 시 "EPCC 운영 규칙" 안내 표시 |

---

## 이상 신호 — 이렇게 보이면 셸이 안 맞는 겁니다

아무 에러도 안 뜨는데 다음 중 하나라도 해당되면, Git for Windows가 없거나 인식이
안 되고 있는 것입니다 (에러 메시지 없이 조용히 꺼지는 게 이 문제의 특징입니다).

- 세션을 시작해도 **"EPCC 운영 규칙"** 안내가 전혀 안 뜬다
- 소스 코드를 수정하고 빌드/테스트 없이 세션을 끝내려 해도 **아무 경고 없이 그냥 끝난다**
  (원래는 막아야 정상입니다)

이 경우 해결 순서:

1. 시작 메뉴에서 "Git Bash"가 검색되는지 확인 (안 되면 위 「방법 A」부터 다시)
2. 설정 → 앱에서 "Git"이 설치 목록에 있는지 확인
3. 그래도 안 되면, `%USERPROFILE%\.claude.json`이나 설정 파일에 아래처럼 Git Bash
   경로를 직접 지정 (보통 자동 인식되므로 위 두 단계로 대부분 해결됩니다):
   ```json
   {
     "env": {
       "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe"
     }
   }
   ```

---

## 더 알아보기

- 이 플러그인이 Windows에서 왜 Git Bash를 요구하는지의 기술적 근거는
  [`docs/platform-contract.md`](platform-contract.md) §5.2에 출처와 함께 정리되어 있습니다.
- 일반 설치·사용법은 [README](../README.md)를 참고하세요.
