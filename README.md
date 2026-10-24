# JMeter 性能試験用 コンテナ内部メトリクス収集 & モノトーン Excel レポート出力スイート

対象環境:
- **実行基盤**: AWS ECS on Fargate (`readonlyRootFilesystem: true`)
- **ベース OS**: Red Hat Universal Base Image 9.8 (`registry.access.redhat.com/ubi9/ubi:9.8`)
- **JVM**: Red Hat build of OpenJDK 21 (`java-21-openjdk-devel`)
- **AP サーバ**: Red Hat JBoss Enterprise Application Platform (EAP) 8.1 (`standalone` モード)
- **出力先 (EFS)**: `/mnt/logs/<front|back>/logs/<Service_Name>/mid/current`
  - `<front|back>`: `front` (フロントコンテナ) / `back` (バックコンテナ)
  - `<Service_Name>`: `intra-web` / `intra-api` / `inter-api` / `sf-api`

---

## ディレクトリ構成

| ファイルパス | 役割・概要 |
|---|---|
| [`docker/base/perf-metrics.sh`](docker/base/perf-metrics.sh) | **性能試験メトリクス収集 1ファイル集約スクリプト** (`/usr/local/bin/perf-metrics.sh` に配置)。ビルド引数・環境変数 `ENABLE_PERF_METRICS=true` の場合のみ [`docker/base/entrypoint.sh`](docker/base/entrypoint.sh) から読み込まれ、起動時バナー出力・`standalone.xml` 統計有効化・JVMフラグ注入・10秒間隔のバックグラウンド収集デーモンを起動します。 |
| [`docker/base/Dockerfile`](docker/base/Dockerfile) | UBI 9.8 + Red Hat build of OpenJDK 21 + JBoss EAP 8.1 共通ベースイメージ。`ARG ENABLE_PERF_METRICS=false` によりビルド時の有効化/無効化を切り替え可能。 |
| [`docker/base/entrypoint.sh`](docker/base/entrypoint.sh) | `readonlyRootFilesystem: true` + EFS `/mnt/logs` シンボリックリンク (`mid/<LOG_ID>` & `mid/current`) + JBoss ログ書込先固定 (`pin`) + `perf-metrics.sh` 読み込み統合エントリポイント。 |
| [`docker/base/entrypoint.taskid.sh`](docker/base/entrypoint.taskid.sh) | `LOG_ID` に ECS タスク ID を採用する場合のラッパーエントリポイント。 |
| [`docker/front/Dockerfile`](docker/front/Dockerfile) | フロントコンテナ (`Component_name=front`) 用 Dockerfile。`ARG ENABLE_PERF_METRICS=false` 対応。 |
| [`docker/back/Dockerfile`](docker/back/Dockerfile) | バックコンテナ (`Component_name=back`) 用 Dockerfile。`ARG ENABLE_PERF_METRICS=false` 対応。 |
| [`ecs/taskdef.perf-metrics.example.json`](ecs/taskdef.perf-metrics.example.json) | `readonlyRootFilesystem: true` 環境での ECS タスク定義サンプル。 |
| [`Convert-PerfMetricsToExcel.ps1`](Convert-PerfMetricsToExcel.ps1) | **Windows 11 PowerShell モノトーン Excel レポート生成スクリプト**。①〜④の出力ファイルを読み込み、パスから `フロントコンテナ`/`バックコンテナ` および `intra-webサービス`/`intra-apiサービス`/`inter-apiサービス`/`sf-apiサービス` を自動判定してファイル名に含め、美しいモノトーンの `.xlsx` レポートを生成します。 |
| [`JMeter_EAP81_OpenJDK21_Metrics_Complete_Guide.md`](JMeter_EAP81_OpenJDK21_Metrics_Complete_Guide.md) | **完全解説ガイド**（歴史・背景・必要になった経緯・小学生にもわかる例え話・各メトリクスの技術詳細）。 |
| [`tests/test_perf_metrics_e2e.sh`](tests/test_perf_metrics_e2e.sh) | エンドツーエンド自動検証スクリプト。 |

---

## 1. ビルド引数による有効化・無効化の切り替え方法

### (A) 性能試験用イメージのビルド（メトリクス収集：有効）
```bash
# ベースイメージ (性能試験有効)
docker build \
  --build-arg ENABLE_PERF_METRICS=true \
  -t jboss-eap81-base:perf \
  -f docker/base/Dockerfile .

# フロントコンテナ (例: intra-web)
docker build \
  --build-arg BASE_IMAGE=jboss-eap81-base:perf \
  --build-arg ENABLE_PERF_METRICS=true \
  --build-arg Service_Name=intra-web \
  --build-arg Component_name=front \
  -t webapp-front-intra-web:perf \
  -f docker/front/Dockerfile .

# バックコンテナ (例: intra-api)
docker build \
  --build-arg BASE_IMAGE=jboss-eap81-base:perf \
  --build-arg ENABLE_PERF_METRICS=true \
  --build-arg Service_Name=intra-api \
  --build-arg Component_name=back \
  -t webapp-back-intra-api:perf \
  -f docker/back/Dockerfile .
```

