#!/bin/sh
# =============================================================================
# perf-metrics.sh
#
# JMeter 性能試験用 コンテナ内部メトリクス統合収集モジュール (1ファイル集約版)
# 対象環境:
#   - AWS ECS Fargate (readonlyRootFilesystem=true)
#   - Red Hat UBI 9.8 + Red Hat build of OpenJDK 21
#   - JBoss EAP 8.1 (standalone モード)
#   - EFS マウント領域: /mnt/logs/<front|back>/logs/<Service_Name>/mid/current
#
# 収集対象 (CloudWatch Container Insights 拡張で取得可能なコンテナ全体CPU/Mem/NW/IOは除外):
#   ① jboss-cli.sh による DB接続プール (InUse/Available/Wait/TimedOut/PrepStmtCache)
#      および Undertow / IO Worker スレッドプール / JTA トランザクション統計
#   ② jstat / jcmd / JFR (Java Flight Recorder) による JVM ヒープ世代別 (Eden/Survivor/Old)、
#      Metaspace、CodeCache、NativeMemory(NMT)、GC回数/停止時間/原因、JFRイベント統計
#   ③ top (-H) / ps (-L) / /proc による スレッド別CPU・カーネル待機要因(wchan)・
#      スレッド状態(R/D/S/Z)・FD枯渇率・ページフォルト・強制コンテキストスイッチ・TCPソケット状態
#   ④ -XX:ActiveProcessorCount の設定要否判断に必要な情報
#      (ホスト物理CPU、ECSタスク/コンテナCPU、cgroup v1/v2 クォータ、JVM認識コア数、
#       GC/JIT/ForkJoin/Undertowスレッド数、CFSスロットリング発生率、自動要否判定)
#
# 有効化方法:
#   ビルド引数 `--build-arg ENABLE_PERF_METRICS=true` (または環境変数 ENABLE_PERF_METRICS=true)
#   無効時 (デフォルト false) は一切読み込まれず、本番コンテナと完全同一の挙動となる。
# =============================================================================

# --- 1. 有効化判定ヘルパー ---------------------------------------------------
is_perf_metrics_enabled() {
    case "${ENABLE_PERF_METRICS:-false}" in
        true|TRUE|1|on|ON|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# コンテナ役割 (front / back) の正規化
perf_normalize_role() {
    _raw_role="${COMPONENT_ROLE:-${Component_name:-front}}"
    case "${_raw_role}" in
        *back*|BACK)   printf 'back' ;;
        *front*|FRONT) printf 'front' ;;
        *)             printf 'front' ;;
    esac
}

# サービス名 (intra-web / intra-api / inter-api / sf-api) の正規化
perf_normalize_service() {
    _raw_svc="${Service_Name:-${SERVICE_NAME:-intra-web}}"
    case "${_raw_svc}" in
        intra-web|intraweb) printf 'intra-web' ;;
        intra-api|intraapi) printf 'intra-api' ;;
        inter-api|interapi) printf 'inter-api' ;;
        sf-api|sfapi)       printf 'sf-api' ;;
        *)                  printf '%s' "${_raw_svc}" ;;
    esac
}

# JST タイムスタンプ取得 (YYYY-MM-DD HH:MM:SS)
perf_now_jst() {
    TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'
}

# --- 2. ビルド時セットアップ (Dockerfile から呼ばれた場合) -------------------
perf_metrics_build_setup() {
    echo "================================================================================"
    echo "[PERF-METRICS][BUILD] ENABLE_PERF_METRICS=${ENABLE_PERF_METRICS:-false}"
    if ! is_perf_metrics_enabled; then
        echo "[PERF-METRICS][BUILD] Performance metrics mode is DISABLED (Production Default)."
        echo "================================================================================"
        return 0
    fi

    echo "[PERF-METRICS][BUILD] ★ Performance Test Metrics Mode is ENABLED in this image ★"
    echo "[PERF-METRICS][BUILD] Verifying OpenJDK 21 (jstat/jcmd/jfr) & procps-ng (top/ps)..."
    for _tool in java jstat jcmd jfr top ps awk sed grep; do
        if command -v "${_tool}" >/dev/null 2>&1; then
            echo "[PERF-METRICS][BUILD]   OK: ${_tool} -> $(command -v "${_tool}")"
        else
            echo "[PERF-METRICS][BUILD]   WARN: ${_tool} not found in PATH (${PATH})"
        fi
    done

    # JFR 一時リポジトリ用ディレクトリ (/tmp/jfr-repo) の用意
    mkdir -p /tmp/jfr-repo 2>/dev/null || true
    chmod 1777 /tmp/jfr-repo 2>/dev/null || true
    echo "enabled_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > /etc/jboss-perf-metrics.enabled 2>/dev/null || true
    echo "================================================================================"
}

# --- 3. standalone.xml の統計属性 (statistics-enabled="true") 事前有効化 ------
# JBoss EAP 8.1 は既定で statistics-enabled="false" のため、起動前に復元済みの
# Writable な configuration/standalone.xml に対して統計収集を有効化する。
perf_enable_xml_statistics() {
    _xml_file="$1"
    [ -f "${_xml_file}" ] && [ -w "${_xml_file}" ] || return 0

    # datasources / undertow / transactions の statistics-enabled="false" を "true" に置換
    sed -i \
        -e 's/statistics-enabled="false"/statistics-enabled="true"/g' \
        -e 's/<subsystem xmlns="urn:jboss:domain:undertow:\([^"]*\)"\([^>]*\)>/<subsystem xmlns="urn:jboss:domain:undertow:\1"\2 statistics-enabled="true">/g' \
        -e 's/statistics-enabled="true" statistics-enabled="true"/statistics-enabled="true"/g' \
        -e 's/<core-environment\([^>]*\)>/<core-environment\1 statistics-enabled="true">/g' \
        -e 's/<coordinator-environment\([^>]*\)>/<coordinator-environment\1 statistics-enabled="true">/g' \
        -e 's/statistics-enabled="true"\([^>]*\)statistics-enabled="true"/statistics-enabled="true"\1/g' \
        "${_xml_file}" 2>/dev/null || true

    # data-source / xa-data-source タグに statistics-enabled が未指定なら付与
    sed -i \
        -e '/<data-source / { /statistics-enabled=/! s/<data-source /<data-source statistics-enabled="true" /; }' \
        -e '/<xa-data-source / { /statistics-enabled=/! s/<xa-data-source /<xa-data-source statistics-enabled="true" /; }' \
        "${_xml_file}" 2>/dev/null || true
}

# --- 4. メトリクス出力ファイルのヘッダ初期化 ---------------------------------
perf_write_common_meta_header() {
    _target_file="$1"
    _category_title="$2"
    _logical_file="${PERF_LOGICAL_CURRENT_DIR}/$(basename "${_target_file}")"
    _real_file="${PERF_OUT_DIR}/$(basename "${_target_file}")"
    cat <<EOF > "${_target_file}"
# ==============================================================================
# ${_category_title}
# METRICS_LOG_PATH: ${_logical_file}
# METRICS_REAL_PATH: ${_real_file}
# CONTAINER_ROLE: ${PERF_ROLE}
# COMPONENT_NAME: ${PERF_COMPONENT}
# SERVICE_NAME: ${PERF_SERVICE}
# TASK_LOG_ID: ${PERF_LOG_ID}
# INTERVAL_SECONDS: ${PERF_METRICS_INTERVAL}
# GENERATED_AT_JST: $(perf_now_jst)
# ==============================================================================
EOF
}

