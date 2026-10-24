#!/usr/bin/env bash
# ==============================================================================
# tests/test_perf_metrics_e2e.sh
# ==============================================================================
# End-to-End verification harness for docker/base/perf-metrics.sh
# Tests:
#   1. ENABLE_PERF_METRICS=false (disabled mode check)
#   2. --build-setup mode
#   3. ENABLE_PERF_METRICS=true (sourced mode + collector daemon execution)
#      across all 4 service & container combinations:
#        - /mnt/logs/front/logs/intra-web/mid/current
#        - /mnt/logs/back/logs/intra-api/mid/current
#        - /mnt/logs/front/logs/inter-api/mid/current
#        - /mnt/logs/back/logs/sf-api/mid/current
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PERF_SCRIPT="${REPO_ROOT}/docker/base/perf-metrics.sh"
TEST_WORK_ROOT="${REPO_ROOT}/tests/sample_output"

rm -rf "${TEST_WORK_ROOT}"
mkdir -p "${TEST_WORK_ROOT}/mock_bin" "${TEST_WORK_ROOT}/mock_jboss/bin" "${TEST_WORK_ROOT}/mock_jboss/standalone/configuration"

# ------------------------------------------------------------------------------
# Create realistic mock CLI tools (jboss-cli.sh, jstat, jcmd, jfr, top, ps, ss)
# so that perf-metrics.sh executes its full parsing pipeline on Windows Git Bash
# ------------------------------------------------------------------------------
cat << 'EOF' > "${TEST_WORK_ROOT}/mock_jboss/standalone/configuration/standalone.xml"
<?xml version="1.0" encoding="UTF-8"?>
<server xmlns="urn:jboss:domain:20.0">
    <subsystem xmlns="urn:jboss:domain:datasources:7.0">
        <datasources>
            <xa-datasource jndi-name="java:jboss/datasources/MySQLXADS" pool-name="MySQLXADS" enabled="true" statistics-enabled="false">
                <xa-datasource-Class>com.mysql.cj.jdbc.MysqlXADataSource</xa-datasource-Class>
            </xa-datasource>
        </datasources>
    </subsystem>
    <subsystem xmlns="urn:jboss:domain:transactions:6.0">
        <core-environment node-identifier="1"/>
        <coordinator-environment statistics-enabled="false"/>
    </subsystem>
    <subsystem xmlns="urn:jboss:domain:undertow:14.0" statistics-enabled="false">
        <server name="default-server">
            <http-listener name="default" socket-binding="http" statistics-enabled="false"/>
        </server>
    </subsystem>
</server>
EOF

