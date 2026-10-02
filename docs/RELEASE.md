# macOS 배포 빌드 (Developer ID)

외부 베타 참여자에게 줄 macOS 앱을 만든다. 결과는 공증·staple된 `Waypoint.app`을 담은 zip 하나와 SHA256이다. iOS·TestFlight는 이 문서 밖이다.

```sh
scripts/release-mac.sh --check            # 준비 점검만
scripts/release-mac.sh                    # 배포 빌드 + 공증
scripts/release-mac.sh --version 0.1.0    # 마케팅 버전을 이번만 덮어서
scripts/release-mac.sh --skip-notarize    # 공증 전까지(내부 확인용)
```

만든 앱은 이 Mac에서 실행하지 않는다. 번들 ID가 평소용(`dev.antaeho.waypoint`)과 같아 평소용 포트 47821과 저장 폴더를 같이 쓴다. 확인은 아래 정적 검사로만 한다.

## 사전 준비 (사람이 할 일)

`scripts/release-mac.sh --check`가 빠진 것을 한 줄씩 알려 준다. 처음 한 번 할 일은 아래와 같다.

### 1. Xcode 계정

Xcode > Settings… > Accounts에 팀 `2FCXA77MC5`(Taeho An) 계정이 있어야 한다. 평소용 빌드에 이미 쓰고 있다.

### 2. Developer ID Application 인증서 — 지금은 없어도 된다

2026-10-02 실측: 키체인에 Developer ID 인증서가 없는데도 자동 서명 export가 **Xcode 클라우드 관리 인증서**로 `Developer ID Application: Taeho An (2FCXA77MC5)` 서명을 했다(개인 팀이라 계정 소유자 권한이 있다). 그래서 `--check`는 이 항목으로 막지 않는다.

export가 인증서 오류(「No signing certificate "Developer ID Application" found」 등)로 실패하면 그때 만든다.

1. Xcode > Settings… > Accounts > 팀 계정 선택 > Manage Certificates…
2. 왼쪽 아래 + > Developer ID Application
3. `security find-identity -v -p codesigning`에 `Developer ID Application: Taeho An (2FCXA77MC5)`가 보이면 된다.

### 3. 공증 자격 증명 프로필 `waypoint-notary`

1. https://account.apple.com 로그인 > 로그인 및 보안 > 앱 암호 > 앱 암호 생성(이름: `waypoint-notary`). 나온 암호를 복사한다.
2. 터미널에서:
   ```sh
   xcrun notarytool store-credentials waypoint-notary --apple-id <Apple ID 이메일> --team-id 2FCXA77MC5
   ```
   암호를 물으면 1의 앱 암호를 붙여 넣는다. 프로필은 로그인 키체인에 저장된다.
3. 확인: `xcrun notarytool history --keychain-profile waypoint-notary`가 오류 없이 목록(처음엔 비어 있음)을 출력한다.

### 4. CloudKit Production 스키마

Developer ID 앱은 CloudKit **Production** 환경을 쓴다(export 결과 엔타이틀먼트 `com.apple.developer.icloud-container-environment = Production`, 아래 「이번 실제 결과」). 평소용(`install-local.sh`, Apple Development 서명)과 Debug는 Development 환경을 쓴다. Production에 스키마가 없으면 외부 사용자 앱이 레코드를 올리지 못해 동기화가 되지 않는다.

Development 스키마는 평소용 앱이 실제로 쓰면서 이미 만들어져 있다(Core Data + CloudKit이 개발 환경에서는 첫 저장 때 레코드 타입을 만든다). 그것을 Production으로 올린다.

1. https://icloud.developer.apple.com 로그인 > CloudKit Database
2. 위쪽 컨테이너 선택에서 `iCloud.dev.antaeho.waypoint`(평소용 컨테이너. `.dev`가 붙은 것이 아님)
3. 환경을 **Development**로 두고 Schema > Record Types에 `CD_` 로 시작하는 레코드 타입들이 있는지 본다.
4. 왼쪽 아래(또는 Schema 화면) **Deploy Schema Changes…** > 바뀔 항목 목록을 확인 > **Deploy**
5. 환경을 **Production**으로 바꿔 Schema > Record Types에 3의 타입이 모두 보이는지 확인한다.