perf_init_output_files() {
    mkdir -p "${PERF_OUT_DIR}" 2>/dev/null || true

    # ⓪ 起動時環境設定・有効化証跡スナップショット
    F_ENV_TXT="${PERF_OUT_DIR}/00_perf_metrics_startup_env.txt"
    perf_write_common_meta_header "${F_ENV_TXT}" "[0] JMeter Performance Test Mode Startup Configuration & Evidence"
    cat <<EOF >> "${F_ENV_TXT}"
ENABLE_PERF_METRICS=${ENABLE_PERF_METRICS}
CONTAINER_ROLE=${PERF_ROLE}
COMPONENT_NAME=${PERF_COMPONENT}
SERVICE_NAME=${PERF_SERVICE}
TASK_LOG_ID=${PERF_LOG_ID}
INTERVAL_SECONDS=${PERF_METRICS_INTERVAL}
LOGICAL_CURRENT_DIR=${PERF_LOGICAL_CURRENT_DIR}
PHYSICAL_WRITE_DIR=${PERF_OUT_DIR}
JAVA_OPTS=${JAVA_OPTS:-}
EOF

    # ① JBoss CLI 統計 TSV
    F_CLI_TSV="${PERF_OUT_DIR}/01_jboss_cli_stats.tsv"
    F_CLI_RAW="${PERF_OUT_DIR}/01_jboss_cli_raw.log"
    if [ ! -f "${F_CLI_TSV}" ]; then
        perf_write_common_meta_header "${F_CLI_TSV}" "[1] JBoss EAP 8.1 jboss-cli DB Connection Pool & Runtime Statistics"
        printf 'Timestamp_JST\tContainer\tService\tTask_LogID\tDatasource_Name\tDS_Type\tMaxPoolSize\tActiveCount\tInUseCount\tAvailableCount\tPoolUsage_Pct\tMaxUsedCount\tWaitCount\tMaxWaitTime_ms\tTimedOut\tTotalBlockingTime_ms\tAvgCreationTime_ms\tDestroyedCount\tPrepStmtCache_HitCnt\tPrepStmtCache_MissCnt\tUndertow_ReqCount\tUndertow_ErrCount\tUndertow_MaxProcTime_ms\tUndertow_ProcTime_ms\tWorker_BusyThreads\tWorker_MaxThreads\tWorker_QueueSize\tWorker_Rejected\tJTA_TotalTx\tJTA_CommittedTx\tJTA_AbortedTx\tJTA_TimedOutTx\tJTA_InFlightTx\tJTA_Heuristics\tStatus_Eval\n' >> "${F_CLI_TSV}"
    fi
    if [ ! -f "${F_CLI_RAW}" ]; then
        perf_write_common_meta_header "${F_CLI_RAW}" "[1] JBoss EAP 8.1 jboss-cli Raw Execution Log"
    fi

    # ② JVM Heap / GC / JFR 統計 TSV
    F_JVM_TSV="${PERF_OUT_DIR}/02_jvm_heap_gc_stats.tsv"
    F_JVM_LOG="${PERF_OUT_DIR}/02_jcmd_jfr_detail.log"
    F_JFR_BIN="${PERF_OUT_DIR}/02_flight_recording.jfr"
    if [ ! -f "${F_JVM_TSV}" ]; then
        perf_write_common_meta_header "${F_JVM_TSV}" "[2] OpenJDK 21 jstat / jcmd / JFR Heap & GC Statistics"
        printf 'Timestamp_JST\tContainer\tService\tPID\tS0_Pct\tS1_Pct\tEden_Pct\tOld_Pct\tMetaspace_Pct\tCCS_Pct\tEden_Used_KB\tEden_Cap_KB\tSurvivor_Used_KB\tOld_Used_KB\tOld_Cap_KB\tMetaspace_Used_KB\tMetaspace_Cap_KB\tYGC_Count\tDelta_YGC\tYGCT_s\tFGC_Count\tDelta_FGC\tFGCT_s\tCGC_Count\tCGCT_s\tGCT_Total_s\tDelta_GCT_ms\tLast_GC_Cause\tCurr_GC_Cause\tClasses_Loaded\tJIT_Compiled\tCodeCache_Used_KB\tCodeCache_Max_KB\tNMT_Total_Committed_KB\tJFR_State\tJFR_Size_KB\tStatus_Eval\n' >> "${F_JVM_TSV}"
    fi
    if [ ! -f "${F_JVM_LOG}" ]; then
        perf_write_common_meta_header "${F_JVM_LOG}" "[2] OpenJDK 21 jcmd (GC.heap_info / VM.native_memory / Compiler.codecache) & JFR Summary Log"
    fi

    # ③ top / ps プロセス・スレッド統計 TSV
    F_PROC_TSV="${PERF_OUT_DIR}/03_process_thread_stats.tsv"
    F_PROC_LOG="${PERF_OUT_DIR}/03_top_ps_detail.log"
    if [ ! -f "${F_PROC_TSV}" ]; then
        perf_write_common_meta_header "${F_PROC_TSV}" "[3] UBI 9.8 top / ps / procfs Deep Process & Thread Statistics"
        printf 'Timestamp_JST\tContainer\tService\tPID\tJVM_Threads_Total\tThreads_Running_R\tThreads_DiskSleep_D\tThreads_Sleeping_S\tThreads_Zombie_Z\tTop1_Thread_TID\tTop1_Thread_Name\tTop1_Thread_CPU_Pct\tTop1_Thread_State\tTop1_Thread_WCHAN\tTop2_Thread_Name\tTop2_Thread_CPU_Pct\tOpen_FDs\tMax_FDs_Limit\tFD_Usage_Pct\tMin_PageFaults\tMaj_PageFaults\tVoluntary_CtxtSw\tNonVoluntary_CtxtSw\tDelta_NonVol_CtxtSw\tTCP_Established\tTCP_CloseWait\tTCP_TimeWait\tTCP_SynRecv\tTCP_ListenDrops\tStatus_Eval\n' >> "${F_PROC_TSV}"
    fi
    if [ ! -f "${F_PROC_LOG}" ]; then
        perf_write_common_meta_header "${F_PROC_LOG}" "[3] UBI 9.8 top -H & ps -L Thread Snapshot Log"
    fi

    # ④ -XX:ActiveProcessorCount 要否判断 TSV & レポート
    F_CPU_TSV="${PERF_OUT_DIR}/04_active_processor_diag.tsv"
    F_CPU_RPT="${PERF_OUT_DIR}/04_active_processor_report.txt"
    if [ ! -f "${F_CPU_TSV}" ]; then
        perf_write_common_meta_header "${F_CPU_TSV}" "[4] -XX:ActiveProcessorCount Necessity & CFS Throttling Diagnosis"
        printf 'Timestamp_JST\tContainer\tService\tHost_Physical_CPUs\tECS_Task_CPU_Units\tECS_Container_CPU_Units\tTask_Container_Count\tCgroup_Version\tCgroup_Quota_us\tCgroup_Period_us\tCgroup_Effective_vCPU\tCgroup_Weight_Shares\tExplicit_ActiveProcessorCount_Flag\tJVM_Recognized_Processors\tParallelGCThreads\tConcGCThreads\tCICompilerCount\tForkJoin_Parallelism\tUndertow_IO_Threads\tUndertow_Worker_Threads\tCFS_nr_periods\tCFS_nr_throttled\tDelta_Periods\tDelta_Throttled\tThrottle_Rate_Pct\tCFS_throttled_ms\tDelta_Throttled_ms\tLoadAvg_1m\tRecommended_ActiveProcessorCount\tNecessity_Judgment\tDiagnosis_Reason\n' >> "${F_CPU_TSV}"
    fi
    if [ ! -f "${F_CPU_RPT}" ]; then
        perf_write_common_meta_header "${F_CPU_RPT}" "[4] -XX:ActiveProcessorCount Necessity Diagnostic Report"
    fi
}

# --- 5. JBoss EAP プロセス PID 検出 ------------------------------------------
perf_find_jboss_pid() {
    # 0. 明示指定 (テスト用・オーバーライド用)
    if [ -n "${PERF_TARGET_PID:-}" ]; then
        printf '%s' "${PERF_TARGET_PID}"
        return 0
    fi
    # 1. jps から検索
    if command -v jps >/dev/null 2>&1; then
        _p="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jps -J-Djava.io.tmpdir="${PERF_TMP_DIR}" -l 2>/dev/null \
            | grep -E 'jboss-modules\.jar|org\.jboss\.as\.standalone' | awk '{print $1}' | head -n 1)"
        if [ -n "${_p}" ]; then
            printf '%s' "${_p}"
            return 0
        fi
    fi
    # 2. jcmd から検索
    if command -v jcmd >/dev/null 2>&1; then
        _p="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir="${PERF_TMP_DIR}" 2>/dev/null \
            | grep -E 'jboss-modules\.jar|org\.jboss\.as\.standalone' | awk '{print $1}' | head -n 1)"
        if [ -n "${_p}" ]; then
            printf '%s' "${_p}"
            return 0
        fi
    fi
    # 3. ps から検索 (jboss-modules.jar を実行している java プロセス)
    _p="$(ps -eo pid,args 2>/dev/null \
        | grep '[j]boss-modules\.jar' | awk '{print $1}' | head -n 1)"
    if [ -n "${_p}" ]; then
        printf '%s' "${_p}"
        return 0
    fi
    return 1
}

