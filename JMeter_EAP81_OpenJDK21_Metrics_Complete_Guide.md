# JMeter 性能試験における AWS ECS Fargate (UBI 9.8 + OpenJDK 21 + JBoss EAP 8.1) 内部メトリクス取得・要否診断・モノトーン Excel レポート出力 完全ガイド

---

## 目次

1. [全体像と小学生にもわかる「たとえ話」](#1-全体像と小学生にもわかるたとえ話)
2. [登場の歴史・背景・なぜ今この仕組みが必要になったのか？](#2-登場の歴史背景なぜ今この仕組みが必要になったのか)
3. [なぜ「CloudWatch Container Insights 拡張」だけではダメなのか？（取得対象と除外対象の境界線）](#3-なぜcloudwatch-container-insights-拡張だけではダメなのか取得対象と除外対象の境界線)
4. [最大の難所：`readonlyRootFilesystem: true` と EFS `mid/current` シンボリックリンク問題の完全攻略](#4-最大の難所readonlyrootfilesystem-true-と-efs-midcurrent-シンボリックリンク問題の完全攻略)
5. [① `jboss-cli.sh` を使った DB 接続プール統計情報・必須ランタイム統計の取得](#5-1-jboss-clish-を使った-db-接続プール統計情報必須ランタイム統計の取得)
6. [② `jstat` / `jcmd` / `JFR` (Java Flight Recorder) を使ったヒープ・GC・ネイティブメモリ情報の取得](#6-2-jstat--jcmd--jfr-java-flight-recorder-を使ったヒープgcネイティブメモリ情報の取得)
7. [③ `top` / `ps` / `/proc` を使ったプロセス・スレッド状況・OS カーネル深層情報の取得](#7-3-top--ps--proc-を使ったプロセススレッド状況os-カーネル深層情報の取得)
8. [④ `-XX:ActiveProcessorCount` の設定要否を判断するために必要な情報の取得と自動判定ロジック](#8-4--xxactiveprocessorcount-の設定要否を判断するために必要な情報の取得と自動判定ロジック)
9. [⑤ コンテナビルド引数 (`ENABLE_PERF_METRICS`) による有効/無効切替と 1 ファイル集約アーキテクチャ](#9-5-コンテナビルド引数-enable_perf_metrics-による有効無効切替と-1-ファイル集約アーキテクチャ)
10. [⑥ Windows 11 PowerShell スクリプトによるモノトーン Excel レポート自動生成](#10-6-windows-11-powershell-スクリプトによるモノトーン-excel-レポート自動生成)

---

## 1. 全体像と小学生にもわかる「たとえ話」

### 給食センター（コンテナ）と1,000人の注文（JMeter）でたとえてみよう！

私たちが作っている Web システム（ECS Fargate コンテナの中の JBoss EAP 8.1 と OpenJDK 21）を、**「超巨大なレストランのキッチン（給食センター）」** だと想像してください。

- **JMeter（ジェイメーター）** ＝ **「おなかを空かせた 1,000 人のお客さん役ロボット」**
  - 本番オープンの前に、「1,000 人がいっぺんにハンバーグを注文しても、キッチンがパンクしないかな？」とテストするロボットです。
- **AWS CloudWatch Container Insights 拡張（コンテナ・インサイト）** ＝ **「レストランの建物の外にある電気メーターと水道メーター」**
  - 建物の外から見て、「今、キッチン全体で電気（CPU）を 70% 使っているな」「水（メモリ）を 60% 使っているな」ということは分かります。
  - **でも、建物の外からは「キッチンの中で何が起きているか」までは絶対に分かりません！**
- **今回実装した `perf-metrics.sh`（①〜④の計測スクリプト）** ＝ **「キッチンの中に設置した 4 台の超精密カメラ」**
  1. **カメラ①（`jboss-cli`：DB接続プール）** ＝ **「冷蔵庫（データベース）から食材を取り出すための『専用カート（DB接続）』が全部出払って、料理人が順番待ちで行列を作っていないか？」** を10秒ごとに記録するカメラ。
  2. **カメラ②（`jstat`/`jcmd`/`JFR`：ヒープとGC）** ＝ **「まな板（Eden領域）や作業台（Old領域）が生ゴミ（使い終わったデータ）でいっぱいになり、全員の手を止める『キッチン全体の大掃除（Full GC）』が起きていないか？」** を10秒ごとに記録するカメラ（さらに航空機のブラックボックス『JFR』で一部始終を録画！）。
  3. **カメラ③（`top`/`ps`/`/proc`：プロセスとスレッド）** ＝ **「料理人一人ひとり（スレッド）のうち、誰がサボっていて、誰が鍋の前で固まって動けなくなっているか（スレッド状態・待機場所 wchan）？」** を10秒ごとに記録するカメラ。
  4. **カメラ④（`-XX:ActiveProcessorCount` 要否判断）** ＝ **「キッチンの広さは 2 人分（2 vCPU）しかないのに、料理長（JVM）が『ここは 8 人入れる広いキッチンだ！』と勘違いして料理人を 30 人も詰め込み、お互いにぶつかって警備員（Linux CFS スケジューラ）に『ストップ！（CFS スロットリング）』と笛を吹かれていないか？」** を診断するカメラ。
- **`readonlyRootFilesystem: true`（読み取り専用ルートファイルシステム）** ＝ **「落書き禁止の魔法のガラス張りキッチン」**
  - 泥棒（ウイルスやハッカー）が入ってきても勝手に道具を書き換えられないよう、キッチンの壁や床には一切メモが書けません。唯一、外につながる **「共有連絡ノート置き場（EFS：`/mnt/logs/front/logs/intra-web/mid/current`）」** と **「一時メモ帳（`/tmp`）」** にだけ記録を書けます。
- **PowerShell スクリプト（`Convert-PerfMetricsToExcel.ps1`）** ＝ **「4 台のカメラの記録を、白黒（モノトーン）の美しい新聞（Excel レポート）に自動でまとめる編集長」**
  - どのキッチン（`フロントコンテナ` / `バックコンテナ`）の、どのお店（`intra-webサービス` / `intra-apiサービス` / `inter-apiサービス` / `sf-apiサービス`）の記録かをパスの名前から自動で見分けて、ファイル名に入れて Excel を作ります。

---

## 2. 登場の歴史・背景・なぜ今この仕組みが必要になったのか？

### 2.1 物理サーバ時代からコンテナ・サーバーレス時代への進化

| 世代 | 実行環境 | 監視・性能試験のやり方 | 起きた問題（なぜ今回の仕組みが必要になったか） |
|---|---|---|---|
| **第1世代 (2000年代)** | 物理サーバ / オンプレミス VM | サーバに SSH ログインして `top` や `jstat` を手打ちし、ローカルディスク `/var/log` に保存 | サーバ台数が増えると手作業が不可能になり、環境ごとの差異が大きかった |
| **第2世代 (2010年代前半)** | Docker コンテナ初期 + OpenJDK 8 初期 | コンテナ内で Java を動かす | **「コンテナ罠（Container Blindness）」の発生**：初期の Java (JDK 8u131 未満) はコンテナの制限（cgroup）を知らず、ホスト物理マシン（例：64コア・256GB）を見てスレッドやヒープを爆増させ、OOM Killer や CPU スロットリングで即死した |
| **第3世代 (2018〜2022年)** | AWS ECS Fargate + OpenJDK 8u191〜17 + cgroup v1 | `-XX:+UseContainerSupport` 登場。しかし Kubernetes / ECS の `cpu.shares` の扱いで **JDK-8281181** 問題が発生 | コンテナに `cpu: 768` 等を指定すると、JVM が `cpu.shares` を見て **「1コアしか使えない！」と誤認** し、CPU が余っているのに GC スレッドを 1 本に絞ってしまう逆方向の性能劣化が多発した |
| **第4世代 (現在：2024〜2026年)** | **Red Hat UBI 9.8 + Red Hat build of OpenJDK 21 + JBoss EAP 8.1 on ECS Fargate (`readonlyRootFilesystem: true`)** | **cgroup v2 完全対応 + Jakarta EE 10 (EAP 8.1) + OpenJDK 21 (JFR標準搭載・JDK-8281181修正済) + ゼロトラスト (`readonlyRootFilesystem: true`)** | セキュリティ強化でルートFSへの書き込みが全面禁止され、従来の `jcmd`/`jboss-cli`/`JFR` がデフォルトでは権限エラー (`EROFS`) で動かなくなった。さらに Fargate マルチコンテナ同居時の CPU 競合と EFS シンボリックリンク (`mid/current`) 競合を同時に解決する必要が生じた |

### 2.2 各コンポーネントの最新仕様と歴史的背景

1. **Red Hat Universal Base Image (UBI) 9.8 (RHEL 9.8 ベース)**
   - Linux カーネルおよびユーザーランドが **cgroup v2 (Unified Hierarchy)** を標準採用。
   - 最小構成イメージでは `ps` や `top` を含む `procps-ng` や、OpenJDK の診断ツール群 (`jstat`, `jcmd`, `jfr`) を含む `-devel` パッケージを明示的に導入する必要があります。
2. **Red Hat build of OpenJDK 21 (LTS)**
   - **JFR (Java Flight Recorder) の完全オープンソース化**: かつて Oracle JDK の有償商用機能（Commercial Feature）だった JFR は、JEP 328 (JDK 11+) を経て OpenJDK に完全統合され、Red Hat build of OpenJDK 21 では **追加ライセンス費用ゼロ・オーバーヘッド 1% 未満** で本番・性能試験ともに標準利用可能です。さらに CLI ツール `jfr` コマンドにより、コンテナ内で `.jfr` バイナリの統計サマリ (`jfr summary`) をテキスト抽出できます。
   - **JDK-8281181 の修正**: OpenJDK 21 では `cpu.shares` (cgroup v1) / `cpu.weight` (cgroup v2) をハードリミットと誤認するバグが解消され、原則としてハードリミット (`cpu.max` / `cfs_quota_us`) に基づいてプロセッサ数を算出します。
3. **JBoss EAP 8.1 (WildFly / Jakarta EE 10 世代)**
   - JBoss EAP 7 系 (Java EE 8) から Jakarta EE 10 (`jakarta.*` 名前空間) へ刷新され、OpenJDK 17 / 21 が必須となりました。
   - 性能面での重要な仕様として、オーバーヘッド削減のため **初期状態ではデータソース・Undertow・トランザクションの統計収集フラグ (`statistics-enabled`) がすべて `false`** になっています。これを `true` にしない限り、`jboss-cli.sh` を叩いてもすべてのカウンタが `0` または `undefined` になります。

---

## 3. なぜ「CloudWatch Container Insights 拡張」だけではダメなのか？（取得対象と除外対象の境界線）

AWS CloudWatch Container Insights **拡張 (Enhanced Observability for ECS)** は、タスクレベル・コンテナレベルの以下のメトリクスを自動収集します。
**したがって、本実装ではこれら Container Insights 拡張で確認できる項目は重複取得せず除外しています。**

| 区分 | CloudWatch Container Insights 拡張で **見えるもの（今回除外）** | CloudWatch Container Insights 拡張では **絶対に見えないもの（今回 ①②③④ で取得）** |
|---|---|---|
| **DB / AP サーバ内部 (①)** | なし（コンテナ外からはブラックボックス） | ・**DB接続プール** の使用中数 (`InUseCount`)、空き数 (`AvailableCount`)、**枯渇待ちスレッド数 (`WaitCount`)**、最大待ち時間 (`MaxWaitTime`)、タイムアウト数 (`TimedOut`)<br>・PreparedStatement キャッシュヒット率<br>・Undertow HTTP リクエスト処理時間 / IO Worker スレッドプールビジー数・キュー滞留数 / JTA 実行中・ロールバックトランザクション数 |
| **JVM メモリ・GC (②)** | コンテナ全体のメモリ使用量 (`MemoryUtilized` / `MemoryReserved` = OS から見た RSS) | ・**JVM ヒープ世代別内訳**（Eden / Survivor S0・S1 / Old 領域のどこが詰まっているか）<br>・**Metaspace / Compressed Class Space / JIT CodeCache / Native Memory (NMT)** の内訳<br>・**Young GC / Full GC の発生回数・Stop-The-World 停止時間 (`YGCT`, `FGCT`)・GC 発生原因 (`LGCC`)**<br>・**JFR** によるオブジェクト割り当て・ロック競合・ホットメソッドの記録 |
| **プロセス・スレッド (③)** | コンテナ全体の CPU 使用率 (`CpuUtilized`)、ネットワーク送受信バイト数、ストレージ読み書きバイト数 | ・**100本以上ある Java スレッドのうち「どのスレッド（Undertow / GC / JIT）」が CPU を食いつぶしているか (`top -H`, `ps -L`)**<br>・スレッドがカーネル内のどの関数 (`wchan`: `futex` ロック待ち、`ep_poll` 通信待ち、ディスク `D` 状態) で止まっているか<br>・ファイルディスクリプタ (FD) 枯渇率、ページフォルト、**CPU 強制剥奪回数 (`nonvoluntary_ctxt_switches`)**、TCP `CLOSE_WAIT` / `TIME_WAIT` / `ListenDrops` |
| **CPU 認識・スロットリング診断 (④)** | コンテナの平均 CPU 使用率（1分粒度など） | ・**100ms 単位の Linux CFS スロットリング発生回数 (`nr_throttled` / `nr_periods`) と停止ミリ秒 (`throttled_usec`)**<br>・JVM が何コアと認識し (`JVM_Recognized_Processors`)、GC/JIT/Worker スレッドを何本生成したか<br>・**`-XX:ActiveProcessorCount` を設定すべきか否かの確定診断** |

---

## 4. 最大の難所：`readonlyRootFilesystem: true` と EFS `mid/current` シンボリックリンク問題の完全攻略

ECS タスク定義でセキュリティ要件により `readonlyRootFilesystem: true` が有効になっている場合、コンテナ内の `/`（ルートファイルシステム）への書き込みは Linux カーネルによって拒否（`EROFS: Read-only file system`）されます。

そのままでは、`jboss-cli.sh`、`jstat`、`jcmd`、`JFR` はすべて以下の理由で失敗します。本実装（[`docker/base/perf-metrics.sh`](docker/base/perf-metrics.sh) および [`docker/base/entrypoint.sh`](docker/base/entrypoint.sh)）では、これら **5 つの罠** をすべて解決しています。

| # | `readonlyRootFilesystem: true` で起きる罠 | なぜ起きるのか（原因） | 本実装での解決策 |
|---|---|---|---|
| **罠1** | **`jcmd` がターゲット JVM にアタッチできず失敗する** | `jcmd <pid>` は実行時、ターゲット JVM のカレントディレクトリ (`WORKDIR` = `/opt/jboss-eap` 等の Read-Only 領域) に `.attach_pid<pid>` というファイルを作ろうとして `EROFS` で失敗するため。 | JBoss 起動時の `JAVA_OPTS` に **`-XX:+StartAttachListener`** を自動注入し、JVM 起動時から `/tmp/.java_pid<pid>` ソケットを待ち受けさせることでファイル作成なしで即座にアタッチ可能にした。 |
| **罠2** | **`jstat` がプロセスを見つけられない / 共有メモリを作れない** | JVM が `/tmp/hsperfdata_<user>/<pid>` にパフォーマンスカウンタを作れない、または `jstat` 側が別の `tmpdir` を見に行くと失敗するため。 | JBoss 本体に **`-XX:-PerfDisableSharedMem -Djava.io.tmpdir=/tmp`** を付与し、`jstat` / `jcmd` 呼び出し側にも `-J-Djava.io.tmpdir=/tmp` を明示指定して完全一致させた。 |
| **罠3** | **`jboss-cli.sh` が履歴ファイル書き込みエラーや OTel Agent 二重起動で失敗する** | `jboss-cli.sh` は `$HOME/.jboss-cli-history` に履歴を書こうとし、さらに環境変数 `JAVA_TOOL_OPTIONS` が設定されていると CLI 用の短命 JVM にまで OpenTelemetry エージェントや JFR が読み込まれてポート競合・メモリ圧迫を起こすため。 | `jboss-cli.sh` 実行時に **`HOME=/tmp` `-Duser.home=/tmp` `-Djava.io.tmpdir=/tmp`** を渡し、かつ **`JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS=""`** でエージェント継承を遮断、さらに `-Xms32m -Xmx64m -XX:+UseSerialGC -XX:ActiveProcessorCount=1` で軽量実行させた。 |
| **罠4** | **JFR (Java Flight Recorder) がチャンクデータを書き込めずクラッシュする** | JFR は記録中のチャンク（一時データ）をローカルリポジトリに書き溜めてから最終 `.jfr` ファイルにダンプするため。 | **`-XX:FlightRecorderOptions=repository=/tmp/jfr-repo`** で一時チャンク置き場を書き込み可能な `/tmp` に向け、最終ダンプ先 (`filename=`) を EFS 上の `/mnt/logs/<front|back>/logs/<Service_Name>/mid/current/02_flight_recording.jfr` に指定した。 |
| **罠5** | **`standalone.xml` の `statistics-enabled="true"` 書き換えが Read-Only で失敗する** | イメージ内の `/opt/jboss-eap/standalone/configuration` が Read-Only のままだと起動時に設定変更や履歴書き込みができないため。 | [`docker/base/Dockerfile`](docker/base/Dockerfile) で `configuration-seed` に原本を退避し、[`docker/base/entrypoint.sh`](docker/base/entrypoint.sh) が起動時に書き込み可能な `configuration` へ復元した直後に、`perf-metrics.sh` が `standalone.xml` の `statistics-enabled="true"` を有効化する。 |

### EFS の `/mnt/logs/<front|back>/logs/<Service_Name>/mid/current` と `pin` の整合性

他プロジェクトフォルダ（`ECS_EFS_Dockerfile_Symboliclink_lite` 等）の設計と完全整合するよう、以下の仕組みを採用しています。

```
/mnt/logs/front/logs/intra-web/mid/
  ├── 20261024223849-a1b2c3d4/        <-- 自タスク専用の書き込み実体ディレクトリ (LOG_OWN)
  │     ├── server.log
  │     ├── 00_perf_metrics_startup_env.txt
  │     ├── 01_jboss_cli_stats.tsv
  │     ├── 01_jboss_cli_raw.log
  │     ├── 02_jvm_heap_gc_stats.tsv
  │     ├── 02_jcmd_jfr_detail.log
  │     ├── 02_flight_recording.jfr
  │     ├── 03_process_thread_stats.tsv
  │     ├── 03_top_ps_detail.log
  │     ├── 04_active_processor_diag.tsv
  │     └── 04_active_processor_report.txt
  └── current -> 20261024223849-a1b2c3d4  <-- 最新タスクを指すシンボリックリンク
```

- 外部の運用者やスクリプトからは、常に **`/mnt/logs/front/logs/intra-web/mid/current` 配下** として全メトリクスファイルを参照できます。
- 同時に、書き込み自体は実体パス (`LOG_OWN`) に対して行われるため、複数タスク起動時にもファイルが混ざりません。また各ファイルのヘッダには論理パス (`METRICS_LOG_PATH: /mnt/logs/front/logs/intra-web/mid/current/...`) が明記されるため、どのパスからコピーしても PowerShell スクリプトが確実に `front`/`back` とサービス名を識別できます。

---

## 5. ① `jboss-cli.sh` を使った DB 接続プール統計情報・必須ランタイム統計の取得

### 5.1 実行コマンドの仕組み

10 秒ごとに `jboss-cli.sh` を複数回起動すると JVM の起動コストがかかるため、**1 回の `jboss-cli.sh --connect` 呼び出しにカンマ区切りで 5 つの DMR コマンドを束ねて一括取得** しています。

```bash
HOME=/tmp JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" \
JAVA_OPTS="-Xms32m -Xmx64m -XX:+UseSerialGC -XX:ActiveProcessorCount=1 -Djava.io.tmpdir=/tmp -Duser.home=/tmp" \
/opt/jboss-eap/bin/jboss-cli.sh --connect --controller=remote+http://127.0.0.1:${MGMT_PORT} --commands="\
/subsystem=datasources:read-children-resources(child-type=data-source,include-runtime=true,recursive=true),\
/subsystem=datasources:read-children-resources(child-type=xa-data-source,include-runtime=true,recursive=true),\
/subsystem=undertow/server=default-server/http-listener=default:read-resource(include-runtime=true),\
/subsystem=io/worker=default:read-resource(include-runtime=true),\
/subsystem=transactions:read-resource(include-runtime=true)"
```

> **バックコンテナ (`back`) のポートオフセット自動追従**:
> 同一 ECS タスク内で `front` と `back` が同居する場合、`back` コンテナは `-Djboss.socket.binding.port-offset=100` 等で管理ポートが `9990` → `10090` にシフトします。`perf-metrics.sh` は環境変数 `PORT_OFFSET` または `/proc/<pid>/cmdline` からポートオフセットを自動検出し、正しい管理ポートへ接続します。

### 5.2 取得項目と性能試験での見方 (`01_jboss_cli_stats.tsv`)

| カラム名 | 取得元サブシステム | 意味（小学生向けのたとえ） | 性能試験での異常判定基準 |
|---|---|---|---|
| `MaxPoolSize` | `datasources` | 冷蔵庫から食材を運ぶ「専用カート」の最大台数 | 設定値と一致しているか確認 |
| `ActiveCount` | `datasources/pool` | 今すぐ使える状態で用意されているカートの台数 | `MaxPoolSize` まで伸びるか |
| `InUseCount` | `datasources/pool` | **今まさに料理人が使っているカートの台数** | `MaxPoolSize` に張り付いていたらプール上限到達 |
| `AvailableCount` | `datasources/pool` | **あと何台カートが空いているか** | **`0` になると次のリクエストは待たされる！** |
| `WaitCount` | `datasources/pool` | **カートが空くのを待って並んでいる料理人の人数** | **`1` 以上が継続したら DB 接続プール枯渇（WARN）** |
| `MaxWaitTime_ms` | `datasources/pool` | カートを借りるまでに待たされた最長時間 (ミリ秒) | 数百 ms〜数秒に跳ね上がるとレスポンス悪化の主因 |
| `TimedOut` | `datasources/pool` | **待ちきれずに諦めてエラーになった回数** | **`1` でも発生したら即 CRITICAL（接続プール不足またはスロークエリ）** |
| `PrepStmtCache_HitCnt` / `MissCnt` | `datasources/jdbc` | SQL の「レシピカード（PreparedStatement）」を使い回せた回数と作り直した回数 | Miss ばかり増える場合はキャッシュサイズ (`prepared-statements-cache-size`) 不足 |
| `Undertow_ReqCount` / `ErrCount` / `MaxProcTime_ms` | `undertow/http-listener` | Web 窓口が受け付けた注文数、エラー数 (HTTP 5xx)、最長処理時間 | JMeter 側のエラー数とサーバー内部のエラー数が一致するか照合 |
| `Worker_BusyThreads` / `Worker_MaxThreads` / `Worker_QueueSize` / `Worker_Rejected` | `io/worker=default` | 接客担当スタッフ（Undertow Worker スレッド）の稼働中人数、上限人数、待合室（キュー）の人数、お断り数 | `BusyThreads == MaxThreads` で頭打ちになると、DB に余裕があっても Web 層で詰まる |
| `JTA_InFlightTx` / `JTA_AbortedTx` / `JTA_TimedOutTx` / `JTA_Heuristics` | `transactions` | 今実行中のトランザクション数、ロールバック数、タイムアウト数、XA 分散トランザクション不整合 (`Heuristics`) | `TimedOutTx > 0` はロック競合や長大 SQL の証拠 |

---

## 6. ② `jstat` / `jcmd` / `JFR` (Java Flight Recorder) を使ったヒープ・GC・ネイティブメモリ情報の取得

### 6.1 なぜ 3 つのツール（`jstat` / `jcmd` / `JFR`）を組み合わせるのか？

1. **`jstat` (`-gc`, `-gccause`, `-class`, `-compiler`)**
   - JVM 共有メモリ (`hsperfdata`) を読み取るため **オーバーヘッドがほぼゼロ** で、10 秒間隔の時系列数値（Eden/Survivor/Old/Metaspace 使用率、Young GC / Full GC 回数と停止時間、直前の GC 原因）を TSV 化するのに最適です。
2. **`jcmd` (`GC.heap_info`, `VM.native_memory summary`, `Compiler.codecache`, `JFR.check`, `JFR.dump`)**
   - `jstat` では見えない **G1GC のリージョン内訳**、**JIT コンパイラの CodeCache 枯渇状況**、そして **ヒープ外メモリ（Direct Buffer、スレッドスタック、GC 管理領域、クラスメタデータ）を追跡する NMT (Native Memory Tracking)** を取得します。ECS Fargate で「ヒープ（`-Xmx`）は余裕があるのにコンテナが OOM Killer (`Exit Code 137`) で死ぬ」原因の 9 割はこのヒープ外メモリにあり、NMT でしか見抜けません。
3. **`JFR` (Java Flight Recorder) + `jfr summary`**
   - UBI 9.8 + Red Hat build of OpenJDK 21 で標準利用できる JVM 内蔵の超低負荷プロファイラです。
   - 起動時に `-XX:StartFlightRecording=name=perf-continuous,settings=profile,disk=true,maxage=1h,maxsize=250M,dumponexit=true,filename=.../02_flight_recording.jfr` を設定し、さらに定期収集ループ内で `jcmd <pid> JFR.dump` と `jfr summary` を実行します。
   - これにより、試験中に万が一コンテナが急死しても EFS 上の `02_flight_recording.jfr` に直前までの全イベント（どのメソッドが CPU を使ったか、どのクラスがメモリを大量消費したか、どのロックで何ミリ秒止まったか）が残り、JDK Mission Control (JMC) で後からミリ秒単位の解剖が可能です。

---

## 7. ③ `top` / `ps` / `/proc` を使ったプロセス・スレッド状況・OS カーネル深層情報の取得

### 7.1 Container Insights では見えない「スレッド単位の犯人捜し」

CloudWatch Container Insights で「CPU 使用率 95%」と分かったとき、インフラ担当者とアプリ担当者の間で必ず起きる議論が **「アプリ（Java の業務ロジック）が重いのか？ GC が暴走しているのか？ それとも OS / I/O 待ちなのか？」** です。

これを一発で解決するのが `top -H -b -n 1 -p <pid>` と `ps -L -p <pid> -o pid,lwp,psr,pcpu,pmem,stat,wchan:24,time,comm --sort=-pcpu` です。

### 7.2 取得項目と性能試験での見方 (`03_process_thread_stats.tsv` & `03_top_ps_detail.log`)

| カラム名 | 意味（小学生向けのたとえ） | 診断のポイント |
|---|---|---|
| `Threads_Running_R` | 今まさに CPU を使って走り回っている料理人の数 (`R`) | 実効 vCPU 数を大きく超えて常時張り付いている場合は CPU ボトルネック |
| `Threads_DiskSleep_D` | **冷蔵庫や倉庫（ディスク/EFS ネームスペース）の応答が返ってこなくて、呼びかけにも反応できず固まっている料理人の数 (`D`: Uninterruptible Sleep)** | **`1` 以上が継続したら EFS やストレージ I/O の詰まりが犯人！** |
| `Top1_Thread_Name` / `Top1_Thread_CPU_Pct` / `Top1_Thread_WCHAN` | **今一番 CPU を使っているスレッドの名前・CPU%・カーネル待機関数 (`wchan`)** | ・`default task-XX` なら **業務アプリ処理 (Undertow Worker)**<br>・`G1 Conc#0` / `GC Thread` なら **GC 負荷**<br>・`C2 CompilerThre` なら **JIT コンパイル負荷**<br>・`wchan` が `futex_wait_queue_me` なら **Java ロック (`synchronized`/`ReentrantLock`) 待ち**、`ep_poll` なら **ネットワーク/DB 応答待ち** |
| `Open_FDs` / `Max_FDs_Limit` / `FD_Usage_Pct` | 開いているファイルや通信ソケットの数（上限に対する割合） | 80% を超えると `Too many open files` で通信不能になる危険サイン |
| `Min_PageFaults` / `Maj_PageFaults` | メモリページフォルト回数（特に `Maj_PageFaults` はディスクからの読み込みを伴う重いフォルト） | `Maj_PageFaults` が急増している場合はメモリ不足またはバイナリ読み込み遅延 |
| `Voluntary_CtxtSw` / `NonVoluntary_CtxtSw` / `Delta_NonVol_CtxtSw` | 自発的コンテキストスイッチ（自分から I/O 待ちで席を譲った回数）と、**非自発的コンテキストスイッチ（まだ作業中なのに OS から強制的に CPU を取り上げられた回数）** | **`Delta_NonVol_CtxtSw`（10秒間の強制剥奪回数）が数千〜数万回に跳ね上がる場合、スレッド数がコア数に対して多すぎて CPU の奪い合い（スラッシング）が起きている決定的証拠！** |
| `TCP_Established` / `TCP_CloseWait` / `TCP_TimeWait` / `TCP_SynRecv` / `TCP_ListenDrops` | コンテナ内部の TCP 通信ソケット状態内訳 | ・`TCP_CloseWait` 増加 ＝ 対向先が切断したのにアプリ側がソケットを `close()` していないリーク<br>・`TCP_ListenDrops > 0` ＝ 受け付けキュー (`accept` backlog) から溢れて接続が捨てられた決定的証拠 |

---

## 8. ④ `-XX:ActiveProcessorCount` の設定要否を判断するために必要な情報の取得と自動判定ロジック

### 8.1 そもそも `-XX:ActiveProcessorCount` とは何か？（歴史と背景）

Java (JVM) は起動する瞬間、**`Runtime.getRuntime().availableProcessors()`（自分が使える CPU コア数はいくつか？）** を調べ、その数をもとに **内部のあらゆるスレッドプールの初期サイズを自動決定（エルゴノミクス設定）** します。

| JVM が認識したコア数 ($N$) に連動する項目 | 算出式（OpenJDK 21 / JBoss EAP 8.1 の目安） | もし 0.75 vCPU のコンテナが「8 コア」と誤認したら？ | もし 4 vCPU のコンテナが「1 コア」と誤認したら？ |
|---|---|---|---|
| **G1/Parallel GC スレッド数 (`ParallelGCThreads`)** | $N \le 8$ のとき $N$ 本 | 0.75 コアしかないのに **8 本の GC スレッド** が一斉に走り、お互いのロック待ちで GC 停止時間が数倍に悪化する | 4 コアあるのに **1 本の GC スレッド** しか動かず、GC が終わらない |
| **並行 GC スレッド数 (`ConcGCThreads`)** | $\max(1, \lfloor \text{ParallelGCThreads} / 4 \rfloor)$ | 2 本 | 1 本 |
| **JIT コンパイラスレッド数 (`CICompilerCount`)** | $\ge 2$（コア数に応じ増加） | 4 本 | 2 本 |
| **共通 ForkJoinPool (`ForkJoinPool.commonPool`)** | $\max(1, N - 1)$ | 7 本（`parallelStream()` や `CompletableFuture` が暴走） | 1 本（並列処理が直列化） |
| **JBoss Undertow IO スレッド数 (`io-threads`)** | $N \times 2$ | 16 本 | 2 本 |
| **JBoss Undertow Worker スレッド数 (`task-max-threads`)** | $N \times 16$ | **128 本** | **16 本（高負荷時にすぐスレッド枯渇）** |

### 8.2 AWS ECS Fargate × OpenJDK 21 で起きる「2つの問題」

1. **問題 A：マルチコンテナ同居時（`front` + `back` + サイドカー）の「タスク CPU 丸見え問題」**
   - ECS Fargate でタスク全体に `2048` (2 vCPU) を割り当て、その中に `front` (768)、`back` (1024)、`adot-collector` (128)、`cwagent` (128) の 4 コンテナを同居させる場合を考えます。
   - タスク定義でコンテナ個別のハードリミットが未設定（cgroup v2 の `cpu.max` が `max`）の場合、またはタスク全体のクォータが見える場合、OpenJDK 21 は **「自分は 2 コア丸ごと使える！」** と認識します。
   - すると `front` も 2 コア分のスレッドを作り、`back` も 2 コア分のスレッドを作り、合計 4 コア分以上のスレッドが 2 vCPU のタスク枠に殺到します。
2. **問題 B：1 vCPU 未満（例：0.5 vCPU = 512 CPU units / 0.75 vCPU = 768 CPU units）と CFS スロットリングの罠**
   - Linux カーネルの CPU スケジューラ（CFS: Completely Fair Scheduler）は、**100 ミリ秒 (`cfs_period_us = 100,000 us`)** ごとに CPU 使用時間の持ち分（クォータ）を配ります。
   - もしコンテナに `0.5 vCPU` (`cpu.max = 50000 100000`) が割り当てられていると、「100 ミリ秒のうち合計 50 ミリ秒間だけ CPU を使ってよい」というルールになります。
   - ここで JVM が 2 コアと認識して **4 本のスレッドが同時に 12.5 ミリ秒ずつ走ると、開始からわずか 12.5 ミリ秒で持ち分の 50 ミリ秒を使い果たし、残りの 87.5 ミリ秒間は Linux カーネルによってコンテナ全体が強制一時停止（CFS スロットリング：`nr_throttled` カウント増加）** させられます！
   - このとき、CloudWatch Container Insights の 1 分平均 CPU 使用率は低く見えるのに、アプリのレスポンスタイムが 100ms 単位でカクカク遅延する怪現象が起きます。

### 8.3 `04_active_processor_diag.tsv` が収集する全項目と自動要否判定アルゴリズム

本実装の [`docker/base/perf-metrics.sh`](docker/base/perf-metrics.sh) は、10 秒ごとに以下の情報をすべて収集し、**`-XX:ActiveProcessorCount` の設定が必要かどうかを 5 段階で自動判定** します。

1. **ハードウェア・ECS 割当層**:
   - `Host_Physical_CPUs` (`/proc/cpuinfo` の物理コア数)
   - `ECS_Task_CPU_Units` / `ECS_Container_CPU_Units` / `Task_Container_Count` (ECS メタデータ v4 から取得したタスク CPU、コンテナ CPU、同居コンテナ数)
2. **Linux cgroup 制限層 (v2 / v1 両対応)**:
   - `Cgroup_Version` (`v2` or `v1`)
   - `Cgroup_Quota_us` / `Cgroup_Period_us` (`/sys/fs/cgroup/cpu.max` または `cpu.cfs_quota_us` / `cpu.cfs_period_us`)
   - `Cgroup_Effective_vCPU` ($\text{Quota} / \text{Period}$ から算出した実効 vCPU 数。例: `0.75`、`1.00`、`2.00`)
   - `Cgroup_Weight_Shares` (`cpu.weight` または `cpu.shares`)
3. **JVM 認識・派生スレッド層**:
   - `Explicit_ActiveProcessorCount_Flag` (現在 `-XX:ActiveProcessorCount` が明示指定されているか)
   - `JVM_Recognized_Processors` (JVM が実際に認識しているコア数)
   - `ParallelGCThreads` / `ConcGCThreads` / `CICompilerCount` / `ForkJoin_Parallelism` / `Undertow_IO_Threads` / `Undertow_Worker_Threads`
4. **Linux CFS スロットリング実測層 (`/sys/fs/cgroup/cpu.stat`)**:
   - `CFS_nr_periods` / `CFS_nr_throttled` (累計周期数とスロットリング発生回数)
   - `Delta_Periods` / `Delta_Throttled` (直近 10 秒間の周期数とスロットリング回数)
   - **`Throttle_Rate_Pct` (直近 10 秒間の CFS スロットリング発生率 `%` = `Delta_Throttled / Delta_Periods * 100`)**
   - `CFS_throttled_ms` / `Delta_Throttled_ms` (CPU を強制停止させられた累計ミリ秒と直近 10 秒間の増加ミリ秒)
5. **自動要否判定 (`Necessity_Judgment`) と推奨値 (`Recommended_ActiveProcessorCount`)**:

| 判定コード (`Necessity_Judgment`) | 判定条件 | 意味とアクション |
|---|---|---|
| **`REQUIRED_SUB_VCPU`** (要設定：1vCPU未満スロットリング発生) | 実効 vCPU $< 1.0$ かつ CFS スロットリング率 $\ge 5.0\%$ | 1 vCPU 未満の割当に対してスレッドが過剰生成され CFS スロットリングが多発中。`-XX:ActiveProcessorCount=1` の設定と Worker スレッド数の明示抑制が必須。 |
| **`REQUIRED_SET_LOWER`** (要設定：マルチコンテナ過大認識) | 同居コンテナ数 $> 1$ かつ `JVM_Recognized_Processors` $>$ 推奨値 かつ CFS スロットリング率 $\ge 5.0\%$ | 同一 ECS タスク内の複数コンテナ（`front`+`back`+サイドカー）で CPU 共食いによるスロットリングが発生中。`-XX:ActiveProcessorCount=<推奨値>` の明示設定が必須。 |
| **`RECOMMENDED_PIN`** (推奨：マルチコンテナ予防固定) | 同居コンテナ数 $> 1$ かつ未指定 (`unset`) かつ `JVM_Recognized_Processors` $>$ 推奨値 | 現時点のスロットリング率は低いが、同一タスク内マルチコンテナ構成のため、ピーク負荷時の共食い防止として `-XX:ActiveProcessorCount=<推奨値>` の明示固定を推奨。 |
| **`REQUIRED_INCREASE`** (要設定：過小認識による性能未発揮) | `JVM_Recognized_Processors` $<$ 推奨値 かつ スロットリング率 $< 1.0\%$ | 実効 vCPU に対して JVM 認識コア数が少なく制限されており、CPU 性能を使い切れていない。`-XX:ActiveProcessorCount=<推奨値>` への引き上げが必要。 |
| **`OPTIMAL_OK`** (設定不要・適正稼働中) | 上記以外（認識コア数と実効 vCPU が整合し、スロットリング率 $< 5.0\%$） | OpenJDK 21 のコンテナ認識と実効 vCPU が一致し、CFS スロットリングも発生していない理想的な状態。 |

---

## 9. ⑤ コンテナビルド引数 (`ENABLE_PERF_METRICS`) による有効/無効切替と 1 ファイル集約アーキテクチャ

### 9.1 設計ポリシー：なぜ「1 ファイル (`perf-metrics.sh`)」に集約し、無効時は一切読み込まないのか？

本番環境で稼働するコンテナイメージと性能試験用のコンテナイメージで Dockerfile やエントリポイントが別々に分岐してしまうと、「性能試験でテストしたイメージと本番イメージの中身が違う」という構成ドリフト事故が起きます。

そこで本実装では、以下のアーキテクチャを採用しています。

1. **性能試験用の全ロジック（ビルド時検証・起動時バナー・`standalone.xml` 統計有効化・JVM フラグ注入・①②③④の10秒間隔収集デーモン）を [`docker/base/perf-metrics.sh`](docker/base/perf-metrics.sh)（コンテナ内 `/usr/local/bin/perf-metrics.sh`）の 1 ファイルに完全集約**。
2. **Dockerfile（[`docker/base/Dockerfile`](docker/base/Dockerfile)、[`docker/front/Dockerfile`](docker/front/Dockerfile)、[`docker/back/Dockerfile`](docker/back/Dockerfile)）に `ARG ENABLE_PERF_METRICS=false` を定義**。
   - `--build-arg ENABLE_PERF_METRICS=true` でビルドすると、環境変数 `ENV ENABLE_PERF_METRICS=true` がイメージに焼き込まれます。
   - 指定しない場合（本番ビルド）は `false` となります。
3. **エントリポイント（[`docker/base/entrypoint.sh`](docker/base/entrypoint.sh)）のセクション `5-B` で、`ENABLE_PERF_METRICS=true` のときだけ `. /usr/local/bin/perf-metrics.sh` を読み込んで実行**。
   - 無効時 (`false`) は `/usr/local/bin/perf-metrics.sh` を読み込まず、`[efs-entrypoint] perf-metrics: disabled (ENABLE_PERF_METRICS=false)` と1行出力するだけで、本番コンテナと 100% 同一の挙動・メモリフットプリントを維持します。
   - 有効時 (`true`) はコンテナ起動ログ（CloudWatch Logs / 標準出力）に以下の明確なバナーを出力し、有効であることが一目で分かります。

```text
================================================================================
[PERF-METRICS] ★ JMeter Performance Test Metrics Collection: ENABLED ★
[PERF-METRICS]   Build/Runtime Flag : ENABLE_PERF_METRICS=true
[PERF-METRICS]   Container Role     : front (ROLE=front)
[PERF-METRICS]   ECS Service Name   : intra-web
[PERF-METRICS]   Sampling Interval  : 10 seconds
[PERF-METRICS]   Logical Output Dir : /mnt/logs/front/logs/intra-web/mid/current
[PERF-METRICS]   Physical Write Dir : /mnt/logs/front/logs/intra-web/mid/20261024223849-a1b2c3d4
[PERF-METRICS]   Output Files:
[PERF-METRICS]     [1] DB Pool & CLI : /mnt/logs/front/logs/intra-web/mid/current/01_jboss_cli_stats.tsv
[PERF-METRICS]     [2] Heap/GC & JFR : /mnt/logs/front/logs/intra-web/mid/current/02_jvm_heap_gc_stats.tsv
[PERF-METRICS]                         /mnt/logs/front/logs/intra-web/mid/current/02_flight_recording.jfr
[PERF-METRICS]     [3] top/ps/Thread : /mnt/logs/front/logs/intra-web/mid/current/03_process_thread_stats.tsv
[PERF-METRICS]     [4] ActiveCPU Diag: /mnt/logs/front/logs/intra-web/mid/current/04_active_processor_diag.tsv
================================================================================
```

---

## 10. ⑥ Windows 11 PowerShell スクリプトによるモノトーン Excel レポート自動生成

### 10.1 [`Convert-PerfMetricsToExcel.ps1`](Convert-PerfMetricsToExcel.ps1) の特徴

1. **Excel 未インストール環境でも動作する Pure .NET OpenXML 生成エンジン**
   - Windows 11 標準の PowerShell 5.1（および PowerShell 7+）に内蔵されている `System.IO.Compression` のみを使用し、OpenXML (`.xlsx`) を直接バイナリ構築します。Excel COM オートメーションや外部モジュール（`ImportExcel` 等）のインストールは一切不要です。
2. **ログファイルパスからのコンテナ種別・サービス名の自動抽出とファイル名反映**
   - 入力されたフォルダパス（例：`/mnt/logs/front/logs/intra-web/mid/current`）や各メトリクスファイル内の `# METRICS_LOG_PATH:` ヘッダを解析し、以下のルールで自動変換して出力 Excel ファイル名に含めます。
     - `front` → **`フロントコンテナ`**
     - `back` → **`バックコンテナ`**
     - `intra-web` → **`intra-webサービス`**
     - `intra-api` → **`intra-apiサービス`**
     - `inter-api` → **`inter-apiサービス`**
     - `sf-api` → **`sf-apiサービス`**
   - 出力ファイル名フォーマット：
     `JMeter_PerfMetrics_Report_<フロントコンテナ|バックコンテナ>_<intra-web|intra-api|inter-api|sf-api>サービス_<YYYYMMDD_HHMMSS>.xlsx`
3. **美しく視認性の高い「モノトーン（白黒・グレースケール）＋ Meiryo UI」デザイン**
   - チャコールブラック (`#1A1A1A`) のタイトルバナー、ダークスレート (`#333333`) のテーブルヘッダ、ホワイト (`#FFFFFF`) とライトグレー (`#F7F7F7`) のゼブラストライプ行、および異常検知時（`WARN` / `CRITICAL` / `REQUIRED_*`）のモノトーン濃淡ハイライトバッジを適用しています。
   - 全 6 シート構成：
     1. **`サマリー`**：コンテナ・サービス情報、①〜④の件数・異常件数集計、および `-XX:ActiveProcessorCount` 最終要否判定サマリー
     2. **`1_DB接続プール_JBossCLI`**：`01_jboss_cli_stats.tsv` の全時系列データ
     3. **`2_ヒープ_GC_JFR`**：`02_jvm_heap_gc_stats.tsv` の全時系列データ
     4. **`3_top_ps_プロセス状況`**：`03_process_thread_stats.tsv` の全時系列データ
     5. **`4_ActiveProcessorCount要否`**：`04_active_processor_diag.tsv` の全時系列データと診断理由
     6. **`5_詳細ログ_jcmd_JFR_top`**：`01_jboss_cli_raw.log`、`02_jcmd_jfr_detail.log` (`jfr summary` 含む)、`03_top_ps_detail.log`、`04_active_processor_report.txt` の詳細ログ一覧
