# LidTone

맥북 덮개로 연주하는 작은 악기. **스페이스바를 누르면 얼굴이 입을 벌리며 노래하고, 덮개 각도로 음높이를 바꿉니다.**

An experimental macOS instrument controlled by the MacBook lid angle. Hold Space to sing; move the lid to change pitch.

## 사용하기

1. [Releases](../../releases)에서 앱 ZIP을 내려받아 압축을 풉니다.
2. `LidTone.app`을 실행하고 앱 창을 선택합니다.
3. **스페이스바를 누른 채** 덮개를 천천히 움직입니다. 덮개를 열수록 음이 높아집니다.
4. 키를 떼거나 다른 창으로 이동하면 소리가 멈추고 입이 닫힙니다.

### 기능

- 오타마톤에서 영감을 받은 얼굴과 입 애니메이션
- 전체 화면 연주
- 각도와 한글 계이름 표시: 도·도♯·레·레♯·미·파·파♯·솔·솔♯·라·라♯·시
- 기본 45°–125° 범위를 C3–C5 두 옥타브로 변환
- 음량, 각도 범위, 음높이 방향 조절
- 부드러운 음높이 변화 또는 반음 단위 보정
- 센서 연결이 끊기거나 창이 비활성화되면 음소거

자세한 설명은 [사용법](사용법.md)을 참고하세요. 설정은 앱을 다시 실행하면 기본값으로 돌아옵니다.

## 지원 환경과 현재 제한

- 배포 앱: **Apple Silicon(arm64), macOS 13 이상**
- HID 덮개 각도 센서가 인식되는 맥북 필요. **MacBook Air M2에서 확인**했으며 모든 맥북을 지원한다고 보장하지 않습니다.
- **개발자 배포 서명 및 Apple 공증을 하지 않은 테스트 버전**입니다. 인터넷에서 다운로드한 앱은 macOS 보안 기능에 의해 실행이 차단될 수 있습니다.
- 센서는 공개적으로 문서화된 전용 각도 API 대신 HID 보고서로 읽습니다. 기기나 macOS 업데이트에 따라 호환성이 달라질 수 있습니다.
- 덮개를 완전히 닫으면 맥이 잠자기에 들어갈 수 있습니다.
- 실제 오타마톤 녹음이 아닌 합성 음색입니다.

네트워크 통신, 마이크 입력, 전역 키보드 감시는 사용하지 않습니다. Otamatone 공식 제품과는 무관한 개인 실험 프로젝트입니다.

## 소스에서 빌드

macOS와 Xcode Command Line Tools가 필요합니다. 저장소 폴더에서:

```sh
zsh build.command
open LidTone.app
```

빌드는 실행한 맥의 기본 아키텍처를 사용하고 로컬 임시 서명을 합니다. 다른 사람에게 일반 배포하려면 Developer ID 서명과 Apple 공증을 별도로 진행해야 합니다.

### 검사

```sh
./LidTone.app/Contents/MacOS/LidTone --self-test
./LidTone.app/Contents/MacOS/LidTone --diagnose
```

자동 검사는 각도-음높이 변환, 범위 제한, 방향 반전, 초기 무음, 440 Hz 소리 생성, 출력 크기 제한, 키 해제 후 무음을 확인합니다. 센서 진단은 해당 맥에서 현재 각도 하나를 읽습니다. 실제 연주 감각과 스피커 음질은 직접 확인해야 합니다.

## 구성

- `Source/main.m`: AppKit 화면, HID 센서 읽기, AVAudioEngine 소리 생성
- `Source/Info.plist`: 앱 정보
- `build.command`: 빌드 및 로컬 서명

## 참고

센서 식별 정보와 보고서 형식: [Lid angle HID example](https://gist.github.com/alessaba/098f83c587e1372d30dea36a7c18b7cc).

현재 별도의 오픈소스 라이선스는 지정하지 않았습니다.