# --- 6. ① jboss-cli による DB 接続プール・Undertow・Worker・JTA 統計収集 -----
perf_collect_jboss_cli() {
    _pid="$1"
    _ts="$2"
    _cli_bin="${JBOSS_HOME:-/opt/jboss-eap}/bin/jboss-cli.sh"
    [ -x "${_cli_bin}" ] || return 0

    _port_offset="${PORT_OFFSET:-0}"
    # back コンテナ等で -Djboss.socket.binding.port-offset が指定されている場合の自動検出
    if [ "${_port_offset}" = "0" ] && [ -r "/proc/${_pid}/cmdline" ]; then
        _cmd_po="$(tr '\0' '\n' < "/proc/${_pid}/cmdline" 2>/dev/null | sed -n 's/^-Djboss\.socket\.binding\.port-offset=//p' | head -n 1)"
        [ -n "${_cmd_po}" ] && _port_offset="${_cmd_po}"
    fi
    _mgmt_port=$((9990 + _port_offset))
    _controller="${PERF_CLI_CONTROLLER:-remote+http://127.0.0.1:${_mgmt_port}}"

    # 1回の jboss-cli 起動で全サブシステムを一括取得し、補助JVMの起動オーバーヘッドを最小化
    # readonlyRootFilesystem=true でも動作するよう HOME=/tmp, -Duser.home=/tmp, -Djava.io.tmpdir=/tmp を指定
    _cli_out="$(
        HOME="${PERF_TMP_DIR}" \
        JAVA_TOOL_OPTIONS="" \
        JDK_JAVA_OPTIONS="" \
        JAVA_OPTS="-Xms32m -Xmx64m -XX:+UseSerialGC -XX:ActiveProcessorCount=1 -Djava.io.tmpdir=${PERF_TMP_DIR} -Duser.home=${PERF_TMP_DIR}" \
        "${_cli_bin}" --connect --controller="${_controller}" --commands="\
/subsystem=datasources:read-children-resources(child-type=data-source,include-runtime=true,recursive=true),\
/subsystem=datasources:read-children-resources(child-type=xa-data-source,include-runtime=true,recursive=true),\
/subsystem=undertow/server=default-server/http-listener=default:read-resource(include-runtime=true),\
/subsystem=io/worker=default:read-resource(include-runtime=true),\
/subsystem=transactions:read-resource(include-runtime=true)" 2>/dev/null || true
    )"

    if [ -z "${_cli_out}" ]; then
        return 0
    fi

    # 生ログの保存
    {
        echo "--- [${_ts}] jboss-cli snapshot (${_controller}) ---"
        printf '%s\n' "${_cli_out}"
    } >> "${F_CLI_RAW}"

    # awk で DMR 出力から各統計値を抽出し TSV 行を生成
    printf '%s\n' "${_cli_out}" | awk \
        -v ts="${_ts}" \
        -v cnt="${PERF_COMPONENT}" \
        -v svc="${PERF_SERVICE}" \
        -v logid="${PERF_LOG_ID}" \
    '
    function clean_val(v) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v);
        gsub(/,$/, "", v);
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v);
        gsub(/^"|"$/, "", v);
        gsub(/L$/, "", v);
        gsub(/^"|"$/, "", v);
        return (v == "" || v == "undefined") ? "0" : v;
    }
    BEGIN {
        ds_count = 0;
        cur_ds = "";
        ut_req = "0"; ut_err = "0"; ut_max_t = "0"; ut_proc_t = "0";
        wk_busy = "0"; wk_max = "0"; wk_q = "0"; wk_rej = "0";
        tx_tot = "0"; tx_com = "0"; tx_abt = "0"; tx_to = "0"; tx_inf = "0"; tx_heu = "0";
        sec = "";
    }
    # データソース名の検出 (例: "MIF02JA_JDS" => { または "MySQLXADS" => {)
    /^[[:space:]]*"[A-Za-z0-9_.-]+"[[:space:]]*=>[[:space:]]*\{/ {
        line = $0;
        sub(/^[[:space:]]*"/, "", line);
        sub(/".*$/, "", line);
        if (line !~ /^step-[0-9]+$/ && line != "result" && line != "data-source" && line != "xa-data-source" &&
            line != "statistics" && line != "pool" && line != "jdbc" &&
            line != "connection-properties" && line != "xa-datasource-properties" &&
            line != "server" && line != "default-server" && line != "http-listener" &&
            line != "https-listener" && line != "ajp-listener" && line != "worker" && line != "default") {
            cur_ds = line;
            if (!(cur_ds in seen_ds)) {
                seen_ds[cur_ds] = ++ds_count;
                ds_names[ds_count] = cur_ds;
                ds_type[cur_ds] = "DataSource";
                ds_max[cur_ds] = "20";
                ds_act[cur_ds] = "0"; ds_inuse[cur_ds] = "0"; ds_avail[cur_ds] = "0";
                ds_maxused[cur_ds] = "0"; ds_wait[cur_ds] = "0"; ds_maxwait[cur_ds] = "0";
                ds_timedout[cur_ds] = "0"; ds_block[cur_ds] = "0"; ds_create[cur_ds] = "0";
                ds_destroy[cur_ds] = "0"; ds_ps_hit[cur_ds] = "0"; ds_ps_miss[cur_ds] = "0";
            }
        }
    }
    /"xa-data-source"[[:space:]]*=>[[:space:]]*\{/ {
        in_xa_section = 1;
    }
    /"xa-datasource-class"|"xa-datasource-properties"/ {
        if (cur_ds != "") ds_type[cur_ds] = "XA-DataSource";
    }
    /"max-pool-size"[[:space:]]*=>/ {
        split($0, a, "=>"); v = clean_val(a[2]);
        if (cur_ds != "" && sec == "") ds_max[cur_ds] = v;
    }
    /"ActiveCount"[[:space:]]*=>/     { split($0, a, "=>"); if (cur_ds != "") { ds_act[cur_ds] = clean_val(a[2]); if (in_xa_section) ds_type[cur_ds] = "XA-DataSource"; } }
    /"InUseCount"[[:space:]]*=>/      { split($0, a, "=>"); if (cur_ds != "") ds_inuse[cur_ds] = clean_val(a[2]); }
    /"AvailableCount"[[:space:]]*=>/  { split($0, a, "=>"); if (cur_ds != "") ds_avail[cur_ds] = clean_val(a[2]); }
    /"MaxUsedCount"[[:space:]]*=>/    { split($0, a, "=>"); if (cur_ds != "") ds_maxused[cur_ds] = clean_val(a[2]); }
    /"WaitCount"[[:space:]]*=>/       { split($0, a, "=>"); if (cur_ds != "") ds_wait[cur_ds] = clean_val(a[2]); }
    /"MaxWaitTime"[[:space:]]*=>/     { split($0, a, "=>"); if (cur_ds != "") ds_maxwait[cur_ds] = clean_val(a[2]); }
    /"TimedOut"[[:space:]]*=>/        { split($0, a, "=>"); if (cur_ds != "") ds_timedout[cur_ds] = clean_val(a[2]); }
    /"TotalBlockingTime"[[:space:]]*=>/ { split($0, a, "=>"); if (cur_ds != "") ds_block[cur_ds] = clean_val(a[2]); }
    /"AverageCreationTime"[[:space:]]*=>/ { split($0, a, "=>"); if (cur_ds != "") ds_create[cur_ds] = clean_val(a[2]); }
    /"DestroyedCount"[[:space:]]*=>/  { split($0, a, "=>"); if (cur_ds != "") ds_destroy[cur_ds] = clean_val(a[2]); }
    /"PreparedStatementCacheHitCount"[[:space:]]*=>/  { split($0, a, "=>"); if (cur_ds != "") ds_ps_hit[cur_ds] = clean_val(a[2]); }
    /"PreparedStatementCacheMissCount"[[:space:]]*=>/ { split($0, a, "=>"); if (cur_ds != "") ds_ps_miss[cur_ds] = clean_val(a[2]); }

    # Undertow HTTP Listener
    /"request-count"[[:space:]]*=>/       { split($0, a, "=>"); ut_req = clean_val(a[2]); }
    /"error-count"[[:space:]]*=>/         { split($0, a, "=>"); ut_err = clean_val(a[2]); }
    /"max-processing-time"[[:space:]]*=>/ { split($0, a, "=>"); ut_max_t = clean_val(a[2]); }
    /"processing-time"[[:space:]]*=>/     { split($0, a, "=>"); ut_proc_t = clean_val(a[2]); }

    # IO Worker Thread Pool
    /"busy-task-thread-count"[[:space:]]*=>/ { split($0, a, "=>"); wk_busy = clean_val(a[2]); }
    /"task-max-threads"[[:space:]]*=>/       { split($0, a, "=>"); wk_max = clean_val(a[2]); }
    /"queue-size"[[:space:]]*=>/             { split($0, a, "=>"); wk_q = clean_val(a[2]); }
    /"rejected-count"[[:space:]]*=>/         { split($0, a, "=>"); wk_rej = clean_val(a[2]); }

    # JTA Transactions
    /"number-of-transactions"[[:space:]]*=>/           { split($0, a, "=>"); tx_tot = clean_val(a[2]); }
    /"number-of-committed-transactions"[[:space:]]*=>/ { split($0, a, "=>"); tx_com = clean_val(a[2]); }
    /"number-of-aborted-transactions"[[:space:]]*=>/   { split($0, a, "=>"); tx_abt = clean_val(a[2]); }
    /"number-of-timed-out-transactions"[[:space:]]*=>/ { split($0, a, "=>"); tx_to = clean_val(a[2]); }
    /"number-of-in-?flight-transactions"[[:space:]]*=>/ { split($0, a, "=>"); tx_inf = clean_val(a[2]); }
    /"number-of-heuristics"[[:space:]]*=>/             { split($0, a, "=>"); tx_heu = clean_val(a[2]); }

    END {
        if (ds_count == 0) {
            ds_count = 1;
            ds_names[1] = "default-ds";
            ds_type["default-ds"] = "DataSource";
            ds_max["default-ds"] = "20";
            ds_act["default-ds"] = "0"; ds_inuse["default-ds"] = "0"; ds_avail["default-ds"] = "20";
            ds_maxused["default-ds"] = "0"; ds_wait["default-ds"] = "0"; ds_maxwait["default-ds"] = "0";
            ds_timedout["default-ds"] = "0"; ds_block["default-ds"] = "0"; ds_create["default-ds"] = "0";
            ds_destroy["default-ds"] = "0"; ds_ps_hit["default-ds"] = "0"; ds_ps_miss["default-ds"] = "0";
        }
        for (i = 1; i <= ds_count; i++) {
            d = ds_names[i];
            inuse = ds_inuse[d] + 0;
            avail = ds_avail[d] + 0;
            maxp  = ds_max[d] + 0;
            if (maxp <= 0 && (inuse + avail) > 0) maxp = inuse + avail;
            pct = (maxp > 0) ? (inuse * 100.0 / maxp) : 0.0;

            eval_st = "NORMAL";
            if ((ds_timedout[d] + 0) > 0 || (wk_rej + 0) > 0 || (tx_heu + 0) > 0 || pct >= 95.0) {
                eval_st = "CRITICAL";
            } else if ((ds_wait[d] + 0) > 0 || (wk_q + 0) > 0 || (tx_to + 0) > 0 || pct >= 80.0) {
                eval_st = "WARN";
            }

            printf "%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%s\t%.1f\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
                ts, cnt, svc, logid, d, ds_type[d], maxp,
                ds_act[d], ds_inuse[d], ds_avail[d], pct,
                ds_maxused[d], ds_wait[d], ds_maxwait[d], ds_timedout[d],
                ds_block[d], ds_create[d], ds_destroy[d],
                ds_ps_hit[d], ds_ps_miss[d],
                ut_req, ut_err, ut_max_t, ut_proc_t,
                wk_busy, wk_max, wk_q, wk_rej,
                tx_tot, tx_com, tx_abt, tx_to, tx_inf, tx_heu,
                eval_st;
        }
    }' >> "${F_CLI_TSV}"
}

# --- 7. ② jstat / jcmd / JFR によるヒープ・GC・ネイティブメモリ統計収集 ------
perf_collect_jvm_heap_gc() {
    _pid="$1"
    _ts="$2"

    # 1) jstat -gc <pid> (容量・使用量 KB & GC 回数/時間)
    _jstat_gc=""
    if command -v jstat >/dev/null 2>&1; then
        _jstat_gc="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jstat -J-Djava.io.tmpdir="${PERF_TMP_DIR}" -gc "${_pid}" 2>/dev/null | tail -n 1 || true)"
    fi

    # 2) jstat -gccause <pid> (使用率 % & 直前/現在の GC 原因)
    _jstat_cause=""
    if command -v jstat >/dev/null 2>&1; then
        _jstat_cause="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jstat -J-Djava.io.tmpdir="${PERF_TMP_DIR}" -gccause "${_pid}" 2>/dev/null | tail -n 1 || true)"
    fi

    # 3) jstat -class & -compiler
    _jstat_cls=""
    _jstat_cmp=""
    if command -v jstat >/dev/null 2>&1; then
        _jstat_cls="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jstat -J-Djava.io.tmpdir="${PERF_TMP_DIR}" -class "${_pid}" 2>/dev/null | tail -n 1 || true)"
        _jstat_cmp="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jstat -J-Djava.io.tmpdir="${PERF_TMP_DIR}" -compiler "${_pid}" 2>/dev/null | tail -n 1 || true)"
    fi

    # 4) jcmd による詳細情報 (GC.heap_info / VM.native_memory / Compiler.codecache / JFR)
    _cc_used="0"; _cc_max="0"; _nmt_comm="0"; _jfr_state="OFF"; _jfr_kb="0"
    if command -v jcmd >/dev/null 2>&1; then
        _heap_info="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir="${PERF_TMP_DIR}" "${_pid}" GC.heap_info 2>/dev/null || true)"
        _cc_info="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir="${PERF_TMP_DIR}" "${_pid}" Compiler.codecache 2>/dev/null || true)"
        _nmt_info="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir="${PERF_TMP_DIR}" "${_pid}" VM.native_memory summary 2>/dev/null || true)"
        _jfr_chk="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir="${PERF_TMP_DIR}" "${_pid}" JFR.check 2>/dev/null || true)"

        # CodeCache 使用量/最大量の抽出 (KB)
        if [ -n "${_cc_info}" ]; then
            _cc_used="$(printf '%s\n' "${_cc_info}" | awk '/used=/ {gsub(/.*used=/,""); gsub(/K.*/,""); sum+=$1} END {print sum+0}')"
            _cc_max="$(printf '%s\n' "${_cc_info}" | awk '/max_used=|size=/ {if(match($0,/size=[0-9]+K/)){s=substr($0,RSTART+5,RLENGTH-6); sum+=s}} END {print sum+0}')"
        fi

        # NMT Total committed (KB)
        if [ -n "${_nmt_info}" ]; then
            _nmt_comm="$(printf '%s\n' "${_nmt_info}" | sed -n 's/.*Total: reserved=[0-9]*KB, committed=\([0-9]*\)KB.*/\1/p' | head -n 1)"
            [ -z "${_nmt_comm}" ] && _nmt_comm="0"
        fi

        # JFR 状態確認・スナップショットダンプ (UBI 9.8 + OpenJDK 21 Red Hat build 標準対応)
        if printf '%s' "${_jfr_chk}" | grep -q "running"; then
            _jfr_state="RUNNING"
            JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir="${PERF_TMP_DIR}" "${_pid}" \
                JFR.dump name=perf-continuous filename="${F_JFR_BIN}" >/dev/null 2>&1 || true
            if [ -f "${F_JFR_BIN}" ]; then
                _jfr_bytes="$(wc -c < "${F_JFR_BIN}" 2>/dev/null | tr -d ' ' || echo 0)"
                _jfr_kb=$((_jfr_bytes / 1024))
            fi
        fi

        # 詳細ログへの書き出し
        {
            echo "================================================================================"
            echo "[${_ts}] PID=${_pid} jcmd & JFR Snapshot"
            echo "--- [GC.heap_info] ---"
            printf '%s\n' "${_heap_info}"
            echo "--- [VM.native_memory summary] ---"
            printf '%s\n' "${_nmt_info}" | head -n 35
            echo "--- [JFR.check] ---"
            printf '%s\n' "${_jfr_chk}"
            if [ -f "${F_JFR_BIN}" ] && command -v jfr >/dev/null 2>&1; then
                echo "--- [jfr summary ${F_JFR_BIN}] ---"
                JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jfr summary "${F_JFR_BIN}" 2>/dev/null | head -n 45 || true
            fi
        } >> "${F_JVM_LOG}"
    fi

    # jstat -gc フィールド解析
    # S0C(1) S1C(2) S0U(3) S1U(4) EC(5) EU(6) OC(7) OU(8) MC(9) MU(10) CCSC(11) CCSU(12) YGC(13) YGCT(14) FGC(15) FGCT(16) CGC(17) CGCT(18) GCT(19)
    _cls_loaded="$(printf '%s' "${_jstat_cls}" | awk '{print $1+0}')"
    _jit_comp="$(printf '%s' "${_jstat_cmp}" | awk '{print $1+0}')"

    _row_out="$(awk \
        -v ts="${_ts}" \
        -v cnt="${PERF_COMPONENT}" \
        -v svc="${PERF_SERVICE}" \
        -v pid="${_pid}" \
        -v gc_line="${_jstat_gc}" \
        -v cause_line="${_jstat_cause}" \
        -v prev_ygc="${PREV_YGC:-0}" \
        -v prev_fgc="${PREV_FGC:-0}" \
        -v prev_gct="${PREV_GCT:-0}" \
        -v cls_ld="${_cls_loaded:-0}" \
        -v jit_cp="${_jit_comp:-0}" \
        -v cc_u="${_cc_used:-0}" \
        -v cc_m="${_cc_max:-0}" \
        -v nmt_c="${_nmt_comm:-0}" \
        -v jfr_st="${_jfr_state}" \
        -v jfr_sz="${_jfr_kb:-0}" \
    'BEGIN {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", gc_line);
        n = split(gc_line, g, /[[:space:]]+/);
        s0c = g[1]+0; s1c = g[2]+0; s0u = g[3]+0; s1u = g[4]+0;
        ec  = g[5]+0; eu  = g[6]+0; oc  = g[7]+0; ou  = g[8]+0;
        mc  = g[9]+0; mu  = g[10]+0; ccsc = g[11]+0; ccsu = g[12]+0;
        ygc = g[13]+0; ygct = g[14]+0; fgc = g[15]+0; fgct = g[16]+0;
        if (n >= 19) { cgc = g[17]+0; cgct = g[18]+0; gct = g[19]+0; }
        else { cgc = 0; cgct = 0; gct = g[17]+0; }

        s0_pct  = (s0c > 0) ? (s0u * 100.0 / s0c) : 0.0;
        s1_pct  = (s1c > 0) ? (s1u * 100.0 / s1c) : 0.0;
        e_pct   = (ec  > 0) ? (eu  * 100.0 / ec)  : 0.0;
        o_pct   = (oc  > 0) ? (ou  * 100.0 / oc)  : 0.0;
        m_pct   = (mc  > 0) ? (mu  * 100.0 / mc)  : 0.0;
        ccs_pct = (ccsc > 0) ? (ccsu * 100.0 / ccsc) : 0.0;

        # jstat -gccause から LGCC / GCC を抽出
        lgcc = "No GC"; gcc = "No GC";
        if (cause_line != "") {
            # 先頭13個の数値カラムを除去した残りが LGCC と GCC
            rest = cause_line;
            gsub(/^[[:space:]]+/, "", rest);
            for (i = 1; i <= 13; i++) {
                sub(/^[^[:space:]]+[[:space:]]+/, "", rest);
            }
            if (match(rest, /[[:space:]]{2,}/)) {
                lgcc = substr(rest, 1, RSTART - 1);
                gcc  = substr(rest, RSTART + RLENGTH);
            } else if (rest != "") {
                lgcc = rest;
            }
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", lgcc);
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", gcc);
        }

        d_ygc = (prev_ygc > 0 && ygc >= prev_ygc) ? (ygc - prev_ygc) : 0;
        d_fgc = (prev_fgc > 0 && fgc >= prev_fgc) ? (fgc - prev_fgc) : 0;
        d_gct_ms = (prev_gct > 0 && gct >= prev_gct) ? ((gct - prev_gct) * 1000.0) : 0.0;

        eval_st = "NORMAL";
        if (d_fgc > 0 || o_pct >= 90.0 || d_gct_ms >= 1000.0) {
            eval_st = "CRITICAL";
        } else if (o_pct >= 75.0 || m_pct >= 90.0 || d_gct_ms >= 200.0) {
            eval_st = "WARN";
        }

        surv_u = s0u + s1u;
        printf "%s\t%s\t%s\t%s\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t%d\t%d\t%.3f\t%d\t%d\t%.3f\t%d\t%.3f\t%.3f\t%.1f\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%s|%d|%d|%.3f\n",
            ts, cnt, svc, pid,
            s0_pct, s1_pct, e_pct, o_pct, m_pct, ccs_pct,
            eu, ec, surv_u, ou, oc, mu, mc,
            ygc, d_ygc, ygct, fgc, d_fgc, fgct, cgc, cgct, gct, d_gct_ms,
            lgcc, gcc, cls_ld, jit_cp, cc_u, cc_m, nmt_c, jfr_st, jfr_sz, eval_st,
            ygc, fgc, gct;
    }')"

    _tsv_part="${_row_out%|*|*|*}"
    _state_part="${_row_out##*|*|*|}"
    # PREV 値の更新
    PREV_YGC="$(printf '%s' "${_row_out}" | awk -F'|' '{print $(NF-2)}')"
    PREV_FGC="$(printf '%s' "${_row_out}" | awk -F'|' '{print $(NF-1)}')"
    PREV_GCT="$(printf '%s' "${_row_out}" | awk -F'|' '{print $NF}')"

    printf '%s\n' "${_tsv_part}" >> "${F_JVM_TSV}"
}

# --- 8. ③ top / ps / /proc によるプロセス・スレッド・FD・ソケット統計収集 -----
perf_collect_process_threads() {
    _pid="$1"
    _ts="$2"

    # 1) ps -L でスレッド一覧を取得 (CPU降順)
    _ps_threads="$(LC_ALL=C ps -L -p "${_pid}" -o pid,lwp,psr,pcpu,pmem,stat,wchan:24,time,comm --no-headers --sort=-pcpu 2>/dev/null || true)"

    # 2) top -H -b -n 1 でリアルタイムスレッドスナップショットを取得
    _top_out=""
    if command -v top >/dev/null 2>&1; then
        _top_out="$(LC_ALL=C top -H -b -n 1 -p "${_pid}" 2>/dev/null | head -n 35 || true)"
    fi

    # 詳細ログへ出力
    {
        echo "================================================================================"
        echo "[${_ts}] PID=${_pid} Thread & Process Snapshot (top -H / ps -L)"
        if [ -n "${_top_out}" ]; then
            echo "--- [top -H -b -n 1 -p ${_pid}] ---"
            printf '%s\n' "${_top_out}"
        fi
        echo "--- [ps -L -p ${_pid} (Top 25 Threads by %CPU & Wait Channel)] ---"
        printf '   PID    LWP PSR %%CPU %%MEM STAT WCHAN                    TIME     COMMAND\n'
        printf '%s\n' "${_ps_threads}" | head -n 25
    } >> "${F_PROC_LOG}"

    # 3) FD (ファイルディスクリプタ) 使用数と上限
    _open_fds="0"
    if [ -d "/proc/${_pid}/fd" ]; then
        _open_fds="$(ls -1 "/proc/${_pid}/fd" 2>/dev/null | wc -l | tr -d ' ')"
    fi
    _max_fds="65536"
    if [ -r "/proc/${_pid}/limits" ]; then
        _mf="$(awk '/Max open files/ {print $4}' "/proc/${_pid}/limits" 2>/dev/null | head -n 1)"
        case "${_mf}" in ''|*[!0-9]*) ;; *) _max_fds="${_mf}" ;; esac
    fi

    # 4) ページフォルト (min_flt / maj_flt) & コンテキストスイッチ (voluntary / nonvoluntary)
    _flt_line="$(LC_ALL=C ps -p "${_pid}" -o min_flt,maj_flt --no-headers 2>/dev/null || echo '0 0')"
    _min_flt="$(printf '%s' "${_flt_line}" | awk '{print $1+0}')"
    _maj_flt="$(printf '%s' "${_flt_line}" | awk '{print $2+0}')"

    _vol_cs="0"; _nonvol_cs="0"
    if [ -r "/proc/${_pid}/status" ]; then
        _vol_cs="$(awk '/^voluntary_ctxt_switches:/ {print $2+0}' "/proc/${_pid}/status" 2>/dev/null || echo 0)"
        _nonvol_cs="$(awk '/^nonvoluntary_ctxt_switches:/ {print $2+0}' "/proc/${_pid}/status" 2>/dev/null || echo 0)"
    fi
    _delta_nvcs=0
    if [ "${PREV_NONVOL_CS:-0}" -gt 0 ] && [ "${_nonvol_cs}" -ge "${PREV_NONVOL_CS}" ]; then
        _delta_nvcs=$((_nonvol_cs - PREV_NONVOL_CS))
    fi
    PREV_NONVOL_CS="${_nonvol_cs}"

    # 5) TCP ソケット状態 (/proc/net/tcp & /proc/net/tcp6: 01=ESTAB, 08=CLOSE_WAIT, 06=TIME_WAIT, 03=SYN_RECV)
    _tcp_stats="$(awk '
        BEGIN { est=0; cw=0; tw=0; sr=0; }
        $1 ~ /^[0-9]+:/ {
            st = $4;
            if (st == "01") est++;
            else if (st == "08") cw++;
            else if (st == "06") tw++;
            else if (st == "03") sr++;
        }
        END { printf "%d %d %d %d", est, cw, tw, sr; }
    ' /proc/net/tcp /proc/net/tcp6 2>/dev/null || echo '0 0 0 0')"

    # 6) TCP ListenDrops (/proc/net/netstat)
    _listen_drops="0"
    if [ -r /proc/net/netstat ]; then
        _listen_drops="$(awk '
            /^TcpExt:/ {
                if (hdr == 0) {
                    for (i = 1; i <= NF; i++) if ($i == "ListenDrops") col = i;
                    hdr = 1;
                } else if (col > 0) {
                    print $col + 0;
                }
            }
        ' /proc/net/netstat 2>/dev/null | tail -n 1)"
        [ -z "${_listen_drops}" ] && _listen_drops="0"
    fi

    # 7) スレッド状態集計と上位スレッド抽出
    printf '%s\n' "${_ps_threads}" | awk \
        -v ts="${_ts}" \
        -v cnt="${PERF_COMPONENT}" \
        -v svc="${PERF_SERVICE}" \
        -v pid="${_pid}" \
        -v open_fds="${_open_fds}" \
        -v max_fds="${_max_fds}" \
        -v min_flt="${_min_flt}" \
        -v maj_flt="${_maj_flt}" \
        -v vol_cs="${_vol_cs}" \
        -v nonvol_cs="${_nonvol_cs}" \
        -v d_nvcs="${_delta_nvcs}" \
        -v tcp_s="${_tcp_stats}" \
        -v l_drops="${_listen_drops}" \
    'BEGIN {
        tot=0; r_cnt=0; d_cnt=0; s_cnt=0; z_cnt=0;
        t1_tid="-"; t1_name="-"; t1_cpu="0.0"; t1_st="-"; t1_wc="-";
        t2_name="-"; t2_cpu="0.0";
        split(tcp_s, tcp_a, " ");
        est = tcp_a[1]+0; cw = tcp_a[2]+0; tw = tcp_a[3]+0; sr = tcp_a[4]+0;
    }
    NF >= 9 {
        tot++;
        tid  = $2;
        pcpu = $4;
        st   = substr($6, 1, 1);
        wc   = $7;
        comm = $9;
        for (i = 10; i <= NF; i++) comm = comm "_" $i;

        if (st == "R") r_cnt++;
        else if (st == "D") d_cnt++;
        else if (st == "S" || st == "I") s_cnt++;
        else if (st == "Z") z_cnt++;

        if (tot == 1) {
            t1_tid = tid; t1_name = comm; t1_cpu = pcpu; t1_st = st; t1_wc = wc;
        } else if (tot == 2) {
            t2_name = comm; t2_cpu = pcpu;
        }
    }
    END {
        fd_pct = (max_fds > 0) ? (open_fds * 100.0 / max_fds) : 0.0;
        eval_st = "NORMAL";
        if (d_cnt >= 3 || z_cnt > 0 || fd_pct >= 85.0 || cw >= 20 || (l_drops + 0) > 0) {
            eval_st = "CRITICAL";
        } else if (d_cnt > 0 || fd_pct >= 70.0 || cw > 0 || d_nvcs >= 5000) {
            eval_st = "WARN";
        }
        printf "%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%.1f\t%s\t%s\t%s\t%.1f\t%d\t%d\t%.1f\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n",
            ts, cnt, svc, pid,
            tot, r_cnt, d_cnt, s_cnt, z_cnt,
            t1_tid, t1_name, t1_cpu+0, t1_st, t1_wc,
            t2_name, t2_cpu+0,
            open_fds+0, max_fds+0, fd_pct,
            min_flt+0, maj_flt+0, vol_cs+0, nonvol_cs+0, d_nvcs+0,
            est, cw, tw, sr, l_drops+0, eval_st;
    }' >> "${F_PROC_TSV}"
}

