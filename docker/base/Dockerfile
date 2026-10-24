# syntax=docker/dockerfile:1
# =============================================================================
# base イメージ (Red Hat UBI 9.8 + Red Hat build of OpenJDK 21 + JBoss EAP 8.1)
#
# front / back の各 Dockerfile が FROM で参照する共通ベース。
#   - Red Hat UBI 9.8 ベース + Red Hat build of OpenJDK 21 (java-21-openjdk-devel)
#     および procps-ng (top, ps) 等の導入
#   - EFS マウントポイント (/mnt/logs, /mnt/data) のディレクトリ作成
#   - readonlyRootFilesystem=true 対応のエントリポイントスクリプト配置
#   - JMeter 性能試験用メトリクス収集モジュール (perf-metrics.sh) の配置と
#     ビルド引数 ENABLE_PERF_METRICS による有効/無効切り替え
#   - JBoss EAP 8.1 の configuration を configuration-seed へ退避 (seed 方式)
#
# ビルド例:
#   # 本番用 (性能試験メトリクス無効 = デフォルト)
#   docker build -t myapp-base:latest docker/base
#
#   # JMeter 性能試験用 (メトリクス収集有効)
#   docker build -t myapp-base:perf --build-arg ENABLE_PERF_METRICS=true docker/base
# =============================================================================
ARG BASE_IMAGE=registry.access.redhat.com/ubi9/ubi:9.8
FROM ${BASE_IMAGE}

USER root

# 1. Red Hat build of OpenJDK 21 (jstat, jcmd, jfr 同梱の devel パッケージ) と
#    procps-ng (top, ps) 等の必須パッケージ導入
RUN if command -v dnf >/dev/null 2>&1; then \
        dnf install -y --nodocs --disableplugin=subscription-manager \
            java-21-openjdk-devel \
            procps-ng \
            findutils \
            tar \
            gzip \
            shadow-utils \
            curl-minimal \
        && dnf clean all \
        && rm -rf /var/cache/dnf; \
    fi

ARG JBOSS_HOME=/opt/jboss-eap
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
    JBOSS_HOME=${JBOSS_HOME} \
    JBOSS_CONF_DIR=${JBOSS_HOME}/standalone/configuration \
    JBOSS_CONF_SEED_DIR=${JBOSS_HOME}/standalone/configuration-seed \
    PATH=/usr/lib/jvm/java-21-openjdk/bin:${JBOSS_HOME}/bin:${PATH}

ENV SERVER_CONFIG=standalone.xml \
    EXTRASLB_TRUSTSTORE_TYPE=JKS

# EFS のマウントポイントと基本ディレクトリ作成
RUN mkdir -p /mnt/logs /mnt/data /webapp "${JBOSS_HOME}"

# エントリポイントと性能試験用メトリクス収集モジュール (1ファイル集約版) の配置
COPY entrypoint.sh        /usr/local/bin/efs-entrypoint.sh
COPY entrypoint.taskid.sh /usr/local/bin/efs-entrypoint-taskid.sh
COPY perf-metrics.sh      /usr/local/bin/perf-metrics.sh
RUN chmod 0755 /usr/local/bin/efs-entrypoint.sh \
               /usr/local/bin/efs-entrypoint-taskid.sh \
               /usr/local/bin/perf-metrics.sh \
    && sed -i 's/\r$//' /usr/local/bin/efs-entrypoint.sh \
                        /usr/local/bin/efs-entrypoint-taskid.sh \
                        /usr/local/bin/perf-metrics.sh

# =============================================================================
# JMeter 性能試験用設定のビルド引数による有効化 / 無効化切り替え
# =============================================================================
ARG ENABLE_PERF_METRICS=false
ARG PERF_METRICS_INTERVAL=10
ENV ENABLE_PERF_METRICS=${ENABLE_PERF_METRICS} \
    PERF_METRICS_INTERVAL=${PERF_METRICS_INTERVAL}

RUN /usr/local/bin/perf-metrics.sh build-setup

# =============================================================================
# configuration の seed 退避  ★ 必ず JBoss EAP 導入の「後ろ」に置くこと
# =============================================================================
ARG STRICT_SEED=0
RUN set -eu; \
    mkdir -p "${JBOSS_HOME}/standalone"; \
    if [ -d "${JBOSS_CONF_DIR}" ] && [ -n "$(ls -A "${JBOSS_CONF_DIR}" 2>/dev/null)" ]; then \
        rm -rf "${JBOSS_CONF_SEED_DIR}"; \
        mkdir -p "${JBOSS_CONF_SEED_DIR}"; \
        cp -a "${JBOSS_CONF_DIR}/." "${JBOSS_CONF_SEED_DIR}/"; \
        rm -rf "${JBOSS_CONF_SEED_DIR}/standalone_xml_history"; \
        chmod -R g+rwX "${JBOSS_CONF_SEED_DIR}"; \
        echo "[base] seeded ${JBOSS_CONF_SEED_DIR}: $(find "${JBOSS_CONF_SEED_DIR}" -type f | wc -l) files"; \
        test -f "${JBOSS_CONF_SEED_DIR}/logging.properties" \
            || { echo "[base] ERROR: seed に logging.properties がありません。これが無いと JBoss は無音で起動失敗します。" >&2; exit 1; }; \
    else \
        mkdir -p "${JBOSS_CONF_SEED_DIR}"; \
        if [ "${STRICT_SEED}" = "1" ]; then \
            echo "[base] ERROR: ${JBOSS_CONF_DIR} が空/未作成です。JBoss EAP の導入 RUN より後ろにこのブロックがあるか確認してください。" >&2; \
            exit 1; \
        fi; \
        echo "[base] WARN: ${JBOSS_CONF_DIR} が空/未作成のため seed をスキップしました (本スケルトンでは正常)。" >&2; \
    fi

# JBoss が起動時に書き込む可変ディレクトリ (ECS ではタスクローカルの書き込み可能ボリュームをマウント)
RUN mkdir -p "${JBOSS_HOME}/standalone/tmp" \
             "${JBOSS_HOME}/standalone/data" \
             "${JBOSS_HOME}/standalone/deployments" \
    && chmod -R g+rwX "${JBOSS_HOME}/standalone/tmp" \
                      "${JBOSS_HOME}/standalone/data" \
                      "${JBOSS_HOME}/standalone/deployments"