cat << 'EOF' > "${TEST_WORK_ROOT}/mock_jboss/bin/jboss-cli.sh"
#!/usr/bin/env bash
cat << 'JSON_OUT'
{
    "outcome" => "success",
    "result" => {
        "step-1" => {
            "outcome" => "success",
            "result" => {
                "data-source" => {},
                "xa-data-source" => {
                    "MySQLXADS" => {
                        "statistics" => {
                            "pool" => {
                                "ActiveCount" => 20,
                                "AvailableCount" => 12,
                                "AverageBlockingTime" => 4L,
                                "AverageCreationTime" => 15L,
                                "AverageGetTime" => 2L,
                                "BlockingFailureCount" => 0,
                                "CreatedCount" => 20,
                                "DestroyedCount" => 0,
                                "IdleCount" => 12,
                                "InUseCount" => 8,
                                "MaxCreationTime" => 45L,
                                "MaxGetTime" => 18L,
                                "MaxPoolTime" => 12000L,
                                "MaxUsedCount" => 16,
                                "MaxWaitCount" => 2,
                                "MaxWaitTime" => 12L,
                                "TimedOut" => 0,
                                "TotalBlockingTime" => 24L,
                                "TotalCreationTime" => 300L,
                                "TotalGetTime" => 950L,
                                "WaitCount" => 0
                            },
                            "jdbc" => {
                                "PreparedStatementCacheAccessCount" => 1420L,
                                "PreparedStatementCacheAddCount" => 85L,
                                "PreparedStatementCacheCurrentSize" => 85,
                                "PreparedStatementCacheDeleteCount" => 0L,
                                "PreparedStatementCacheHitCount" => 1335L,
                                "PreparedStatementCacheMissCount" => 85L
                            }
                        }
                    }
                }
            }
        },
        "step-2" => {
            "outcome" => "success",
            "result" => {
                "server" => {
                    "default-server" => {
                        "http-listener" => {
                            "default" => {
                                "bytes-received" => 5242880L,
                                "bytes-sent" => 18874368L,
                                "error-count" => 2,
                                "max-processing-time" => 340L,
                                "processing-time" => 48200L,
                                "request-count" => 1250
                            }
                        }
                    }
                }
            }
        },
        "step-3" => {
            "outcome" => "success",
            "result" => {
                "worker" => {
                    "default" => {
                        "busy-task-thread-count" => 6,
                        "core-pool-size" => 16,
                        "io-thread-count" => 4,
                        "max-pool-size" => 32,
                        "queue-size" => 0,
                        "rejected-count" => 0,
                        "task-max-threads" => 32
                    }
                }
            }
        },
        "step-4" => {
            "outcome" => "success",
            "result" => {
                "number-of-aborted-transactions" => 1L,
                "number-of-application-rollbacks" => 1L,
                "number-of-committed-transactions" => 980L,
                "number-of-heuristics" => 0L,
                "number-of-inflight-transactions" => 3L,
                "number-of-nested-transactions" => 0L,
                "number-of-resource-rollbacks" => 0L,
                "number-of-system-rollbacks" => 0L,
                "number-of-timed-out-transactions" => 0L,
                "number-of-transactions" => 984L
            }
        }
    }
}
JSON_OUT
EOF
chmod +x "${TEST_WORK_ROOT}/mock_jboss/bin/jboss-cli.sh"

cat << 'EOF' > "${TEST_WORK_ROOT}/mock_bin/jstat"
#!/usr/bin/env bash
ARGS="$*"
case "$ARGS" in
  *-gccause*)
    echo "  S0     S1     E      O      M     CCS    YGC     YGCT    FGC    FGCT    CGC    CGCT     GCT    LGCC                 GCC                 "
    echo "  0.00 100.00  50.00  37.43  95.03  90.46     42    0.385     0    0.000    12    0.045    0.430 G1 Evacuation Pause  No GC               "
    ;;
  *-gc*)
    echo " S0C    S1C    S0U    S1U      EC       EU        OC         OU       MC     MU    CCSC   CCSU   YGC     YGCT    FGC    FGCT    CGC    CGCT     GCT   "
    echo " 0.0   24576.0  0.0   24576.0 622592.0 311296.0 1449984.0   542720.0  135168.0 128450.2 16384.0 14820.5     42    0.385     0    0.000    12    0.045    0.430"
    ;;
  *-class*)
    echo "Loaded  Bytes  Unloaded  Bytes     Time   "
    echo " 18450 36240.5       12    18.4       8.42"
    ;;
  *-compiler*)
    echo "Compiled Failed Invalid   Time   FailedType FailedMethod"
    echo "   14280      0       0    19.85          0             "
    ;;
esac
EOF
chmod +x "${TEST_WORK_ROOT}/mock_bin/jstat"

cat << 'EOF' > "${TEST_WORK_ROOT}/mock_bin/jcmd"
#!/usr/bin/env bash
if [ $# -eq 0 ]; then
  echo "12345 /opt/jboss-eap/jboss-modules.jar -mp /opt/jboss-eap/modules org.jboss.as.standalone"
  exit 0
fi
PID="$1"
shift
CMD="$*"
case "$CMD" in
  *GC.heap_info*)
    cat << 'OUT'
12345:
 garbage-first heap   total 2097152K, used 878592K [0x0000000780000000, 0x0000000800000000)
  region size 1024K, 328 young (335872K), 24 survivors (24576K)
 Metaspace       used 128450K, committed 135168K, reserved 1179648K
  class space    used 14820K, committed 16384K, reserved 1048576K
