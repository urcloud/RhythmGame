# Chart Format Specification (v1)

이 문서는 리듬게임 차트 JSON 파일의 **협업 인터페이스**다.  
채보 작성자와 엔진 구현자는 이 스펙과 [`chart.schema.json`](chart.schema.json)만 공유하면 된다.

## 결정된 규약

- 타이밍 단위: **beat** (곡의 비트 0 기준)
- BPM: 곡 전체 동안 **일정** (BPM 변화 없음)
- 레인: **3레인** — `position` ∈ `{0, 1, 2}`
- 단일 노트: `end` 필드 **생략**
- 롱 노트: `end` 필드 **필수**, `end > start`

## 파일 배치

- 스키마: [`format/chart.schema.json`](chart.schema.json)
- 예제: [`format/examples/sample.chart.json`](examples/sample.chart.json)
- `meta.audio`는 **차트 파일 기준 상대경로**로 기록한다.

## 루트 오브젝트

```json
{
  "formatVersion": 1,
  "meta": { ... },
  "notes": [ ... ]
}
```

| 필드 | 타입 | 필수 | 의미 |
|------|------|------|------|
| `formatVersion` | integer | Y | 스펙 버전. 현재 `1` |
| `meta` | object | Y | 곡/차트 메타데이터 |
| `notes` | array | Y | 노트 목록 (비어 있어도 됨) |

알 수 없는 최상위 필드는 허용하지 않는다.

## `meta`

| 필드 | 타입 | 필수 | 의미 |
|------|------|------|------|
| `title` | string | Y | 곡 제목 (비어 있지 않음) |
| `artist` | string | Y | 아티스트. 모르면 `"Unknown"` |
| `audio` | string | Y | mp3 경로. **차트 파일 기준 상대경로** |
| `bpm` | number | Y | 상수 BPM (`> 0`) |
| `offsetBeats` | number | Y | 오디오 타임라인 대비 비트 0 보정 (보통 `0`) |
| `difficulty` | integer | Y | 난이도 `1`–`10` (1=가장 쉬움, 10=가장 어려움) |

## `notes[]` 노트 오브젝트

| 필드 | 타입 | 필수 | 의미 |
|------|------|------|------|
| `type` | string | Y | `"single"` \| `"long"` |
| `start` | number | Y | 시작 비트 (`≥ 0`) |
| `end` | number | long만 | 끝 비트. `type === "long"`이면 필수, `type === "single"`이면 **금지(생략)** |
| `position` | integer | Y | `0` \| `1` \| `2` |

### 타입별 규칙

**single**

```json
{ "type": "single", "start": 4.0, "position": 0 }
```

- `end`를 넣지 않는다.

**long**

```json
{ "type": "long", "start": 8.0, "end": 12.0, "position": 1 }
```

- `end`는 필수이며 `end > start`여야 한다.

## 불변 조건 (엔진/채보 공통 계약)

아래를 만족하지 않는 차트는 **유효하지 않다**.

1. `type === "long"` → `end` 존재, `end > start`
2. `type === "single"` → `end` 없음
3. 동일 `(start, position)`에 노트 중복 금지
4. 같은 `position`에서 롱노트 구간 `[start, end]`끼리 겹침 금지  
   (경계가 닿는 경우: `a.end === b.start`는 허용)
5. `notes`는 `start` 오름차순 정렬을 **권장**한다.  
   엔진은 로드 시 정렬해도 되고, 정렬된 입력을 가정해도 된다.

스키마(`chart.schema.json`)는 구조·타입·single/long의 `end` 유무를 검증한다.  
중복·겹침 같은 의미론적 제약은 채보 툴 또는 엔진 로드 단계에서 검사한다.

## 타이밍 변환

상수 BPM이므로 beat ↔ 밀리초 변환은 다음과 같다.

```
timeMs = (beat + offsetBeats) * (60000 / bpm)
beat   = timeMs * (bpm / 60000) - offsetBeats
```

`offsetBeats`는 오디오가 비트 그리드보다 일찍/늦게 시작할 때 맞추는 값이다.

예) BPM 120에서 오디오가 250ms 늦으면:

```
offsetBeats = 250 * (120 / 60000) = 0.5
```

이때 beat `0`의 노트는 오디오 재생 시각 250ms에 판정한다.

## 협업 인터페이스

| 역할 | 책임 |
|------|------|
| 채보 작성 | 이 JSON만 읽고/쓴다. 엔진 구현을 몰라도 된다. |
| 엔진 구현 | `formatVersion` 확인 후 `meta` / `notes`를 소비한다. 가능하면 스키마로 검증한다. |

스키마를 깨는 변경이 필요하면:

1. `formatVersion`을 올린다.
2. 이 `SPEC.md`와 `chart.schema.json`을 함께 갱신한다.
3. 구버전 호환이 필요하면 엔진에서 버전별 로더를 둔다.

## 예제

[`examples/sample.chart.json`](examples/sample.chart.json)을 참고한다.
