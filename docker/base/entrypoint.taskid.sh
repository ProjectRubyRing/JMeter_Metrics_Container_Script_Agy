#!/bin/sh
# =============================================================================
# efs-entrypoint-taskid.sh  【ECS タスク ID 方式の互換ラッパー】
# =============================================================================
set -eu

if [ -n "${EFS_ENTRYPOINT_TASKID_WRAPPED:-}" ]; then
    echo "[efs-entrypoint-taskid] FATAL: ラッパーが自分自身を呼び出しました。" >&2
    echo "[efs-entrypoint-taskid] FATAL: base の Dockerfile で entrypoint.sh を /usr/local/bin/efs-entrypoint.sh として COPY してください。" >&2
    exit 1
fi
export EFS_ENTRYPOINT_TASKID_WRAPPED=1

export LOG_ID_SOURCE="${LOG_ID_SOURCE:-taskid}"
exec /usr/local/bin/efs-entrypoint.sh "$@"