# --- 9. ④ -XX:ActiveProcessorCount 要否判断情報の収集・自動診断 ----------------
perf_collect_active_processor_diag() {
    _pid="$1"
    _ts="$2"

    # 1) ホスト物理コア数 (/proc/cpuinfo / nproc)
    _host_cpus="$(nproc --all 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 2)"

    # 2) cgroup v2 / v1 CPU クォータ・重み・スロットリング統計の読み取り
    _cg_ver="v2"
    _cg_quota="max"
    _cg_period="100000"
    _cg_weight="100"
    _nr_periods="0"
    _nr_throttled="0"
    _throttled_usec="0"

    if [ -r /sys/fs/cgroup/cpu.max ]; then
        _cg_ver="v2"
        _cg_quota="$(awk '{print $1}' /sys/fs/cgroup/cpu.max 2>/dev/null || echo max)"
        _cg_period="$(awk '{print $2}' /sys/fs/cgroup/cpu.max 2>/dev/null || echo 100000)"
        [ -r /sys/fs/cgroup/cpu.weight ] && _cg_weight="$(cat /sys/fs/cgroup/cpu.weight 2>/dev/null || echo 100)"
        if [ -r /sys/fs/cgroup/cpu.stat ]; then
            _nr_periods="$(awk '/^nr_periods/ {print $2+0}' /sys/fs/cgroup/cpu.stat 2>/dev/null || echo 0)"
            _nr_throttled="$(awk '/^nr_throttled/ {print $2+0}' /sys/fs/cgroup/cpu.stat 2>/dev/null || echo 0)"
            _throttled_usec="$(awk '/^throttled_usec/ {print $2+0}' /sys/fs/cgroup/cpu.stat 2>/dev/null || echo 0)"
        fi
    elif [ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
        _cg_ver="v1"
        _cg_quota="$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null || echo -1)"
        _cg_period="$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null || echo 100000)"
        [ -r /sys/fs/cgroup/cpu/cpu.shares ] && _cg_weight="$(cat /sys/fs/cgroup/cpu/cpu.shares 2>/dev/null || echo 1024)"
        if [ -r /sys/fs/cgroup/cpu/cpu.stat ]; then
            _nr_periods="$(awk '/^nr_periods/ {print $2+0}' /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null || echo 0)"
            _nr_throttled="$(awk '/^nr_throttled/ {print $2+0}' /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null || echo 0)"
            _ns="$(awk '/^throttled_time/ {print $2+0}' /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null || echo 0)"
            _throttled_usec=$((_ns / 1000))
        fi
    fi

    # 3) ECS メタデータ (または環境変数) からタスクCPU・コンテナCPU・同居コンテナ数を取得
    _task_cpu="${PERF_ECS_TASK_CPU:-2048}"
    _cnt_cpu="${PERF_ECS_CONTAINER_CPU:-768}"
    _cnt_num="${PERF_ECS_CONTAINER_COUNT:-4}"

    # 4) JVM 認識プロセッサ数 & 自動決定スレッド数 (jcmd VM.flags -all / VM.info)
    _explicit_apc="unset(-1)"
    _jvm_procs="${_host_cpus}"
    _par_gc="2"; _conc_gc="1"; _ci_comp="2"

    if [ -r "/proc/${_pid}/cmdline" ]; then
        _cmd_apc="$(tr '\0' '\n' < "/proc/${_pid}/cmdline" 2>/dev/null | sed -n 's/^-XX:ActiveProcessorCount=//p' | tail -n 1)"
        [ -n "${_cmd_apc}" ] && _explicit_apc="${_cmd_apc}"
    fi

    if command -v jcmd >/dev/null 2>&1; then
        _vm_flags="$(JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir="${PERF_TMP_DIR}" "${_pid}" VM.flags -all 2>/dev/null || true)"
        if [ -n "${_vm_flags}" ]; then
            _f_apc="$(printf '%s\n' "${_vm_flags}" | awk '
                /ActiveProcessorCount/ {
                    for (i=1; i<=NF; i++) {
                        if ($i ~ /^-XX:ActiveProcessorCount=/) { sub(/^-XX:ActiveProcessorCount=/, "", $i); print $i; exit }
                        if ($i == "=" && i < NF) { print $(i+1); exit }
                    }
                }' | head -n 1)"
            _f_pgc="$(printf '%s\n' "${_vm_flags}" | awk '
                /ParallelGCThreads/ {
                    for (i=1; i<=NF; i++) {
                        if ($i ~ /^-XX:ParallelGCThreads=/) { sub(/^-XX:ParallelGCThreads=/, "", $i); print $i; exit }
                        if ($i == "=" && i < NF) { print $(i+1); exit }
                    }
                }' | head -n 1)"
            _f_cgc="$(printf '%s\n' "${_vm_flags}" | awk '
                /ConcGCThreads/ {
                    for (i=1; i<=NF; i++) {
                        if ($i ~ /^-XX:ConcGCThreads=/) { sub(/^-XX:ConcGCThreads=/, "", $i); print $i; exit }
                        if ($i == "=" && i < NF) { print $(i+1); exit }
                    }
                }' | head -n 1)"
            _f_cic="$(printf '%s\n' "${_vm_flags}" | awk '
                /CICompilerCount/ {
                    for (i=1; i<=NF; i++) {
                        if ($i ~ /^-XX:CICompilerCount=/) { sub(/^-XX:CICompilerCount=/, "", $i); print $i; exit }
                        if ($i == "=" && i < NF) { print $(i+1); exit }
                    }
                }' | head -n 1)"
            [ -n "${_f_pgc}" ] && _par_gc="${_f_pgc}"
            [ -n "${_f_cgc}" ] && _conc_gc="${_f_cgc}"
            [ -n "${_f_cic}" ] && _ci_comp="${_f_cic}"
            if [ -n "${_f_apc}" ] && [ "${_f_apc}" != "-1" ]; then
                _explicit_apc="${_f_apc}"
                _jvm_procs="${_f_apc}"
            fi
        fi
    fi

    # LoadAvg
    _load_1m="0.00"
    [ -r /proc/loadavg ] && _load_1m="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0.00)"

    # 差分計算と診断ロジック (awk)
    _diag_out="$(awk \
        -v ts="${_ts}" \
        -v cnt="${PERF_COMPONENT}" \
        -v svc="${PERF_SERVICE}" \
        -v host_c="${_host_cpus}" \
        -v task_u="${_task_cpu}" \
        -v cnt_u="${_cnt_cpu}" \
        -v cnt_n="${_cnt_num}" \
        -v cg_v="${_cg_ver}" \
        -v cg_q="${_cg_quota}" \
        -v cg_p="${_cg_period}" \
        -v cg_w="${_cg_weight}" \
        -v exp_apc="${_explicit_apc}" \
        -v jvm_p="${_jvm_procs}" \
        -v par_gc="${_par_gc}" \
        -v conc_gc="${_conc_gc}" \
        -v ci_cmp="${_ci_comp}" \
        -v nr_p="${_nr_periods}" \
        -v nr_t="${_nr_throttled}" \
        -v t_usec="${_throttled_usec}" \
        -v prev_p="${PREV_CFS_PERIODS:-0}" \
        -v prev_t="${PREV_CFS_THROTTLED:-0}" \
        -v prev_u="${PREV_CFS_USEC:-0}" \
        -v l1m="${_load_1m}" \
    'BEGIN {
        # cgroup 実効 vCPU の計算
        if (cg_q != "max" && cg_q != "-1" && (cg_q + 0) > 0 && (cg_p + 0) > 0) {
            eff_vcpu = (cg_q + 0.0) / (cg_p + 0.0);
        } else if ((cnt_u + 0) > 0) {
            eff_vcpu = (cnt_u + 0.0) / 1024.0;
        } else if ((task_u + 0) > 0) {
            eff_vcpu = (task_u + 0.0) / 1024.0;
        } else {
            eff_vcpu = host_c + 0.0;
        }

        # OpenJDK 21 エルゴノミクスに基づく認識コア数 (明示指定がない場合)
        if (exp_apc != "unset(-1)" && (exp_apc + 0) > 0) {
            recog_p = exp_apc + 0;
        } else {
            # OpenJDK 21 (JDK-8281181修正済) は quota/period の切り上げ整数を認識する。
            # ただしコンテナ個別 quota が max の場合はタスク全体 quota または host_c を認識する。
            if (cg_q != "max" && cg_q != "-1" && (cg_q + 0) > 0 && (cg_p + 0) > 0) {
                q_vcpu = (cg_q + 0.0) / (cg_p + 0.0);
                recog_p = int(q_vcpu);
                if (q_vcpu > recog_p) recog_p++;
                if (recog_p < 1) recog_p = 1;
            } else if ((task_u + 0) > 0) {
                t_vcpu = (task_u + 0.0) / 1024.0;
                recog_p = int(t_vcpu);
                if (t_vcpu > recog_p) recog_p++;
                if (recog_p < 1) recog_p = 1;
            } else {
                recog_p = host_c + 0;
            }
        }

        fj_par = (recog_p > 1) ? (recog_p - 1) : 1;
        ut_io  = recog_p * 2;
        ut_wk  = recog_p * 16;

        d_p = (prev_p > 0 && nr_p >= prev_p) ? (nr_p - prev_p) : 0;
        d_t = (prev_t > 0 && nr_t >= prev_t) ? (nr_t - prev_t) : 0;
        t_ms = (t_usec + 0.0) / 1000.0;
        d_ms = (prev_u > 0 && t_usec >= prev_u) ? ((t_usec - prev_u) / 1000.0) : 0.0;
        t_rate = (d_p > 0) ? (d_t * 100.0 / d_p) : ((nr_p > 0) ? (nr_t * 100.0 / nr_p) : 0.0);

        # 推奨 ActiveProcessorCount の算出
        # Fargate マルチコンテナ構成 (front + back + adot + cwagent) ではコンテナ割当 vCPU の整数切り上げ (最低1)
        rec_apc = int(eff_vcpu + 0.49);
        if (rec_apc < 1) rec_apc = 1;
        if ((cnt_n + 0) > 1 && (task_u + 0) >= 2048 && rec_apc >= int((task_u + 0) / 1024)) {
            rec_apc = int((task_u + 0) / 1024) - 1;
            if (rec_apc < 1) rec_apc = 1;
        }

        # 要否判定ロジック
        if (eff_vcpu < 1.0 && t_rate >= 5.0) {
            judg = "REQUIRED_SUB_VCPU";
            reason = sprintf("実効割当%.2fvCPU(1vCPU未満)に対しJVMが%dコア相当スレッドを生成しCFSスロットリング率%.1f%%発生。-XX:ActiveProcessorCount=1 かつスレッド抑制が必要", eff_vcpu, recog_p, t_rate);
        } else if ((cnt_n + 0) > 1 && recog_p > rec_apc && t_rate >= 5.0) {
            judg = "REQUIRED_SET_LOWER";
            reason = sprintf("同一ECSタスク内%dコンテナ同居環境でJVMが%dコアと認識し過大スレッド生成(CFSスロットリング率%.1f%%)。サイドカー/他コンテナ共食い防止のため -XX:ActiveProcessorCount=%d の明示設定が必要", cnt_n, recog_p, t_rate, rec_apc);
        } else if ((cnt_n + 0) > 1 && exp_apc == "unset(-1)" && recog_p > rec_apc) {
            judg = "RECOMMENDED_PIN";
            reason = sprintf("OpenJDK21(JDK-8281181対応済)だが同一タスク内%dコンテナ同居のため、高負荷時のCPU競合予防として -XX:ActiveProcessorCount=%d の外出し明示設定を推奨", cnt_n, rec_apc);
        } else if (recog_p < rec_apc && t_rate < 1.0) {
            judg = "REQUIRED_INCREASE";
            reason = sprintf("実効%.2fvCPUに対しJVM認識コア数が%dに制限されており性能未発揮。-XX:ActiveProcessorCount=%d への引き上げが必要", eff_vcpu, recog_p, rec_apc);
        } else {
            judg = "OPTIMAL_OK";
            reason = sprintf("OpenJDK21が実効vCPU(%.2f)と整合する%dコアを認識しCFSスロットリング率%.1f%%で安定稼働中(現行設定で適正)", eff_vcpu, recog_p, t_rate);
        }

        printf "%s\t%s\t%s\t%d\t%s\t%s\t%d\t%s\t%s\t%s\t%.2f\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%.2f\t%.1f\t%.1f\t%s\t%d\t%s\t%s\n",
            ts, cnt, svc, host_c+0, task_u, cnt_u, cnt_n+0,
            cg_v, cg_q, cg_p, eff_vcpu, cg_w,
            exp_apc, recog_p, par_gc+0, conc_gc+0, ci_cmp+0, fj_par, ut_io, ut_wk,
            nr_p+0, nr_t+0, d_p, d_t, t_rate, t_ms, d_ms, l1m,
            rec_apc, judg, reason;
    }')"

    PREV_CFS_PERIODS="${_nr_periods}"
    PREV_CFS_THROTTLED="${_nr_throttled}"
    PREV_CFS_USEC="${_throttled_usec}"

    printf '%s\n' "${_diag_out}" >> "${F_CPU_TSV}"

    # 詳細診断レポートの更新
    {
        echo "--------------------------------------------------------------------------------"
        printf '[%s] ActiveProcessorCount Diagnostic Snapshot (Container=%s, Service=%s)\n' "${_ts}" "${PERF_COMPONENT}" "${PERF_SERVICE}"
        printf '%s\n' "${_diag_out}" | awk -F'\t' '{
            printf "  - Host / Task / Container CPU : Host=%s cores | Task=%s units | Container=%s units (Co-located=%s containers)\n", $4, $5, $6, $7;
            printf "  - cgroup (%s) Limit          : quota=%s us / period=%s us -> Effective=%.2f vCPU (weight/shares=%s)\n", $8, $9, $10, $11, $12;
            printf "  - JVM Processor Recognition   : ExplicitFlag=%s | Recognized=%s cores\n", $13, $14;
            printf "  - Derived JVM/JBoss Threads   : ParallelGC=%s | ConcGC=%s | JIT=%s | ForkJoin=%s | UndertowIO=%s | UndertowWorker=%s\n", $15, $16, $17, $18, $19, $20;
            printf "  - CFS Throttling Telemetry    : nr_periods=%s (+%s) | nr_throttled=%s (+%s) | ThrottleRate=%s%% | ThrottledTime=%sms (+%sms)\n", $21, $23, $22, $24, $25, $26, $27;
            printf "  - Recommended Flag & Verdict  : -XX:ActiveProcessorCount=%s  => [%s]\n", $29, $30;
            printf "  - Diagnosis Reason            : %s\n", $31;
        }'
    } >> "${F_CPU_RPT}"
}