OUT
    ;;
  *VM.native_memory*)
    cat << 'OUT'
12345:
Native Memory Tracking:
Total: reserved=3845120KB, committed=2412544KB
-                 Java Heap (reserved=2097152KB, committed=2097152KB)
                            (mmap: reserved=2097152KB, committed=2097152KB)
-                     Class (reserved=1064960KB, committed=16384KB)
-                    Thread (reserved=148480KB, committed=148480KB)
                            (thread #142)
-                      Code (reserved=253952KB, committed=68420KB)
-                        GC (reserved=112640KB, committed=94208KB)
OUT
    ;;
  *Compiler.codecache*)
    cat << 'OUT'
12345:
CodeCache: size=245760Kb used=66810Kb max_used=67120Kb free=178950Kb
 bounds [0x00007f8a10000000, 0x00007f8a1f000000, 0x00007f8a1f000000]
 total_blobs=15420 nmethods=14110 adapters=1210
 compilation: enabled
OUT
    ;;
  *JFR.check*)
    cat << 'OUT'
12345:
Recording 1: name=perf-continuous maxsize=250.0MB maxage=2h (running)
OUT
    ;;
  *JFR.dump*)
    # Extract filename=...
    FILE_ARG="$(echo "$CMD" | sed -n 's/.*filename=\([^ ]*\).*/\1/p')"
    if [ -n "$FILE_ARG" ]; then
      echo "MOCK_JFR_BINARY_RECORDING_HEADER_OPENJDK21" > "$FILE_ARG"
    fi
    echo "12345:"
    echo "Dumped recording \"perf-continuous\", 4.2 MB written to:"
    echo "${FILE_ARG}"
    ;;
  *VM.flags*)
    cat << 'OUT'
12345:
-XX:ActiveProcessorCount=2 -XX:CICompilerCount=2 -XX:ConcGCThreads=1 -XX:G1HeapRegionSize=1048576 -XX:InitialHeapSize=2147483648 -XX:MaxHeapSize=2147483648 -XX:MaxNewSize=1287651328 -XX:MinHeapDeltaBytes=1048576 -XX:NativeMemoryTracking=summary -XX:NonNMethodCodeHeapSize=5825164 -XX:NonProfiledCodeHeapSize=122916538 -XX:ParallelGCThreads=2 -XX:-PerfDisableSharedMem -XX:ProfiledCodeHeapSize=122916538 -XX:ReservedCodeCacheSize=251658240 -XX:+SegmentedCodeCache -XX:+StartAttachListener -XX:+UseCompressedClassPointers -XX:+UseCompressedOops -XX:+UseG1GC
OUT
    ;;
  *VM.info*)
    cat << 'OUT'
12345:
# JRE version: OpenJDK Runtime Environment (Red_Hat-21.0.5.0.11-1) (21.0.5+11-LTS) (build 21.0.5+11-LTS)
# Java VM: OpenJDK 64-Bit Server VM (Red_Hat-21.0.5.0.11-1) (21.0.5+11-LTS, mixed mode, sharing, tiered, compressed oops, compressed class ptrs, g1 gc, linux-amd64)
container (cgroup) information:
container_type: cgroupv2
cpu_cpuset_cpus: 0-7
cpu_memory_nodes: 0
active_processor_count: 2
cpu_quota: 200000
cpu_period: 100000
cpu_shares: 1024
OUT
    ;;
esac
EOF
chmod +x "${TEST_WORK_ROOT}/mock_bin/jcmd"

cat << 'EOF' > "${TEST_WORK_ROOT}/mock_bin/jfr"
#!/usr/bin/env bash
cat << 'OUT'
 Version: 2.1
 Chunks: 1
 Start: 2026-10-24 13:00:00 (UTC)
 Duration: 30 s

 Event Type                              Count  Size (bytes)