주의:
- Production에 올린 레코드 타입·필드는 지울 수 없다. 모델에 필드를 더한 판을 배포할 때마다 그 판을 평소용으로 한 번 써서 Development 스키마를 갱신한 뒤 다시 Deploy한다.
- 평소용(Development)의 데이터는 Production으로 옮겨지지 않는다. 같은 Apple ID로 베타 빌드를 써도 빈 상태에서 시작한다.
- Deploy 버튼 위치·문구는 2026-10-02에 직접 보지 못했다(**확인 못 함**). 위 순서는 Apple 문서 「Deploying an iCloud Container's Schema」 기준이다.

`xcrun cktool`(Xcode 27 포함)로는 스키마를 읽고 비교할 수 있다. 관리 토큰이 필요하다(CloudKit Console > 오른쪽 위 계정 메뉴 > Manage Tokens > 새 Management Token).

```sh
xcrun cktool save-token --type management                     # 토큰을 키체인에 저장(붙여 넣기)
xcrun cktool export-schema --team-id 2FCXA77MC5 --container-id iCloud.dev.antaeho.waypoint \
  --environment development --output-file /tmp/schema-dev.ckdb
xcrun cktool export-schema --team-id 2FCXA77MC5 --container-id iCloud.dev.antaeho.waypoint \
  --environment production  --output-file /tmp/schema-prod.ckdb
diff /tmp/schema-dev.ckdb /tmp/schema-prod.ckdb                # 차이가 없으면 Production이 최신
```

이번에 실행하지 않았다(토큰 필요). `cktool import-schema`는 `--environment`를 받지만 Production에 바로 넣을 수 있는지는 **확인 못 함** — Production 배포는 Console의 Deploy로 한다.

### 5. 하드닝 런타임에서 앱이 도는지 (첫 배포 전 한 번)

배포 빌드만 하드닝 런타임을 켠다(`project.yml`은 NO). 앱은 `Process`로 `claude`·`codex`를 띄우고 `NSWorkspace`로 터미널을 연다. 예외 엔타이틀먼트 없이 되는지는 배포 앱을 실행하지 않아 **확인 못 함**. 같은 설정의 Dev 빌드로 본다:

```sh
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -destination 'platform=macOS' \
  -derivedDataPath .build/xcode-hardened -allowProvisioningUpdates ENABLE_HARDENED_RUNTIME=YES build
open -g -j .build/xcode-hardened/Build/Products/Debug/Waypoint.app
```

실측 폴더에서 훅 수신(47822), 카드의 터미널 열기, 연동 상태 진단이 평소 Dev와 같은지 확인한다. 되면 `project.yml`에서 켜서 평소용과 배포 빌드를 맞출지 정한다.

## 단계와 기대 출력

`scripts/release-mac.sh` 한 번이 아래를 차례로 한다. 단계마다 `· …` 한 줄을 출력하고, 실패하면 이유를 출력하고 exit 1. 같은 내용이 `dist/<이름>-summary.txt`에 남는다(실패해도).