# --- 10. ECS タスクメタデータ v4 からの CPU/コンテナ構成取得 ------------------
perf_fetch_ecs_cpu_metadata() {
    PERF_ECS_TASK_CPU="${ECS_TASK_CPU:-2048}"
    PERF_ECS_CONTAINER_CPU="${ECS_CONTAINER_CPU:-768}"
    PERF_ECS_CONTAINER_COUNT="${ECS_CONTAINER_COUNT:-4}"

    if [ -n "${ECS_CONTAINER_METADATA_URI_V4:-}" ]; then
        _task_json="$(curl -fsS --max-time 2 "${ECS_CONTAINER_METADATA_URI_V4}/task" 2>/dev/null || true)"
        if [ -n "${_task_json}" ]; then
            _t_cpu="$(printf '%s' "${_task_json}" | sed -n 's/.*"Limits"[[:space:]]*:[[:space:]]*{[^}]*"CPU"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | head -n 1)"
            if [ -n "${_t_cpu}" ]; then
                # Task Limits.CPU が vCPU 単位 (例: 2) の場合は 1024 倍、ユニット単位ならそのまま
                PERF_ECS_TASK_CPU="$(awk -v c="${_t_cpu}" 'BEGIN { if (c <= 64) printf "%d", c * 1024; else printf "%d", c }')"
            fi
            _c_cnt="$(printf '%s' "${_task_json}" | grep -o '"DockerId"' 2>/dev/null | wc -l | tr -d ' ')"
            [ "${_c_cnt:-0}" -gt 0 ] && PERF_ECS_CONTAINER_COUNT="${_c_cnt}"
        fi
        _cnt_json="$(curl -fsS --max-time 2 "${ECS_CONTAINER_METADATA_URI_V4}" 2>/dev/null || true)"
        if [ -n "${_cnt_json}" ]; then
            _c_cpu="$(printf '%s' "${_cnt_json}" | sed -n 's/.*"Limits"[[:space:]]*:[[:space:]]*{[^}]*"CPU"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | head -n 1)"
            [ -n "${_c_cpu}" ] && [ "${_c_cpu}" != "0" ] && PERF_ECS_CONTAINER_CPU="${_c_cpu}"
        fi
    fi
    export PERF_ECS_TASK_CPU PERF_ECS_CONTAINER_CPU PERF_ECS_CONTAINER_COUNT
}

