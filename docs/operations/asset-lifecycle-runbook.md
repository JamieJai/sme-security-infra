# Endpoint Asset Lifecycle Runbook

이 workflow는 endpoint 자산의 등록, 재고, 지급, 사용자 이관, 수리, 회수, wipe,
폐기를 SQLite 상태와 변경 이력으로 관리한다. 디스크 wipe나 물리 폐기를 직접
수행하는 도구가 아니라 승인된 작업 결과와 증거를 기록하는 control plane이다.

## 상태와 전이

| Action | 허용 시작 상태 | 종료 상태 | 추가 조건 |
|---|---|---|---|
| `stock` | registered, package issued, returned, repaired, wiped | `in_stock` | owner 제거 |
| `assign` | in_stock, wiped | `assigned` | 새 owner 필수 |
| `transfer` | assigned | `assigned` | 현재와 다른 owner 필수 |
| `send-repair` | assigned, in_stock, returned | `repair` | owner 제거 |
| `complete-repair` | repair | `repaired` | 이후 stock/assign 별도 처리 |
| `return` | assigned, recovery_pending, repair | `returned` | owner 제거 |
| `start-wipe` | returned | `wipe_pending` | 실제 wipe는 별도 수행 |
| `complete-wipe` | wipe_pending | `wiped` | wipe evidence 필수 |
| `retire` | wiped | `retired` | disposal evidence 필수 |

`scripts/register-endpoint.sh`는 최초 등록과 동일한 상태의 metadata 갱신만 허용한다.
기존 자산의 status 또는 owner를 바꾸려 하면 실패하며 lifecycle workflow를
사용해야 한다.

## Plan

기본 실행은 asset record를 변경하지 않고 `planned` operation과 Markdown
report만 남긴다.

```bash
python3 scripts/asset-lifecycle.py \
  --asset PC-2026071001 \
  --action assign \
  --owner kim.chulsoo \
  --ticket-ref ASSET-2026-001 \
  --reason "New employee endpoint assignment"
```

## Execute

실행에는 approver, 현재 예상 상태, asset 이름의 exact confirmation이 모두
필요하다. 예상 상태는 plan 이후 다른 운영자가 먼저 자산을 변경한 stale write를
차단한다.

```bash
python3 scripts/asset-lifecycle.py \
  --asset PC-2026071001 \
  --action assign \
  --owner kim.chulsoo \
  --ticket-ref ASSET-2026-001 \
  --reason "New employee endpoint assignment" \
  --expected-status in_stock \
  --approved-by it.manager \
  --confirm-asset PC-2026071001 \
  --execute
```

wipe 완료와 폐기는 각각 wipe log와 disposal record 같은 `--evidence-ref`가
필수다. 실행 결과는 `assets`, append-only `asset_history`, `operations`,
Markdown report에 기록된다.

## 오프보딩 연계

- 승인된 오프보딩은 `assigned → recovery_pending` 이력을 기록한다.
- 승인된 오프보딩 복구는 기록된 이전 상태로 돌아간 이력을 기록한다.
- 실제 장비를 회수한 뒤에는 별도 승인으로 `return`을 실행한다.
- 회수됐다는 이유만으로 wipe 완료나 폐기 상태로 건너뛰지 않는다.

## Rollback

상태를 DB에서 직접 수정하지 않는다. 잘못된 전이가 확인되면 현재 상태에서
허용되는 보정 action을 새 ticket과 승인으로 수행해 원장에 이력을 남긴다.
허용되지 않는 역전이가 필요한 경우 변경을 멈추고 자산 증거와 물리 상태를 먼저
대조한다.

## 검증

```bash
python3 -m unittest -v tests/test_asset_lifecycle.py
```

테스트는 plan 비변경성, 승인 gate, owner 이관, 회수·wipe·폐기 순서, wipe evidence,
잘못된 전이와 stale-state 차단을 임시 SQLite DB에서 확인한다.