### (B) 本番用イメージのビルド（メトリクス収集：無効・デフォルト）
```bash
# --build-arg ENABLE_PERF_METRICS を省略（または false を指定）すると無効になります
docker build -t jboss-eap81-base:prod -f docker/base/Dockerfile .
docker build --build-arg BASE_IMAGE=jboss-eap81-base:prod -t webapp-front:prod -f docker/front/Dockerfile .
```

---

## 2. 出力されるメトリクスファイル一覧 (`/mnt/logs/<front|back>/logs/<Service_Name>/mid/current` 配下)

| 区分 | ファイル名 | 内容 |
|---|---|---|
| **⓪ 起動証跡** | `00_perf_metrics_startup_env.txt` | 性能試験モードの有効化フラグ・コンテナ役割・サービス名・サンプリング間隔・適用済 `JAVA_OPTS` |
| **① JBoss CLI** | `01_jboss_cli_stats.tsv`<br>`01_jboss_cli_raw.log` | DB接続プール (`ActiveCount`, `InUseCount`, `AvailableCount`, `MaxUsedCount`, `WaitCount`, `MaxWaitTime`, `TimedOut`, `TotalBlockingTime`, `PreparedStatementCacheHit/Miss`)、Undertow HTTP リスナー、IO Worker スレッドプール、JTA トランザクション統計 |
| **② ヒープ/GC/JFR** | `02_jvm_heap_gc_stats.tsv`<br>`02_jcmd_jfr_detail.log`<br>`02_flight_recording.jfr` | `jstat` (`-gc`, `-gccause`, `-class`, `-compiler`)、`jcmd` (`GC.heap_info`, `VM.native_memory summary`, `Compiler.codecache`, `JFR.check`/`JFR.dump`)、OpenJDK 21 `JFR` 連続フライトレコーディング & `jfr summary` |
| **③ top/ps/OS** | `03_process_thread_stats.tsv`<br>`03_top_ps_detail.log` | `top -H -b -n 1` / `ps -L` によるスレッド状態内訳 (`R`/`D`/`S`/`Z`)、高負荷スレッド Top1/Top2 の TID・スレッド名・CPU%・カーネル待機関数 (`wchan`)、FD 枯渇率、ページフォルト、非自発的コンテキストスイッチ、TCP ソケット状態 (`ESTABLISHED`/`CLOSE_WAIT`/`TIME_WAIT`/`SYN_RECV`/`ListenDrops`) |
| **④ ActiveProcessorCount** | `04_active_processor_diag.tsv`<br>`04_active_processor_report.txt` | `-XX:ActiveProcessorCount` 要否判断用テレメトリ（ホスト物理コア数、ECS タスク/コンテナ CPU 単位、同居コンテナ数、cgroup v2/v1 実効 vCPU、JVM 認識コア数、自動生成スレッド数、CFS スロットリング率 `nr_throttled`/`nr_periods`、推奨設定値と自動要否判定） |

---

## 3. Windows 11 PowerShell によるモノトーン Excel レポート生成

EFS から取得したメトリクスフォルダを指定して [`Convert-PerfMetricsToExcel.ps1`](Convert-PerfMetricsToExcel.ps1) を実行すると、パスに含まれる `front`/`back` と `intra-web`/`intra-api`/`inter-api`/`sf-api` を自動抽出し、モノトーンの美しい Excel (`.xlsx`) レポートを生成します。

```powershell
# 単一フォルダの変換（例: /mnt/logs/front/logs/intra-web/mid/current）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Convert-PerfMetricsToExcel.ps1 `
  -InputPath "C:\logs\mnt\logs\front\logs\intra-web\mid\current" `
  -OutputDirectory "C:\PerfReports"
```

出力される Excel ファイル名の例:
- `JMeter性能試験メトリクスレポート_フロントコンテナ_intra-webサービス_20261024_223539.xlsx`
- `JMeter性能試験メトリクスレポート_バックコンテナ_intra-apiサービス_20261024_223542.xlsx`
- `JMeter性能試験メトリクスレポート_フロントコンテナ_inter-apiサービス_20261024_223545.xlsx`
- `JMeter性能試験メトリクスレポート_バックコンテナ_sf-apiサービス_20261024_223548.xlsx`