| 단계 | 하는 일 | 성공 출력 |
|---|---|---|
| 사전 점검 | 깨끗한 트리(아니면 바로 멈춤), 빌드 번호·버전, Xcode 팀, 공증 프로필(`--skip-notarize`면 생략) | `· 사전 점검: 통과(…)` |
| archive | `xcodebuild archive` Release, `generic/platform=macOS`, `-allowProvisioningUpdates`, `MARKETING_VERSION`·`CURRENT_PROJECT_VERSION`·`ENABLE_HARDENED_RUNTIME=YES` 덮기. 로그 `.build/release-mac/archive.log` | `· archive: 성공(…)` |
| export | `-exportArchive`, ExportOptions(method `developer-id`, signingStyle `automatic`, teamID, 스크립트가 `.build/release-mac/ExportOptions.plist`로 만든다) | `· export: 성공(developer-id, …)` |
| 서명 검증 | Info.plist의 번들 ID·버전·빌드, `codesign --verify --deep --strict`, Authority가 Developer ID·팀, 하드닝 런타임, 엔타이틀먼트 컨테이너·`icloud-container-environment`(Production이어야 함)·`aps-environment` 출력 | `Authority=…` 세 줄, 엔타이틀먼트 세 줄, `· 서명 검증: 통과(…)` |
| 공증 | `ditto -c -k --keepParent` → `notarytool submit --keychain-profile waypoint-notary --wait`. 결과와 상관없이 `notarytool log`를 `dist/<이름>-notary-log.json`에 남긴다 | `· 공증: Accepted(제출 <id>, …)` |
| staple | `stapler staple` + `stapler validate` | `· staple: 성공` |
| Gatekeeper | `spctl -a -vvv -t exec`. 공증 빌드는 `accepted`, `source=Notarized Developer ID`여야 한다. `--skip-notarize`는 거부가 정상이라 기록만 | `· Gatekeeper: 통과(…)` |
| 산출물 | staple된 앱으로 zip을 다시 만들고 SHA256 | `완료: dist/<이름>.zip` |

산출물(`dist/`, git에 안 올림):

- `Waypoint-<버전>-<빌드>.zip` — 참여자에게 주는 파일
- `Waypoint-<버전>-<빌드>.zip.sha256`
- `Waypoint-<버전>-<빌드>-summary.txt` — 시각·커밋·Xcode·단계 결과
- `Waypoint-<버전>-<빌드>-notary-log.json` — 공증 로그
- 이름 끝: `--allow-dirty`로 변경이 있을 때 `-dirty`, `--skip-notarize`면 `-unnotarized`

중간 결과는 `.build/release-mac/`(archive, export된 앱, 로그, `codesign-info.txt`, `entitlements.plist`). 매번 지우고 새로 만든다. 평소용 설치의 `.build/release`와 겹치지 않는다.

## 검증 명령

스크립트가 하는 것과 같다. 손으로 다시 볼 때:

```sh
APP=.build/release-mac/export/Waypoint.app
codesign --verify --deep --strict --verbose=2 $APP
codesign -dv --verbose=4 $APP 2>&1 | grep -E '^(Authority|TeamIdentifier|CodeDirectory)'
codesign -d --entitlements - --xml $APP | plutil -p -
spctl -a -vvv -t exec $APP
xcrun stapler validate $APP
# 받은 zip을 풀어서(참여자 쪽과 같은 확인)
ditto -x -k dist/Waypoint-<버전>-<빌드>.zip /tmp/wp && spctl -a -vvv -t exec /tmp/wp/Waypoint.app
shasum -a 256 -c dist/Waypoint-<버전>-<빌드>.zip.sha256   # dist/에서
```

## 이번 실제 결과 (2026-10-02, 커밋 084dcde, Xcode 27.0 27A266a)

`scripts/release-mac.sh --check` — 공증 프로필 없음, (점검 당시) 커밋 안 된 변경 있음으로 「준비 안 됨」(exit 1). Developer ID 인증서는 키체인에 없지만 막지 않음(아래 export 결과).

`scripts/release-mac.sh --skip-notarize`(깨끗한 트리) — exit 0:

```
· archive: 성공(…/.build/release-mac/Waypoint.xcarchive)          # 로그 끝: ** ARCHIVE SUCCEEDED **
· export: 성공(developer-id, …/export/Waypoint.app)               # 로그 끝: ** EXPORT SUCCEEDED **
  Authority=Developer ID Application: Taeho An (2FCXA77MC5)
  Authority=Developer ID Certification Authority
  Authority=Apple Root CA
  icloud-container-identifiers: iCloud.dev.antaeho.waypoint
  icloud-container-environment: Production
  aps-environment: production
  …/Waypoint.app: rejected
  source=Unnotarized Developer ID
  origin=Developer ID Application: Taeho An (2FCXA77MC5)
· 산출물: dist/Waypoint-0.0.1-218-unnotarized.zip (5.2M)
```

