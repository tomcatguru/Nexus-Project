# Nexus Gantt

Canvas 기반 macOS 프로젝트 일정 관리 앱의 초기 버전입니다.

## 실행

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run NexusGantt
```

또는 Xcode에서 `Package.swift`를 열고 `NexusGantt` 스킴을 실행합니다. macOS 14 이상이 필요합니다.

## 포함된 기능

- 프로젝트 → 작업 → 하위 작업 계층
- SwiftUI `Canvas` 기반 일/월 타임라인, 주말 음영, 오늘 표시선
- 진행률 바와 상위 항목 의존선
- 프로젝트/작업 추가, 편집, 계층 삭제
- 트랙패드 핀치, 툴바, 단축키를 통한 65–200% 확대/축소
- 접기/펼치기 및 화면 위치·배율 자동 복원
- 바 가장자리 드래그로 시작일·완료일 변경, 바 중앙 드래그로 전체 일정 이동
- Application Support의 `NexusGantt/gantt.json`에 자동 저장

현재 의존 관계는 요구사항에 맞춰 자신의 상위 작업 또는 프로젝트만 선택할 수 있습니다.
