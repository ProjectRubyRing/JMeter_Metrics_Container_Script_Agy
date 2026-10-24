# syntax=docker/dockerfile:1
# =============================================================================
# フロントコンテナ (webapp9mf02) 用 Dockerfile
#
# 作成するシンボリックリンク:
#   /webapp/webapp9mf02/logs      -> /mnt/logs/<Component_name>/logs/<Service_Name>
#   /webapp/webapp9mf02/pdf       -> /mnt/data/pdf          ※ intra-web のみ
#   /opt/jboss-eap/standalone/log -> /mnt/logs/<Component_name>/logs/<Service_Name>/mid/current
#
# ビルド例:
#   # JMeter 性能試験用ビルド (ENABLE_PERF_METRICS=true)
#   docker build -t intra-web-front:perf \
#     --build-arg BASE_IMAGE=myapp-base:perf \
#     --build-arg Service_Name=intra-web \
#     --build-arg Component_name=front \
#     --build-arg ENABLE_PERF_METRICS=true \
#     docker/front
#
#   # 本番用ビルド (ENABLE_PERF_METRICS=false = 既定)
#   docker build -t intra-web-front:latest \
#     --build-arg BASE_IMAGE=myapp-base:latest \
#     --build-arg Service_Name=intra-web \
#     --build-arg Component_name=front \
#     docker/front
# =============================================================================
ARG BASE_IMAGE=myapp-base:latest
FROM ${BASE_IMAGE}

ARG Service_Name=intra-web
ARG Component_name=front
ARG ENABLE_PERF_METRICS=false
ARG PERF_METRICS_INTERVAL=10

RUN test -n "${Service_Name}"   || { echo "ERROR: --build-arg Service_Name が未指定です"   >&2; exit 1; } \
    && test -n "${Component_name}" || { echo "ERROR: --build-arg Component_name が未指定です" >&2; exit 1; }

ENV Service_Name=${Service_Name} \
    Component_name=${Component_name} \
    COMPONENT_ROLE=front \
    APP_HOME=/webapp/webapp9mf02 \
    EFS_LOG_DIR=/mnt/logs/${Component_name}/logs/${Service_Name} \
    ENABLE_PERF_METRICS=${ENABLE_PERF_METRICS} \
    PERF_METRICS_INTERVAL=${PERF_METRICS_INTERVAL}

USER root

# --- アプリケーション本体の配置 ----------------------------------------------
# COPY --chown=jboss:jboss webapp9mf02/ /webapp/webapp9mf02/
RUN mkdir -p /webapp/webapp9mf02 /opt/jboss-eap/standalone

# --- 1. アプリログ: /webapp/webapp9mf02/logs -> EFS --------------------------
RUN rm -rf /webapp/webapp9mf02/logs \
    && ln -s "/mnt/logs/${Component_name}/logs/${Service_Name}" /webapp/webapp9mf02/logs

# --- 2. 帳票 pdf: intra-web のフロントコンテナのみ ---------------------------
RUN if [ "${Service_Name}" = "intra-web" ] || [ "${Service_Name}" = "intraweb" ]; then \
        rm -rf /webapp/webapp9mf02/pdf; \
        ln -s /mnt/data/pdf /webapp/webapp9mf02/pdf; \
        echo "pdf symlink created for ${Service_Name}"; \
    else \
        echo "pdf symlink skipped for ${Service_Name}"; \
    fi

# --- 3. ミドルウェア(JBoss EAP)ログ ------------------------------------------
RUN rm -rf /opt/jboss-eap/standalone/log \
    && ln -s "/mnt/logs/${Component_name}/logs/${Service_Name}/mid/current" /opt/jboss-eap/standalone/log

# 性能試験設定のビルド時検証・マーカー更新
RUN /usr/local/bin/perf-metrics.sh build-setup \
    && ls -l /webapp/webapp9mf02/ /opt/jboss-eap/standalone/ | grep -E ' logs| log| pdf' || true

# USER jboss

ENTRYPOINT ["/usr/local/bin/efs-entrypoint.sh"]
CMD ["eap"]