# --- 11. バックグラウンド定期収集デーモン (10秒間隔等) ------------------------
perf_metrics_daemon_loop() {
    echo "[PERF-METRICS] Background collector daemon started (PID=$$, Interval=${PERF_METRICS_INTERVAL}s)"
    perf_fetch_ecs_cpu_metadata

    # JBoss EAP プロセスの起動待機 (最大180秒)
    _wait_sec=0
    _target_pid=""
    while [ "${_wait_sec}" -lt 180 ]; do
        _target_pid="$(perf_find_jboss_pid || true)"
        if [ -n "${_target_pid}" ]; then
            break
        fi
        sleep 2
        _wait_sec=$((_wait_sec + 2))
    done

    if [ -z "${_target_pid}" ]; then
        echo "[PERF-METRICS] WARN: JBoss EAP process not detected within 180s; collector daemon will keep polling..." >&2
    else
        echo "[PERF-METRICS] Attached to JBoss EAP process (PID=${_target_pid}). Writing metrics to ${PERF_LOGICAL_CURRENT_DIR} (${PERF_OUT_DIR})"
    fi

    while :; do
        _target_pid="$(perf_find_jboss_pid || true)"
        if [ -n "${_target_pid}" ] && ( kill -0 "${_target_pid}" 2>/dev/null || [ "${PERF_ALLOW_MOCK_PID:-false}" = "true" ] ); then
            _now_ts="$(perf_now_jst)"
            perf_collect_jboss_cli            "${_target_pid}" "${_now_ts}" || true
            perf_collect_jvm_heap_gc          "${_target_pid}" "${_now_ts}" || true
            perf_collect_process_threads      "${_target_pid}" "${_now_ts}" || true
            perf_collect_active_processor_diag "${_target_pid}" "${_now_ts}" || true
        fi

        # ワンショットテスト用: PERF_MAX_ITERATIONS が指定されていれば回数到達で終了
        if [ -n "${PERF_MAX_ITERATIONS:-}" ] && [ "${PERF_MAX_ITERATIONS}" -gt 0 ]; then
            PERF_ITER_COUNT=$(( ${PERF_ITER_COUNT:-0} + 1 ))
            if [ "${PERF_ITER_COUNT}" -ge "${PERF_MAX_ITERATIONS}" ]; then
                echo "[PERF-METRICS] Reached PERF_MAX_ITERATIONS=${PERF_MAX_ITERATIONS}. Exiting daemon."
                break
            fi
        fi

        sleep "${PERF_METRICS_INTERVAL}"
    done
}