=============================================================
 jdk.ObjectAllocationSample               4210        134720
 jdk.ExecutionSample                      1850         44400
 jdk.G1GarbageCollection                    12           480
 jdk.GCPhasePause                           48          1920
 jdk.CPUInformation                          1           312
 jdk.ContainerConfiguration                  1           256
 jdk.ContainerCPUUsage                      30          1440
 jdk.ContainerCPUThrottling                 30          1200
OUT
EOF
chmod +x "${TEST_WORK_ROOT}/mock_bin/jfr"

cat << 'EOF' > "${TEST_WORK_ROOT}/mock_bin/top"
#!/usr/bin/env bash
cat << 'OUT'
top - 22:15:10 up 14 days,  3:22,  0 users,  load average: 1.42, 1.18, 0.95
Threads: 145 total,   2 running, 143 sleeping,   0 stopped,   0 zombie
%Cpu(s): 34.2 us,  4.8 sy,  0.0 ni, 59.5 id,  0.2 wa,  0.0 hi,  1.3 si,  0.0 st
MiB Mem :   7982.4 total,   2140.2 free,   3120.8 used,   2721.4 buff/cache
MiB Swap:      0.0 total,      0.0 free,      0.0 used.   4512.0 avail Mem

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
  12381 jboss     20   0 4825120   2.3g  32400 R  28.5  29.8   0:14.22 default task-3
  12382 jboss     20   0 4825120   2.3g  32400 R  19.2  29.8   0:11.05 default task-7
  12355 jboss     20   0 4825120   2.3g  32400 S   6.4  29.8   0:04.18 G1 Conc#0
  12360 jboss     20   0 4825120   2.3g  32400 S   4.1  29.8   0:03.90 C2 CompilerThre
  12370 jboss     20   0 4825120   2.3g  32400 S   2.8  29.8   0:02.15 default I/O-2
OUT
EOF
chmod +x "${TEST_WORK_ROOT}/mock_bin/top"

cat << 'EOF' > "${TEST_WORK_ROOT}/mock_bin/ps"
#!/usr/bin/env bash
ARGS="$*"
if echo "$ARGS" | grep -q "min_flt"; then
  echo "4820 0"
else
  cat << 'OUT'
12345 12381   0 28.5 29.8 Rl   -                        00:00:14 default task-3
12345 12382   1 19.2 29.8 Rl   -                        00:00:11 default task-7
12345 12355   0  6.4 29.8 Sl   futex_wait_queue_me      00:00:04 G1 Conc#0
12345 12360   1  4.1 29.8 Sl   futex_wait_queue_me      00:00:03 C2 CompilerThre
12345 12370   0  2.8 29.8 Sl   ep_poll                  00:00:02 default I/O-2
OUT
fi
EOF
chmod +x "${TEST_WORK_ROOT}/mock_bin/ps"

export PATH="${TEST_WORK_ROOT}/mock_bin:${PATH}"
export JBOSS_HOME="${TEST_WORK_ROOT}/mock_jboss"

# ------------------------------------------------------------------------------
# Test 1: ENABLE_PERF_METRICS=false
# ------------------------------------------------------------------------------
echo "=== [Test 1] ENABLE_PERF_METRICS=false ==="
export ENABLE_PERF_METRICS="false"
export Component_name="front"
export Service_Name="intra-web"
export LOG_OWN="${TEST_WORK_ROOT}/disabled_test/mnt/logs/front/logs/intra-web/mid/current"
mkdir -p "${LOG_OWN}"

OUTPUT_DISABLED="$(sh "${PERF_SCRIPT}" 2>&1)"
echo "${OUTPUT_DISABLED}"
if ! echo "${OUTPUT_DISABLED}" | grep -q "DISABLED"; then
  echo "FAIL: Expected DISABLED message when ENABLE_PERF_METRICS=false"
  exit 1
fi
if [ -f "${LOG_OWN}/01_jboss_cli_stats.tsv" ]; then
  echo "FAIL: Metrics files should not be created when ENABLE_PERF_METRICS=false"
  exit 1
fi
echo "PASS: Test 1 (ENABLE_PERF_METRICS=false)"

