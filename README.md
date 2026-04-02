# Findery

macOS 네이티브 파일 관리자. Windows Explorer 스타일의 주소창과 Finder 스타일의 사이드바를 결합한 오픈소스 파일 탐색기.

## 주요 기능

**네비게이션**
- 주소창 직접 입력 (`~/` 지원, 자동완성)
- ◀ ▶ ▲ 네비게이션 버튼
- Finder 스타일 사이드바 (즐겨찾기 + 위치)
- 탭 지원 (⌘T)

**파일 조작**
- 복사 / 잘라내기 / 붙여넣기 (⌘C / ⌘X / ⌘V)
- 실행 취소 (⌘Z)
- 이름 변경 (F2, 인라인)
- 새 폴더 (⌘⇧N)
- 휴지통 (⌘⌫, 사운드 + 페이드 애니메이션)
- 압축 (⌃⇧C, Keka 연동)
- 드래그 앤 드롭

**보기**
- Quick Look 미리보기 (Space)
- 숨김파일 표시/숨기기 (.* 토글, ⌘⇧.)
- 컬럼 헤더 클릭 정렬
- 검색 필터 (⌘F)
- 실시간 파일 감시 (FSEvents)

**기타**
- 즐겨찾기 관리 (★ 버튼 + 우클릭)
- 우클릭 컨텍스트 메뉴 (다음으로 열기, Finder에서 보기 등)
- 심볼릭 링크 / 숨김파일 반투명 표시
- 선택 상태 보존

## 키보드 단축키

| 단축키 | 동작 |
|--------|------|
| ⌘L | 주소창 포커스 |
| ⌘F | 검색 |
| ⌘T | 새 탭 |
| ⌘↑ | 상위 폴더 |
| ⌘[ / ⌘] | 뒤로 / 앞으로 |
| Backspace | 뒤로 |
| Enter | 폴더 열기 / 파일 실행 |
| Space | Quick Look |
| F2 | 이름 변경 |
| ⌘⇧N | 새 폴더 |
| ⌘⌫ | 휴지통 |
| ⌘C / ⌘X / ⌘V | 복사 / 잘라내기 / 붙여넣기 |
| ⌘Z | 실행 취소 |
| ⌘⇧. | 숨김파일 토글 |
| ⌃⇧C | 압축 |
| ⌘A | 전체 선택 |
| ⌘R | 새로고침 |

## 기술 스택

- **Swift** + **AppKit** (macOS 네이티브)
- NSSplitViewController (사이드바 + 콘텐츠)
- NSOutlineView (사이드바)
- NSTableView (파일 목록)
- FSEvents (실시간 파일 감시)
- QLPreviewPanel (Quick Look)

## 설치 (DMG / ZIP)

[최신 릴리즈 다운로드](https://github.com/y8ny8n/findery/releases/latest)

1. `.dmg` 또는 `.zip` 다운로드
2. DMG: 열고 Findery.app을 **Applications 폴더로 드래그**
3. ZIP: 압축 해제 후 Findery.app을 **Applications 폴더로 이동**

### 첫 실행 (미서명 앱 허용)

Apple Developer ID로 서명되지 않은 앱이라 첫 실행 시 Gatekeeper가 차단합니다.

**방법 1: 시스템 설정 (권장)**
1. Findery.app 더블클릭 → 경고 뜨면 **취소**
2. **시스템 설정 > 개인정보 보호 및 보안** 열기
3. 아래쪽 `"Findery"이(가) 차단되었습니다` → **그래도 열기** 클릭
4. 비밀번호 입력 → 이후 정상 실행

**방법 2: 터미널**
```bash
xattr -cr /Applications/Findery.app
```

### 파일 접근 권한

첫 실행 시 Desktop, Documents, Downloads 접근 권한을 물어봅니다.
**허용**을 누르면 해당 폴더는 이후 다시 묻지 않습니다.

## 소스에서 빌드

```bash
# XcodeGen 필요
brew install xcodegen
git clone https://github.com/y8ny8n/findery.git
cd findery
xcodegen generate
open Findery.xcodeproj
# ⌘R로 빌드 & 실행
```

## 라이선스

MIT