# --- 12. コンテナ起動時エントリポイント連携フック -----------------------------
# efs-entrypoint.sh から `. /usr/local/bin/perf-metrics.sh && perf_metrics_setup_before_exec`
# または `. /usr/local/bin/perf-metrics.sh` として呼び出される。
perf_metrics_setup_before_exec() {
    if [ "${PERF_SETUP_DONE:-0}" = "1" ] && [ "${PERF_FORCE_REINIT:-false}" != "true" ]; then
        return 0
    fi
    PERF_SETUP_DONE=1
    export PERF_SETUP_DONE

    if ! is_perf_metrics_enabled; then
        echo "[PERF-METRICS] Status: DISABLED (ENABLE_PERF_METRICS=${ENABLE_PERF_METRICS:-false})"
        return 0
    fi

    PERF_ROLE="$(perf_normalize_role)"
    PERF_COMPONENT="${PERF_ROLE}"
    PERF_SERVICE="$(perf_normalize_service)"
    PERF_METRICS_INTERVAL="${PERF_METRICS_INTERVAL:-10}"
    PERF_TMP_DIR="${PERF_TMP_DIR:-/tmp}"
    PERF_LOG_ID="${LOG_ID:-$(date +%Y%m%d%H%M%S)-perf}"

    # 論理パス (/mnt/logs/front/logs/intra-web/mid/current) と実体書き込みパスの決定
    PERF_LOGICAL_CURRENT_DIR="/mnt/logs/${PERF_COMPONENT}/logs/${PERF_SERVICE}/mid/current"
    if [ -n "${LOG_OWN:-}" ] && [ -d "${LOG_OWN}" ]; then
        PERF_OUT_DIR="${LOG_OWN}"
    elif [ -d "${PERF_LOGICAL_CURRENT_DIR}" ]; then
        PERF_OUT_DIR="${PERF_LOGICAL_CURRENT_DIR}"
    else
        mkdir -p "/mnt/logs/${PERF_COMPONENT}/logs/${PERF_SERVICE}/mid/${PERF_LOG_ID}" 2>/dev/null || true
        ln -sfn "${PERF_LOG_ID}" "${PERF_LOGICAL_CURRENT_DIR}" 2>/dev/null || mkdir -p "${PERF_LOGICAL_CURRENT_DIR}" 2>/dev/null || true
        PERF_OUT_DIR="$(cd "${PERF_LOGICAL_CURRENT_DIR}" 2>/dev/null && pwd -P || printf '%s' "${PERF_LOGICAL_CURRENT_DIR}")"
    fi

    export PERF_ROLE PERF_COMPONENT PERF_SERVICE PERF_METRICS_INTERVAL PERF_TMP_DIR PERF_LOG_ID PERF_LOGICAL_CURRENT_DIR PERF_OUT_DIR

    # 1) 起動時バナー出力 (性能試験設定が有効であることをコンテナ起動時に明確に表示)
    cat <<EOF
================================================================================
[PERF-METRICS] ★ JMeter Performance Test Metrics Collection: ENABLED ★
[PERF-METRICS]   Build/Runtime Flag : ENABLE_PERF_METRICS=${ENABLE_PERF_METRICS}
[PERF-METRICS]   Container Role     : ${PERF_COMPONENT} (ROLE=${PERF_ROLE})
[PERF-METRICS]   ECS Service Name   : ${PERF_SERVICE}
[PERF-METRICS]   Sampling Interval  : ${PERF_METRICS_INTERVAL} seconds
[PERF-METRICS]   Logical Output Dir : ${PERF_LOGICAL_CURRENT_DIR}
[PERF-METRICS]   Physical Write Dir : ${PERF_OUT_DIR}
[PERF-METRICS]   Output Files:
[PERF-METRICS]     [1] DB Pool & CLI : ${PERF_LOGICAL_CURRENT_DIR}/01_jboss_cli_stats.tsv
[PERF-METRICS]     [2] Heap/GC & JFR : ${PERF_LOGICAL_CURRENT_DIR}/02_jvm_heap_gc_stats.tsv
[PERF-METRICS]                         ${PERF_LOGICAL_CURRENT_DIR}/02_flight_recording.jfr
[PERF-METRICS]     [3] top/ps/Thread : ${PERF_LOGICAL_CURRENT_DIR}/03_process_thread_stats.tsv
[PERF-METRICS]     [4] ActiveCPU Diag: ${PERF_LOGICAL_CURRENT_DIR}/04_active_processor_diag.tsv
================================================================================
EOF

    # 2) standalone.xml の statistics-enabled="true" 自動有効化
    _xml_target=""
    if [ -n "${CONF_DIR:-}" ] && [ -n "${JBOSS_CONFIG_FILE:-}" ]; then
        _xml_target="${CONF_DIR}/${JBOSS_CONFIG_FILE}"
    elif [ -n "${JBOSS_HOME:-}" ]; then
        _xml_target="${JBOSS_HOME}/standalone/configuration/${SERVER_CONFIG:-standalone.xml}"
    fi
    if [ -n "${_xml_target}" ] && [ -f "${_xml_target}" ]; then
        perf_enable_xml_statistics "${_xml_target}"
    fi

    # 3) JFR / jstat / jcmd / NMT 用の JVM オプション自動注入 (readonlyRootFilesystem=true 対応)
    mkdir -p "${PERF_TMP_DIR}/jfr-repo" 2>/dev/null || true
    _perf_jvm_flags="-XX:-PerfDisableSharedMem -XX:+StartAttachListener -Djava.io.tmpdir=${PERF_TMP_DIR} -XX:NativeMemoryTracking=summary"
    if [ "${PERF_ENABLE_JFR:-true}" = "true" ]; then
        _perf_jvm_flags="${_perf_jvm_flags} -XX:FlightRecorderOptions=repository=${PERF_TMP_DIR}/jfr-repo -XX:StartFlightRecording=name=perf-continuous,settings=profile,disk=true,maxage=1h,maxsize=250M,dumponexit=true,filename=${PERF_OUT_DIR}/02_flight_recording.jfr"
    fi
    case "${JAVA_OPTS:-}" in
        *StartAttachListener*) ;;
        *)
            JAVA_OPTS="${JAVA_OPTS:+${JAVA_OPTS} }${_perf_jvm_flags}"
            export JAVA_OPTS
            ;;
    esac

    # 4) 出力ファイル初期化 & バックグラウンド収集デーモン起動
    perf_init_output_files
    if [ "${PERF_DAEMON_AUTOSTART:-true}" = "true" ]; then
        perf_metrics_daemon_loop &
        PERF_DAEMON_PID=$!
        PERF_COLLECTOR_PID="${PERF_DAEMON_PID}"
        export PERF_DAEMON_PID PERF_COLLECTOR_PID
    fi
}

# スクリプトが直接実行された場合、または source された場合のサブコマンド分岐
case "${1:-}" in
    build-setup|--build-setup)
        perf_metrics_build_setup
        ;;
    start-daemon|--start-daemon)
        perf_metrics_setup_before_exec
        ;;
    collect-once|--collect-once)
        PERF_DAEMON_AUTOSTART=false
        perf_metrics_setup_before_exec
        perf_fetch_ecs_cpu_metadata
        _pid="${2:-$(perf_find_jboss_pid || echo $$)}"
        _ts="$(perf_now_jst)"
        perf_collect_jboss_cli             "${_pid}" "${_ts}" || true
        perf_collect_jvm_heap_gc           "${_pid}" "${_ts}" || true
        perf_collect_process_threads       "${_pid}" "${_ts}" || true
        perf_collect_active_processor_diag "${_pid}" "${_ts}" || true
        ;;
    *)
        if [ "${PERF_SKIP_AUTO_SETUP:-false}" != "true" ]; then
            perf_metrics_setup_before_exec
        fi
        ;;
esac
