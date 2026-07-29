# Helpdesk Ticket and KPI Runbook

이 workflow는 사용자 문의를 단순 메모가 아니라 접수, 최초 응답, 해결, 재오픈
event로 기록하고 기간별 운영 지표를 만든다. 개인 lab의 모의 티켓은
`simulation`으로 저장하며 실제 사용자 SLA처럼 표현하지 않는다.

## 데이터 모델

| 테이블 | 역할 |
|---|---|
| `helpdesk_tickets` | priority, 현재 상태, 최초 응답·최종 해결 시각 |
| `helpdesk_events` | open/respond/resolve/reopen event 원장 |
| `operations` | workflow 실행 결과와 report 경로 |

티켓 상태는 `open → in_progress → resolved` 순서로 진행한다. 해결된 티켓만
`reopen`할 수 있으며 최초 응답 시각은 후속 응답이나 재오픈으로 덮어쓰지 않는다.
모든 event 시각은 timezone이 있는 ISO 8601 형식이어야 하고 이전 event보다
과거로 이동할 수 없다.

## 티켓 처리

모의 티켓 접수:

```bash
python3 scripts/helpdesk-ticket.py open \
  --ticket-ref HD-DEMO-001 \
  --actor demo.user \
  --priority p2 \
  --scenario sso \
  --target demo.user \
  --summary "SSO redirect returns to login" \
  --recurrence-key sso-login-loop
```

최초 응답과 해결:

```bash
python3 scripts/helpdesk-ticket.py respond \
  --ticket-ref HD-DEMO-001 \
  --actor helpdesk.agent \
  --note "Identity path triage started"

python3 scripts/helpdesk-ticket.py resolve \
  --ticket-ref HD-DEMO-001 \
  --actor helpdesk.agent \
  --resolution "Stale browser session cleared"
```

실제 문의를 기록할 때만 `open`에 `--data-classification live`를 명시한다. 비밀번호,
OTP, token, webhook URL, raw sensitive log는 summary, note, resolution에 쓰지
않는다.

## KPI Report

```bash
python3 scripts/helpdesk-metrics.py \
  --from 2026-07-01T00:00:00+09:00 \
  --to 2026-08-01T00:00:00+09:00
```

리포트는 다음을 집계한다.

- priority별 접수량과 현재 상태
- 최초 응답 평균과 p95
- 최종 해결 평균과 p95
- priority별 목표 기준 응답·해결 SLA 준수율
- 재오픈 비율
- 같은 `recurrence_key`가 두 건 이상 발생한 재발 항목
- `simulation`과 `live` 티켓 수

P1/P2/P3/P4 목표는 각각 응답 `15m/1h/4h/8h`, 해결
`4h/8h/24h/72h`로 설정했다. 이는 workflow 검증용 기준이며 실제 조직의
production SLA가 아니다.

## 장애 진단 연결

티켓을 연 뒤 `scripts/helpdesk-diagnose.sh`로 read-only 진단 계획과 증적을
생성한다. 지원 scenario에는 `windows-gpo`가 포함되며 runbook과 스크립트의
지원 목록을 동일하게 유지한다.

## 검증

```bash
python3 -m unittest -v tests/test_helpdesk_workflow.py
```

테스트는 응답 전 해결 차단, 최초 응답 보존, 시간 역행 차단, 재오픈, SLA와 재발
집계를 임시 SQLite DB에서 확인한다.