- `CodeDirectory … flags=0x10000(runtime)` — 하드닝 런타임 켜짐. `Format=app bundle with Mach-O universal (x86_64 arm64)`, `TeamIdentifier=2FCXA77MC5`, `Timestamp` 있음(보안 타임스탬프).
- 엔타이틀먼트 전체: `application-identifier 2FCXA77MC5.dev.antaeho.waypoint`, `aps-environment production`, `icloud-container-environment Production`, `icloud-container-identifiers [iCloud.dev.antaeho.waypoint]`, `icloud-services [CloudKit]`, `team-identifier`. 하드닝 런타임 예외(`com.apple.security.cs.*`)는 없다.
- 프로파일: `embedded.provisionprofile` = 「Mac Team Direct Provisioning Profile: dev.antaeho.waypoint」(Xcode가 export 때 만듦, 만료 2044-09-27, 모든 기기).
- `spctl` 거부(`Unnotarized Developer ID`)는 공증 전이라 정상이다.
- 공증·staple·공증 후 `spctl`은 프로필이 없어 **아직 못 함**.

## 실패할 때

| 증상 | 할 일 |
|---|---|
| `커밋 안 된 변경이 있음` | 커밋한다. 확인만이면 `--allow-dirty`(이름에 `-dirty`, 외부 배포 금지) |
| `공증 프로필 'waypoint-notary' 을 쓸 수 없음(missing)` | 「사전 준비 3」. 공증 없이 확인만이면 `--skip-notarize` |
| `공증 프로필 … (error: …)` | 네트워크·Apple ID 상태. 앱 암호를 지웠으면 다시 만들어 `store-credentials` |
| `archive 실패` | 화면의 마지막 오류와 `.build/release-mac/archive.log`. 평소 빌드(`install-local.sh`의 빌드 단계)와 같은 원인인지 본다 |
| `Developer ID export 실패` | `.build/release-mac/export.log`. 인증서 오류면 「사전 준비 2」로 인증서를 만든다. 프로파일 오류면 Xcode 계정 로그인 상태를 확인하고 다시 |
| `CloudKit 환경이 Production이 아님` | export가 개발용 서명으로 됐다는 뜻. ExportOptions method가 `developer-id`인지, Xcode 계정 권한을 본다 |
| `하드닝 런타임이 꺼져 있음` | archive 줄의 `ENABLE_HARDENED_RUNTIME=YES`가 빠졌는지 본다 |
| `공증 실패: 상태 'Invalid'` | `dist/<이름>-notary-log.json`의 `issues`를 본다. 고친 뒤 커밋하고 다시(빌드 번호가 바뀐다) |
| `Gatekeeper가 받지 않음` | `xcrun stapler validate`, 공증 로그. staple 직후 바로 실패하면 몇 분 뒤 다시 |

## 버전과 빌드 번호

- **빌드 번호**(`CFBundleVersion`) = `git rev-list --count HEAD`. 커밋마다 늘어난다. `release-mac.sh`와 `install-local.sh`가 같은 함수(`scripts/build-version.sh`의 `waypoint_build_number`)로 정해 `CURRENT_PROJECT_VERSION=<n>`으로 넘긴다. `project.yml`의 `CURRENT_PROJECT_VERSION: "1"`은 Xcode에서 직접 빌드할 때만 쓰인다.
- 빌드 번호가 바뀌면 앱이 첫 실행 때 `store-version.json`과 비교해 저장소를 열기 전에 백업한다(TRK-46). 같은 커밋을 다시 빌드하면 번호가 같아 백업이 생기지 않는다.
- **마케팅 버전**(`CFBundleShortVersionString`)은 `project.yml`의 `MARKETING_VERSION`이 원본이다. `--version X.Y.Z`(숫자 셋)를 주면 그 빌드에만 덮고 파일은 고치지 않는다. 계속 쓸 버전이면 `project.yml`을 고쳐 커밋한다.
- 배포 빌드는 깨끗한 트리에서만 만든다. 그래야 빌드 번호와 커밋이 한 내용을 가리킨다(요약 파일에 커밋 해시가 남는다).
