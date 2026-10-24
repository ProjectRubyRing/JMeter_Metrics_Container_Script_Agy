# syntax=docker/dockerfile:1
# =============================================================================
# バックコンテナ (webapp9mb02) 用 Dockerfile
#
# 作成するシンボリックリンク:
#   /webapp/webapp9mb02/logs      -> /mnt/logs/<Component_name>/logs/<Service_Name>
#   /opt/jboss-eap/standalone/log -> /mnt/logs/<Component_name>/logs/<Service_Name>/mid/current
#
# ビルド例:
#   # JMeter 性能試験用ビルド (ENABLE_PERF_METRICS=true)
#   docker build -t intra-web-back:perf \
#     --build-arg BASE_IMAGE=myapp-base:perf \
#     --build-arg Service_Name=intra-web \
#     --build-arg Component_name=back \
#     --build-arg ENABLE_PERF_METRICS=true \
#     docker/back
#
#   # 本番用ビルド (ENABLE_PERF_METRICS=false = 既定)
#   docker build -t intra-web-back:latest \
#     --build-arg BASE_IMAGE=myapp-base:latest \
#     --build-arg Service_Name=intra-web \
#     --build-arg Component_name=back \
#     docker/back
# =============================================================================
ARG BASE_IMAGE=myapp-base:latest
FROM ${BASE_IMAGE}

ARG Service_Name=intra-web
ARG Component_name=back
ARG ENABLE_PERF_METRICS=false
ARG PERF_METRICS_INTERVAL=10

RUN test -n "${Service_Name}"   || { echo "ERROR: --build-arg Service_Name が未指定です"   >&2; exit 1; } \
    && test -n "${Component_name}" || { echo "ERROR: --build-arg Component_name が未指定です" >&2; exit 1; }

ENV Service_Name=${Service_Name} \
    Component_name=${Component_name} \
    COMPONENT_ROLE=back \
    APP_HOME=/webapp/webapp9mb02 \
    EFS_LOG_DIR=/mnt/logs/${Component_name}/logs/${Service_Name} \
    ENABLE_PERF_METRICS=${ENABLE_PERF_METRICS} \
    PERF_METRICS_INTERVAL=${PERF_METRICS_INTERVAL}

USER root

# --- アプリケーション本体の配置 ----------------------------------------------
# COPY --chown=jboss:jboss webapp9mb02/ /webapp/webapp9mb02/
RUN mkdir -p /webapp/webapp9mb02 /opt/jboss-eap/standalone

# --- 1. アプリログ: /webapp/webapp9mb02/logs -> EFS --------------------------
RUN rm -rf /webapp/webapp9mb02/logs \
    && ln -s "/mnt/logs/${Component_name}/logs/${Service_Name}" /webapp/webapp9mb02/logs

# --- 2. ミドルウェア(JBoss EAP)ログ ------------------------------------------
RUN rm -rf /opt/jboss-eap/standalone/log \
    && ln -s "/mnt/logs/${Component_name}/logs/${Service_Name}/mid/current" /opt/jboss-eap/standalone/log

# 性能試験設定のビルド時検証・マーカー更新
RUN /usr/local/bin/perf-metrics.sh build-setup \
    && ls -l /webapp/webapp9mb02/ /opt/jboss-eap/standalone/ | grep -E ' logs| log' || true

# USER jboss

ENTRYPOINT ["/usr/local/bin/efs-entrypoint.sh"]
CMD ["eap"]