# ------------------------------------------------------------------------------
# Test 2: --build-setup mode
# ------------------------------------------------------------------------------
echo "=== [Test 2] --build-setup mode ==="
sh "${PERF_SCRIPT}" --build-setup
echo "PASS: Test 2 (--build-setup)"

# ------------------------------------------------------------------------------
# Test 3: ENABLE_PERF_METRICS=true across 4 container/service combinations
# ------------------------------------------------------------------------------
run_combination_test() {
  local comp="$1"
  local svc="$2"
  echo "=== [Test 3] Testing Component=${comp}, Service=${svc} ==="

  local base_mnt="${TEST_WORK_ROOT}/mnt/logs/${comp}/logs/${svc}/mid"
  local task_dir="${base_mnt}/20261024-221500-a1b2c3d4"
  local current_link="${base_mnt}/current"
  mkdir -p "${task_dir}"
  ln -sfn "${task_dir}" "${current_link}"

  # Copy fresh standalone.xml
  cp "${TEST_WORK_ROOT}/mock_jboss/standalone/configuration/standalone.xml" "${TEST_WORK_ROOT}/mock_jboss/standalone/configuration/standalone.xml.bak"

  export ENABLE_PERF_METRICS="true"
  export PERF_FORCE_REINIT="true"
  export PERF_ALLOW_MOCK_PID="true"
  export PERF_TARGET_PID="12345"
  export Component_name="${comp}"
  export Service_Name="${svc}"
  export LOG_BASE="${TEST_WORK_ROOT}/mnt/logs/${comp}/logs/${svc}"
  export LOG_MID="${base_mnt}"
  export LOG_OWN="${current_link}"
  export PERF_METRICS_OUTPUT_DIR="${current_link}"
  export PERF_METRICS_INTERVAL="1"
  export PERF_MAX_ITERATIONS="2"
  export JAVA_OPTS="-Xms2048m -Xmx2048m"

  # Source perf-metrics.sh as entrypoint.sh does
  # shellcheck disable=SC1090
  . "${PERF_SCRIPT}"

  # Wait for collector daemon to complete 2 cycles
  if [ -n "${PERF_COLLECTOR_PID:-}" ]; then
    wait "${PERF_COLLECTOR_PID}" 2>/dev/null || true
  fi

  # Verify standalone.xml statistics-enabled="true"
  if ! grep -q 'statistics-enabled="true"' "${JBOSS_HOME}/standalone/configuration/standalone.xml"; then
    echo "FAIL: standalone.xml did not have statistics-enabled=true enabled"
    exit 1
  fi

  # Verify JAVA_OPTS flags
  case "${JAVA_OPTS}" in
    *-XX:-PerfDisableSharedMem*-XX:+StartAttachListener*)
      echo "  [OK] JAVA_OPTS contains attach & perf shared mem flags"
      ;;
    *)
      echo "FAIL: JAVA_OPTS missing expected flags: ${JAVA_OPTS}"
      exit 1
      ;;
  esac

  # Verify all required output files in /mnt/logs/<comp>/logs/<svc>/mid/current
  for req_file in \
    "00_perf_metrics_startup_env.txt" \
    "01_jboss_cli_stats.tsv" \
    "01_jboss_cli_raw.log" \
    "02_jvm_heap_gc_stats.tsv" \
    "02_jcmd_jfr_detail.log" \
    "02_flight_recording.jfr" \
    "03_process_thread_stats.tsv" \
    "03_top_ps_detail.log" \
    "04_active_processor_diag.tsv" \
    "04_active_processor_report.txt"
  do
    if [ ! -s "${current_link}/${req_file}" ]; then
      echo "FAIL: Missing or empty file ${current_link}/${req_file}"
      exit 1
    fi
    local lines
    lines="$(wc -l < "${current_link}/${req_file}")"
    echo "  [OK] ${req_file} (${lines} lines)"
  done
}

run_combination_test "front" "intra-web"
run_combination_test "back"  "intra-api"
run_combination_test "front" "inter-api"
run_combination_test "back"  "sf-api"

echo "=== ALL E2E SHELL TESTS PASSED SUCCESSFULLY ==="
