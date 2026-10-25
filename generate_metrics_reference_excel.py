# -*- coding: utf-8 -*-
"""
Generate a beautiful Monotone Excel reference workbook with Meiryo UI font
documenting all container metrics collected by perf-metrics.sh and Convert-PerfMetricsToExcel.ps1,
along with exact, ready-to-run implementation commands for each metric.
"""

import sys
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

def create_metrics_excel(output_path):
    wb = openpyxl.Workbook()
    # Remove default sheet after creating custom sheets
    default_sheet = wb.active
    
    # ---------------------------------------------------------
    # Styles definition (Monotone & Meiryo UI)
    # ---------------------------------------------------------
    font_family = "Meiryo UI"
    
    # Fonts
    font_title = Font(name=font_family, size=14, bold=True, color="FFFFFF")
    font_subtitle = Font(name=font_family, size=10, bold=False, color="E0E0E0")
    font_sec_hdr = Font(name=font_family, size=11, bold=True, color="FFFFFF")
    font_tbl_hdr = Font(name=font_family, size=9.5, bold=True, color="FFFFFF")
    font_data = Font(name=font_family, size=9.5, bold=False, color="1A1A1A")
    font_data_bold = Font(name=font_family, size=9.5, bold=True, color="1A1A1A")
    font_code = Font(name=font_family, size=9, bold=False, color="1A1A1A")
    font_code_bold = Font(name=font_family, size=9, bold=True, color="000000")
    font_meta_key = Font(name=font_family, size=9.5, bold=True, color="262626")
    font_meta_val = Font(name=font_family, size=9.5, bold=False, color="333333")
    
    # Fills (Monotone Grayscale Palette)
    fill_title = PatternFill(start_color="1A1A1A", end_color="1A1A1A", fill_type="solid")       # Very dark charcoal
    fill_subtitle = PatternFill(start_color="2D2D2D", end_color="2D2D2D", fill_type="solid")    # Dark charcoal
    fill_sec_hdr = PatternFill(start_color="404040", end_color="404040", fill_type="solid")     # Medium charcoal
    fill_tbl_hdr = PatternFill(start_color="333333", end_color="333333", fill_type="solid")     # Charcoal slate
    fill_even = PatternFill(start_color="FFFFFF", end_color="FFFFFF", fill_type="solid")        # Pure white
    fill_odd = PatternFill(start_color="F7F7F7", end_color="F7F7F7", fill_type="solid")         # Very soft light gray
    fill_meta_k = PatternFill(start_color="E8E8E8", end_color="E8E8E8", fill_type="solid")      # Light gray
    fill_meta_v = PatternFill(start_color="FAFAFA", end_color="FAFAFA", fill_type="solid")      # Off-white
    fill_code_bg = PatternFill(start_color="F2F2F2", end_color="F2F2F2", fill_type="solid")     # Code background gray
    
    # Borders
    border_thin_gray = Side(style="thin", color="D0D0D0")
    border_medium_dark = Side(style="medium", color="262626")
    border_double_bottom = Side(style="double", color="333333")
    
    border_cell = Border(left=border_thin_gray, right=border_thin_gray, top=border_thin_gray, bottom=border_thin_gray)
    border_hdr = Border(left=border_thin_gray, right=border_thin_gray, top=border_medium_dark, bottom=border_medium_dark)
    border_title = Border(left=border_medium_dark, right=border_medium_dark, top=border_medium_dark, bottom=border_medium_dark)
    
    # Alignments
    align_center = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_left = Alignment(horizontal="left", vertical="center", wrap_text=True)
    align_right = Alignment(horizontal="right", vertical="center", wrap_text=True)
    align_top_left = Alignment(horizontal="left", vertical="top", wrap_text=True)
    align_top_center = Alignment(horizontal="center", vertical="top", wrap_text=True)
    align_top_right = Alignment(horizontal="right", vertical="top", wrap_text=True)

    def apply_banner(ws, title, subtitle):
        ws.row_dimensions[1].height = 36
        ws.row_dimensions[2].height = 24
        
        # Merge across columns A to H
        ws.merge_cells("A1:H1")
        c1 = ws["A1"]
        c1.value = f"  {title}"
        c1.font = font_title
        c1.fill = fill_title
        c1.alignment = Alignment(horizontal="left", vertical="center")
        
        ws.merge_cells("A2:H2")
        c2 = ws["A2"]
        c2.value = f"  {subtitle}"
        c2.font = font_subtitle
        c2.fill = fill_subtitle
        c2.alignment = Alignment(horizontal="left", vertical="center")
        
        ws.row_dimensions[3].height = 8

    def format_table(ws, start_row, headers, rows_data, col_widths, code_cols=[6]):
        header_row = start_row
        ws.row_dimensions[header_row].height = 28
        
        for col_idx, h in enumerate(headers, 1):
            cell = ws.cell(row=header_row, column=col_idx)
            cell.value = h
            cell.font = font_tbl_hdr
            cell.fill = fill_tbl_hdr
            cell.alignment = align_center
            cell.border = border_hdr

        current_row = header_row + 1
        for r_idx, r_data in enumerate(rows_data):
            # Dynamic row height calculation for perfect readability
            max_lines = 1
            for c_idx, val in enumerate(r_data):
                if val is None:
                    continue
                s = str(val)
                lines = s.split('\n')
                w = col_widths[c_idx] if c_idx < len(col_widths) else 30
                cell_lines = 0
                for line in lines:
                    char_units = sum(2 if ord(ch) > 127 else 1 for ch in line)
                    wrapped = max(1, (char_units + w - 1) // w)
                    cell_lines += wrapped
                max_lines = max(max_lines, cell_lines)
            
            row_h = max(24, min(240, max_lines * 14.5 + 8))
            ws.row_dimensions[current_row].height = row_h
            row_fill = fill_even if r_idx % 2 == 0 else fill_odd
            
            for c_idx, val in enumerate(r_data, 1):
                cell = ws.cell(row=current_row, column=c_idx)
                cell.value = val
                cell.border = border_cell
                
                # Check code column
                if (c_idx - 1) in code_cols:
                    cell.font = font_code
                    cell.fill = fill_code_bg if r_idx % 2 == 0 else fill_odd
                    cell.alignment = align_top_left
                elif c_idx in [1, 2]: # No, Column Name
                    cell.font = font_data_bold if c_idx == 2 else font_data
                    cell.fill = row_fill
                    cell.alignment = align_top_center if c_idx == 1 else align_top_left
                else:
                    cell.font = font_data
                    cell.fill = row_fill
                    cell.alignment = align_top_left
                    
            current_row += 1
            
        # Apply column widths
        for col_idx, w in enumerate(col_widths, 1):
            col_letter = get_column_letter(col_idx)
            ws.column_dimensions[col_letter].width = w

        ws.freeze_panes = f"A{header_row + 1}"
        return current_row

    # =========================================================================
    # Sheet 0: 目次・概要 (Overview)
    # =========================================================================
    ws0 = wb.create_sheet(title="0_目次・全体概要")
    apply_banner(ws0, 
                 "JMeter 性能試験用 コンテナ内部メトリクス収集スクリプト 出力項目 & 実装コマンド完全リファレンス",
                 "対象環境: AWS ECS Fargate (readonlyRootFilesystem=true) / UBI 9.8 / OpenJDK 21 / JBoss EAP 8.1 / EFS mid/current")
    
    ws0.row_dimensions[4].height = 24
    ws0.merge_cells("A4:H4")
    ws0["A4"] = "  1. 本リファレンスの構成とシート一覧"
    ws0["A4"].font = font_sec_hdr
    ws0["A4"].fill = fill_sec_hdr
    ws0["A4"].alignment = align_left
    
    s0_headers = ["シート名", "ファイル名", "区分・目的", "収集項目数", "主要取得コマンド / 取得ツール", "CloudWatch Container Insights との棲み分け"]
    s0_data = [
        ["1_DB接続プール_JBossCLI", "01_jboss_cli_stats.tsv\n01_jboss_cli_raw.log", "AP/DB接続プール・Webリスナー・Worker・JTAトランザクション統計", "35項目", "jboss-cli.sh --connect (datasources / undertow / io / transactions)", "外側からは完全不可視のDB接続待ち行列(WaitCount)やタイムアウト(TimedOut)、リクエスト処理時間を監視"],
        ["2_ヒープ_GC_JFR_JVM", "02_jvm_heap_gc_stats.tsv\n02_jcmd_jfr_detail.log\n02_flight_recording.jfr", "JVM ヒープ世代別内訳・GC回数/停止時間/原因・CodeCache・NMT・JFR", "37項目", "jstat (-gc/-gccause/-class/-compiler), jcmd (heap_info/native_memory/codecache), jfr summary", "OSメモリ(RSS)だけでなく、Eden/Survivor/Old/Metaspaceの内訳とFull GC停止時間(STW)、ヒープ外メモリを監視"],
        ["3_top_ps_プロセス状況", "03_process_thread_stats.tsv\n03_top_ps_detail.log", "スレッド単位CPU/状態・カーネル待機関数(wchan)・FD・強制切替・TCP状態", "30項目", "top -H -b -n 1, ps -L -o ..., /proc/<pid>/fd, /proc/<pid>/status, /proc/net/tcp, netstat", "コンテナ全体CPUだけでなく、Undertow/GC/JITどのスレッドが高負荷か、futex/ep_poll等の停止原因、ソケット枯渇を特定"],
        ["4_ActiveProcessorCount要否", "04_active_processor_diag.tsv\n04_active_processor_report.txt", "-XX:ActiveProcessorCount 設定要否判断・Linux CFS スロットリング診断", "31項目", "nproc, cgroup v2 cpu.max / cpu.stat, ECS Metadata v4, jcmd VM.flags -all", "平均CPUでは見えない100ms単位のCFSスロットリング率(%)と、マルチコンテナ同居時の過大スレッド生成を確定診断"],
        ["5_起動時環境証跡", "00_perf_metrics_startup_env.txt", "性能試験モード起動設定・コンテナ役割・サービス名・JAVA_OPTS証跡", "9項目", "date, env, /proc/<pid>/cmdline, perf-metrics.sh バナー", "試験実施時の起動フラグ・サンプリング間隔(10秒)・JVMオプションが正しく適用されていたかの改ざん不能な証跡"],
        ["6_実装コマンド即座一覧", "スクリプト全体", "そのままコピー＆ペーストで実装・ターミナル実行可能なコマンド集", "全カテゴリ", "Bash 1行コマンド / CLI コマンド / パイプライン抽出コマンド集", "コンテナ内調査やスクリプト改修、手動ヘルスチェック時にそのまま叩ける完全なコマンドライン集"]
    ]
    format_table(ws0, 5, s0_headers, s0_data, [26, 28, 38, 14, 40, 50], code_cols=[4])
    
    # Notes section
    r_note = len(s0_data) + 7
    ws0.row_dimensions[r_note].height = 24
    ws0.merge_cells(f"A{r_note}:H{r_note}")
    ws0[f"A{r_note}"] = "  2. 性能試験におけるコンテナ内部メトリクス設計の最重要ポイント"
    ws0[f"A{r_note}"].font = font_sec_hdr
    ws0[f"A{r_note}"].fill = fill_sec_hdr
    ws0[f"A{r_note}"].alignment = align_left
    
    notes_kv = [
        ("CloudWatch Container Insights 拡張との境界線", "CloudWatch Container Insights 拡張で見える「コンテナ全体のCPU使用率(%)」「コンテナメモリ使用量(RSS)」「ネットワーク送受信バイト」「ディスクI/O」はスクリプト内での重複取得を完全に除外しています。本スクリプトは、外側からは絶対に見えない「APサーバ内部(DB接続待ち・Undertow・JTA)」「JVM内部(世代別ヒープ・GC STW時間・CodeCache・NMT)」「Linuxカーネル深層(スレッド状態・wchan・FD枯渇・非自発的コンテキストスイッチ・TCP ListenDrops)」「CFSスロットリング実測率」に特化して極小オーバーヘッドで収集します。"),
        ("readonlyRootFilesystem: true 対策の完全性", "ECS Fargate のゼロトラスト要件によりコンテナルートファイルシステムが書き込み不可の場合、従来の jcmd/jstat/JFR/jboss-cli は全滅します。本スクリプトは起動オプションに -XX:+StartAttachListener -XX:-PerfDisableSharedMem -Djava.io.tmpdir=/tmp を注入し、さらに HOME=/tmp, JDK_JAVA_OPTIONS=\"\" により一時ディレクトリを書き込み可能な /tmp に完全固定することで、セキュリティを一切緩めることなく安定動作を実現しています。"),
        ("1ファイル集約と本番・試験の完全一致", "全収集デーモン、XML統計有効化、起動証跡出力ロジックを docker/base/perf-metrics.sh の 1 ファイルに集約。ENABLE_PERF_METRICS=false (デフォルト本番時) はスクリプトを一切読み込まず、本番コンテナと 100% 同一のバイナリ・フットプリントを維持します。試験時のみ ENABLE_PERF_METRICS=true で起動します。"),
        ("EFS mid/current シンボリックリンクとの整合性", "書き込み実体は各タスク固有のタイムスタンプディレクトリ /mnt/logs/<front|back>/logs/<Service_Name>/mid/<LOG_ID>/ 配下に行い、外部参照用に current シンボリックリンクを自動維持します。複数タスク同時起動時でもログの混濁や破損が一切起きません。"),
        ("モノトーン＆Meiryo UI レポート出力", "PowerShell スクリプト (Convert-PerfMetricsToExcel.ps1) により、Excel 未インストール環境でも .NET 標準機能のみで美しい白黒・グレースケール＋Meiryo UI フォントの .xlsx レポートを瞬時に自動生成します。フロント/バックおよびサービス名(intra-web/intra-api/inter-api/sf-api)がファイル名に自動付与されます。")
    ]
    
    cur_nr = r_note + 1
    for k, v in notes_kv:
        ws0.row_dimensions[cur_nr].height = 42
        ws0.merge_cells(f"B{cur_nr}:H{cur_nr}")
        ws0.cell(row=cur_nr, column=1, value=k).font = font_meta_key
        ws0.cell(row=cur_nr, column=1).fill = fill_meta_k
        ws0.cell(row=cur_nr, column=1).border = border_cell
        ws0.cell(row=cur_nr, column=1).alignment = align_top_left
        
        ws0.cell(row=cur_nr, column=2, value=v).font = font_meta_val
        ws0.cell(row=cur_nr, column=2).fill = fill_meta_v
        ws0.cell(row=cur_nr, column=2).border = border_cell
        ws0.cell(row=cur_nr, column=2).alignment = align_top_left
        cur_nr += 1

    # =========================================================================
    # Sheet 1: ① DB接続プール・JBoss CLI (01_jboss_cli_stats.tsv)
    # =========================================================================
    ws1 = wb.create_sheet(title="1_DB接続プール_JBossCLI")
    apply_banner(ws1,
                 "① JBoss EAP 8.1 jboss-cli DB接続プール・Undertow・Worker・JTAトランザクション統計",
                 "出力ファイル: 01_jboss_cli_stats.tsv / 01_jboss_cli_raw.log (サンプリング間隔: 10秒)")
    
    s1_headers = [
        "No.", "TSVカラム名", "サブシステム / 属性名", "項目名 & 単位",
        "項目の詳細内容・意味・背景 (小学生向けたとえ含む)",
        "性能試験での着眼点・異常判定基準 (WARN / CRITICAL)",
        "そのまま実装に利用できるコマンド (Bash / jboss-cli.sh / awk)",
        "コマンド詳細解説・抽出オプション"
    ]
    
    cli_base_cmd = (
        'HOME=/tmp JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" \\\n'
        'JAVA_OPTS="-Xms32m -Xmx64m -XX:+UseSerialGC -XX:ActiveProcessorCount=1 -Djava.io.tmpdir=/tmp -Duser.home=/tmp" \\\n'
        '/opt/jboss-eap/bin/jboss-cli.sh --connect --controller=remote+http://127.0.0.1:${MGMT_PORT} --commands="'
    )
    
    s1_data = [
        [
            1, "Timestamp_JST", "共通ヘッダ", "計測日時 [YYYY-MM-DD HH:MM:SS]",
            "メトリクス取得時刻 (日本標準時 JST)。JMeter の実行ログ (jtl) や CloudWatch メトリクスと 1 秒単位で突き合わせるための基準時間。",
            "JMeter 側の高負荷印加開始・ピーク負荷・終了時刻と完全に一致しているか確認。",
            "TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'",
            "date コマンドで JST タイムスタンプを安全に取得 (タイムゾーン環境変数を考慮)。"
        ],
        [
            2, "Container", "共通ヘッダ", "コンテナ種別 [front / back]",
            "フロントコンテナ (intra-web, inter-api) かバックコンテナ (intra-api, sf-api) かの識別コード。",
            "front / back 間の呼出連動とボトルネック所在の特定に使用。",
            'echo "${COMPONENT_ROLE:-${Component_name:-front}}"',
            "コンテナ起動時の環境変数からフロント/バックを自動正規化。"
        ],
        [
            3, "Service", "共通ヘッダ", "ECSサービス名",
            "intra-web / intra-api / inter-api / sf-api の各業務サービス名。",
            "対象サービス固有の負荷特性や閾値判定の照合に使用。",
            'echo "${Service_Name:-${SERVICE_NAME:-intra-web}}"',
            "サービス名正規化ヘルパー。"
        ],
        [
            4, "Task_LogID", "共通ヘッダ", "ECSタスク識別子",
            "タスク固有のタイムスタンプまたは ECS タスク ID (EFS 書込実体フォルダ名)。",
            "スケールアウト時や複数タスク起動時にログが混ざらないよう分離。",
            'echo "${LOG_ID:-$(date +%Y%m%d%H%M%S)-perf}"',
            "タスクログIDの生成・取得。"
        ],
        [
            5, "Datasource_Name", "datasources", "データソース名",
            "JBoss に登録されているデータソースの JNDI 名 / リソース名 (例: MIF02JA_JDS, MySQLXADS)。",
            "業務ごとに複数データソースが存在する場合、各データソースごとに 1 行ずつ出力される。",
            cli_base_cmd + '/subsystem=datasources:read-children-resources(child-type=data-source,include-runtime=true,recursive=true)"',
            "データソースの子リソースを再帰的にランタイム統計付きで一括取得。"
        ],
        [
            6, "DS_Type", "datasources", "データソース種別",
            "標準 DataSource (ローカルTx) または XA-DataSource (2フェーズコミット分散Tx)。",
            "XA データソースは 2PC オーバーヘッドがあるため、接続解放遅延に注意。",
            cli_base_cmd + '/subsystem=datasources:read-children-resources(child-type=xa-data-source,include-runtime=true,recursive=true)"',
            "XA データソースの子リソースを再帰取得。"
        ],
        [
            7, "MaxPoolSize", "datasources/pool", "最大プールサイズ [個]",
            "DB接続専用カートの最大台数。これ以上は同時に物理コネクションを開かない上限値。",
            "負荷試験時の想定最大同時接続数 (max-pool-size) が正しく反映されているか確認。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}:read-attribute(name=max-pool-size)" | grep -o "[0-9]*"',
            "max-pool-size 属性値を抽出。"
        ],
        [
            8, "ActiveCount", "datasources/pool", "物理コネクション総数 [個]",
            "DB との間で実際に確立され維持されている物理コネクションの総数 (使用中＋アイドル空き)。",
            "MaxPoolSize まで自動伸長しているか、プール最小値 (min-pool-size) からの推移を確認。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=ActiveCount)"',
            "ActiveCount (現在確立されているコネクション数) を抽出。"
        ],
        [
            9, "InUseCount", "datasources/pool", "現在使用中コネクション数 [個]",
            "今まさに料理人 (スレッド) が握って SQL を投げているカートの数。最も重要な指標。",
            "InUseCount が MaxPoolSize に張り付いた場合、プール枯渇警報。空き待ちが発生する前兆。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=InUseCount)"',
            "InUseCount をリアルタイム抽出。"
        ],
        [
            10, "AvailableCount", "datasources/pool", "即時利用可能コネクション数 [個]",
            "あと何台カートが空いているか。AvailableCount = MaxPoolSize - InUseCount。",
            "【CRITICAL判定】0 になると、次のリクエストはカート待ち行列に並ばされ遅延が始まる！",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=AvailableCount)"',
            "AvailableCount を抽出。"
        ],
        [
            11, "PoolUsage_Pct", "計算値", "プール使用率 [%]",
            "InUseCount / MaxPoolSize * 100。プールの圧迫率。",
            "80% 以上で WARN (注意)、95% 以上で CRITICAL (枯渇寸前/危険)。",
            "awk -v u=\"$inuse\" -v m=\"$maxp\" 'BEGIN { printf \"%.1f\", (m>0)?(u*100.0/m):0 }'",
            "InUse と MaxPoolSize からパーセンテージを即時計算。"
        ],
        [
            12, "MaxUsedCount", "datasources/pool", "最大同時使用コネクション数 [個]",
            "起動または統計リセット以降に、同時に使用されたコネクションの過去最大値 (ピークハイウォーターマーク)。",
            "試験ピーク時に MaxPoolSize に到達した実績があるかを一発で確認。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=MaxUsedCount)"',
            "MaxUsedCount 属性値を抽出。"
        ],
        [
            13, "WaitCount", "datasources/pool", "コネクション空き待ち発生回数 [回]",
            "空きコネクションがなくなり、スレッドが「待ち」に入った累計回数 (行列を作った人数)。",
            "【WARN判定】1 以上が継続・増加している場合、DB接続プールが性能ボトルネックになっている決定的証拠！",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=WaitCount)"',
            "WaitCount (ブロックされたスレッド数) を抽出。"
        ],
        [
            14, "MaxWaitTime_ms", "datasources/pool", "最大待ち時間 [ミリ秒]",
            "コネクションが空くまで待たされた最長待機時間 (ms)。",
            "数十ms〜数秒に跳ね上がっている場合、レスポンス悪化 (Tail Latency) の主因。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=MaxWaitTime)"',
            "MaxWaitTime をミリ秒単位で抽出。"
        ],
        [
            15, "TimedOut", "datasources/pool", "コネクション取得タイムアウト数 [回]",
            "blocking-timeout-wait-millis 待ってもコネクションが取れずに例外エラーとなった回数。",
            "【CRITICAL判定】1 回でも発生したら即致命的エラー！アプリで SQL エラー (TimeoutException) が発生。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=TimedOut)"',
            "TimedOut (タイムアウト発生数) を抽出。"
        ],
        [
            16, "TotalBlockingTime_ms", "datasources/pool", "累計ブロック待機時間 [ミリ秒]",
            "全スレッドがコネクション空き待ちでブロックされていた時間の総計 (ms)。",
            "スループット低下時に、どれだけのCPU時間がDBプール待ちで無駄に浪費されたかを定量化。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=TotalBlockingTime)"',
            "TotalBlockingTime を抽出。"
        ],
        [
            17, "AvgCreationTime_ms", "datasources/pool", "平均コネクション生成時間 [ミリ秒]",
            "DB との新規物理ソケット接続・ハンドシェイクにかかる平均所要時間 (ms)。",
            "ネットワーク遅延や DB サーバの CPU 高負荷により接続確立が遅延していないかを診断。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=AverageCreationTime)"',
            "AverageCreationTime を抽出。"
        ],
        [
            18, "DestroyedCount", "datasources/pool", "破棄コネクション累計数 [個]",
            "アイドルタイムアウトや接続切断例外によりクローズ・破棄された物理コネクションの累計数。",
            "急増している場合、DB 側でのセッション切断や不正なコネクションリークを疑う。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=pool:read-attribute(name=DestroyedCount)"',
            "DestroyedCount を抽出。"
        ],
        [
            19, "PrepStmtCache_HitCnt", "datasources/jdbc", "PreparedStatement キャッシュヒット数 [回]",
            "SQL 実行時に構文解析済みの PreparedStatement キャッシュを再利用できた回数。",
            "Hit 率 = Hit / (Hit + Miss)。80% 以上が望ましい。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=jdbc:read-attribute(name=PreparedStatementCacheHitCount)"',
            "PreparedStatementCacheHitCount を抽出。"
        ],
        [
            20, "PrepStmtCache_MissCnt", "datasources/jdbc", "PreparedStatement キャッシュミス数 [回]",
            "キャッシュになく、DB 側で再度 SQL を PreparedStatement コンパイルした回数。",
            "Miss が急増している場合、prepared-statements-cache-size の上限不足または動的SQLの多用。",
            cli_base_cmd + '/subsystem=datasources/data-source=${DS}/statistics=jdbc:read-attribute(name=PreparedStatementCacheMissCount)"',
            "PreparedStatementCacheMissCount を抽出。"
        ],
        [
            21, "Undertow_ReqCount", "undertow", "HTTPリクエスト総数 [件]",
            "Undertow デフォルト HTTP リスナーが処理した累計リクエスト数。",
            "JMeter 側の総送信リクエスト数と一致するか、途中の ALB でドロップされていないかを確認。",
            cli_base_cmd + '/subsystem=undertow/server=default-server/http-listener=default:read-attribute(name=request-count)"',
            "request-count を抽出。"
        ],
        [
            22, "Undertow_ErrCount", "undertow", "HTTPエラー総数 [件]",
            "5xx 系の内部エラーが発生した累計リクエスト数。",
            "【CRITICAL判定】負荷増加に伴い増加していないか監視。JMeter のエラー件数と突き合わせ。",
            cli_base_cmd + '/subsystem=undertow/server=default-server/http-listener=default:read-attribute(name=error-count)"',
            "error-count を抽出。"
        ],
        [
            23, "Undertow_MaxProcTime_ms", "undertow", "最長処理時間 [ミリ秒]",
            "最も時間がかかった 1 リクエストの処理時間 (ms)。",
            "スパイク遅延の最大値を特定。JMeter の Max レスポンスタイムと相関。",
            cli_base_cmd + '/subsystem=undertow/server=default-server/http-listener=default:read-attribute(name=max-processing-time)"',
            "max-processing-time を抽出。"
        ],
        [
            24, "Undertow_ProcTime_ms", "undertow", "累計処理時間 [ミリ秒]",
            "全リクエストの処理時間の総和 (ms)。",
            "平均レスポンスタイム = Undertow_ProcTime_ms / Undertow_ReqCount の算出に使用。",
            cli_base_cmd + '/subsystem=undertow/server=default-server/http-listener=default:read-attribute(name=processing-time)"',
            "processing-time を抽出。"
        ],
        [
            25, "Worker_BusyThreads", "io/worker", "Workerビジー稼働スレッド数 [本]",
            "JBoss IO Worker スレッドプールで、現在リクエストを処理中の稼働スレッド数。",
            "Worker_MaxThreads に張り付いていないか監視。張り付くとリクエストがキューに待たされる。",
            cli_base_cmd + '/subsystem=io/worker=default:read-attribute(name=busy-task-thread-count)"',
            "busy-task-thread-count を抽出。"
        ],
        [
            26, "Worker_MaxThreads", "io/worker", "Worker最大スレッド数 [本]",
            "Undertow Worker スレッドプールの最大サイズ (task-max-threads)。",
            "コア数×16 で自動計算された値、または standalone.xml で明示指定した設定値。",
            cli_base_cmd + '/subsystem=io/worker=default:read-attribute(name=task-max-threads)"',
            "task-max-threads を抽出。"
        ],
        [
            27, "Worker_QueueSize", "io/worker", "Workerキュー滞留タスク数 [件]",
            "空きスレッドがなくなり、処理待ちキューに溜まっているリクエストの数。",
            "【WARN判定】0 より大きい状態が続く場合、スレッドプール不足またはバックエンド遅延。",
            cli_base_cmd + '/subsystem=io/worker=default:read-attribute(name=queue-size)"',
            "queue-size を抽出。"
        ],
        [
            28, "Worker_Rejected", "io/worker", "Workerリクエスト拒否数 [件]",
            "キューも上限に達し、Undertow が受け付けを拒否 (お断り) した累計回数。",
            "【CRITICAL判定】1 でも発生したら即座にシステムパンク状態。",
            cli_base_cmd + '/subsystem=io/worker=default:read-attribute(name=rejected-count)"',
            "rejected-count を抽出。"
        ],
        [
            29, "JTA_TotalTx", "transactions", "JTAトランザクション総数 [件]",
            "開始されたトランザクションの累計数。",
            "秒間トランザクション処理数 (TPS) の算出に使用。",
            cli_base_cmd + '/subsystem=transactions:read-attribute(name=number-of-transactions)"',
            "number-of-transactions を抽出。"
        ],
        [
            30, "JTA_CommittedTx", "transactions", "コミットトランザクション数 [件]",
            "正常にコミット完了したトランザクション数。",
            "CommittedTx / TotalTx で正常完了率を評価。",
            cli_base_cmd + '/subsystem=transactions:read-attribute(name=number-of-committed-transactions)"',
            "number-of-committed-transactions を抽出。"
        ],
        [
            31, "JTA_AbortedTx", "transactions", "ロールバックトランザクション数 [件]",
            "アプリケーション例外やエラーによりロールバック (アボート) されたトランザクション数。",
            "業務エラーの発生率を監視。",
            cli_base_cmd + '/subsystem=transactions:read-attribute(name=number-of-aborted-transactions)"',
            "number-of-aborted-transactions を抽出。"
        ],
        [
            32, "JTA_TimedOutTx", "transactions", "タイムアウトトランザクション数 [件]",
            "トランザクションタイムアウト値を超過して強制ロールバックされたトランザクション数。",
            "【WARN判定】長大 SQL や行ロック・デッドロック待ちの発生を示す。",
            cli_base_cmd + '/subsystem=transactions:read-attribute(name=number-of-timed-out-transactions)"',
            "number-of-timed-out-transactions を抽出。"
        ],
        [
            33, "JTA_InFlightTx", "transactions", "現在実行中トランザクション数 [件]",
            "今まさに処理中 (In-Flight) のトランザクション数。",
            "同時実行トランザクションの密度を把握。",
            cli_base_cmd + '/subsystem=transactions:read-attribute(name=number-of-inflight-transactions)"',
            "number-of-inflight-transactions を抽出。"
        ],
        [
            34, "JTA_Heuristics", "transactions", "ヒューリスティック完了数 [件]",
            "XA 分散トランザクションで片側だけコミットされ不整合が発生した異常件数。",
            "【CRITICAL判定】データ不整合の危機。1 件でもあれば重大障害。",
            cli_base_cmd + '/subsystem=transactions:read-attribute(name=number-of-heuristics)"',
            "number-of-heuristics を抽出。"
        ],
        [
            35, "Status_Eval", "自動評価", "総合評価ステータス",
            "全メトリクスの閾値判定に基づくステータス (NORMAL / WARN / CRITICAL)。",
            "TimedOut>0, Worker_Rejected>0, Heuristics>0, PoolUsage>=95% で CRITICAL。WaitCount>0 で WARN。",
            'awk -v to="$timedout" -v rej="$rej" -v pct="$pct" \'BEGIN { if(to>0||rej>0||pct>=95) print "CRITICAL"; else if(pct>=80) print "WARN"; else print "NORMAL" }\'',
            "awk によるリアルタイム総合ステータス判定。"
        ]
    ]
    format_table(ws1, 5, s1_headers, s1_data, [6, 24, 20, 26, 46, 44, 52, 40], code_cols=[6])

    # =========================================================================
    # Sheet 2: ② ヒープ・GC・JFR・JVM (02_jvm_heap_gc_stats.tsv)
    # =========================================================================
    ws2 = wb.create_sheet(title="2_ヒープ_GC_JFR_JVM")
    apply_banner(ws2,
                 "② OpenJDK 21 (Red Hat build) jstat / jcmd / JFR ヒープ世代別・GC停止時間・ネイティブメモリ統計",
                 "出力ファイル: 02_jvm_heap_gc_stats.tsv / 02_jcmd_jfr_detail.log / 02_flight_recording.jfr")
    
    s2_headers = [
        "No.", "TSVカラム名", "取得元ツール / 領域", "項目名 & 単位",
        "項目の詳細内容・意味・背景 (小学生向けたとえ含む)",
        "性能試験での着眼点・異常判定基準 (WARN / CRITICAL)",
        "そのまま実装に利用できるコマンド (Bash / jstat / jcmd / jfr)",
        "コマンド詳細解説・抽出オプション"
    ]
    
    jstat_cmd_base = 'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jstat -J-Djava.io.tmpdir=/tmp '
    jcmd_cmd_base  = 'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir=/tmp ${PID} '
    
    s2_data = [
        [1, "Timestamp_JST", "共通ヘッダ", "計測日時 [YYYY-MM-DD HH:MM:SS]", "メトリクス取得時刻 (日本標準時)。", "基準時刻。", "TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'", "date コマンド。"],
        [2, "Container", "共通ヘッダ", "コンテナ種別 [front / back]", "フロントコンテナかバックコンテナか。", "種別判定。", 'echo "${COMPONENT_ROLE:-front}"', "環境変数正規化。"],
        [3, "Service", "共通ヘッダ", "ECSサービス名", "intra-web / intra-api / inter-api / sf-api。", "サービス識別。", 'echo "${Service_Name:-intra-web}"', "サービス名正規化。"],
        [4, "PID", "OSプロセス", "JavaプロセスPID", "JBoss EAP を実行している Java プロセスの PID。", "jstat/jcmd のアタッチ先 PID。", 'jps -l | grep jboss-modules | awk \'{print $1}\'', "jps または ps コマンドで JBoss プロセスの PID を自動検出。"],
        [5, "S0_Pct", "jstat -gc / -gccause", "Survivor 0 使用率 [%]", "Survivor 領域 0 (From 空間) の使用率 %。Young GC を生き残ったオブジェクトが一時退避される。", "S0 と S1 が交互に使用される動きを確認。", jstat_cmd_base + '-gccause ${PID} | tail -n 1 | awk \'{print $1}\'', "jstat -gccause の第1カラム (S0)。"],
        [6, "S1_Pct", "jstat -gc / -gccause", "Survivor 1 使用率 [%]", "Survivor 領域 1 (To 空間) の使用率 %。", "S0 と S1 の交互移動とオブジェクトの昇格状況を確認。", jstat_cmd_base + '-gccause ${PID} | tail -n 1 | awk \'{print $2}\'', "jstat -gccause の第2カラム (S1)。"],
        [7, "Eden_Pct", "jstat -gc / -gccause", "Eden 領域使用率 [%]", "新規オブジェクトが生成される「まな板」の使用率 %。100% に達すると Young GC がトリガーされる。", "Young GC の周期と頻度を分析。", jstat_cmd_base + '-gccause ${PID} | tail -n 1 | awk \'{print $3}\'', "jstat -gccause の第3カラム (E)。"],
        [8, "Old_Pct", "jstat -gc / -gccause", "Old 領域使用率 [%]", "長寿命オブジェクトが保管される「作業台」の使用率 %。", "【CRITICAL判定】75% 以上で WARN、90% 以上で Full GC / メモリリークの危険性大！", jstat_cmd_base + '-gccause ${PID} | tail -n 1 | awk \'{print $4}\'', "jstat -gccause の第4カラム (O)。"],
        [9, "Metaspace_Pct", "jstat -gc / -gccause", "Metaspace 使用率 [%]", "クラスメタデータが格納されるネイティブメモリ領域の使用率 %。", "90% 以上で WARN。クラスローダーリークがないかを診断。", jstat_cmd_base + '-gccause ${PID} | tail -n 1 | awk \'{print $5}\'', "jstat -gccause の第5カラム (M)。"],
        [10, "CCS_Pct", "jstat -gc / -gccause", "Compressed Class Space 使用率 [%]", "圧縮クラスポインタ領域の使用率 %。", "上限設定 (CompressedClassSpaceSize) に対する余裕を確認。", jstat_cmd_base + '-gccause ${PID} | tail -n 1 | awk \'{print $6}\'', "jstat -gccause の第6カラム (CCSCS)。"],
        [11, "Eden_Used_KB", "jstat -gc", "Eden 使用量 [KB]", "Eden 領域の現在使用バイト数 (KB)。", "メモリ割り当て速度 (Allocation Rate MB/s) の算出に使用。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $6}\'', "jstat -gc の EU カラム。"],
        [12, "Eden_Cap_KB", "jstat -gc", "Eden 容量 [KB]", "Eden 領域の現在の確保容量 (KB)。G1GC では動的に伸縮する。", "G1GC のエルゴノミクスによる Eden 伸縮挙動を確認。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $5}\'', "jstat -gc の EC カラム。"],
        [13, "Survivor_Used_KB", "jstat -gc", "Survivor 合計使用量 [KB]", "Survivor 0 と 1 の使用量合計 (S0U + S1U, KB)。", "短命オブジェクトが Survivor で消滅せず Old へ早期昇格 (Premature Promotion) していないか診断。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $3 + $4}\'', "jstat -gc の S0U + S1U 合計。"],
        [14, "Old_Used_KB", "jstat -gc", "Old 使用量 [KB]", "Old 領域の現在使用バイト数 (KB)。", "GC 後に Old 使用量が下がりきらず右肩上がりの場合、メモリリークの決定的証拠。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $8}\'', "jstat -gc の OU カラム。"],
        [15, "Old_Cap_KB", "jstat -gc", "Old 容量 [KB]", "Old 領域の現在の確保容量 (KB)。", "最大ヒープ (-Xmx) に対する Old 領域の割合。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $7}\'', "jstat -gc の OC カラム。"],
        [16, "Metaspace_Used_KB", "jstat -gc", "Metaspace 使用量 [KB]", "クラスメタデータの実際の使用バイト数 (KB)。", "アプリデプロイ後、定常状態で一定値にサチっているか確認。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $10}\'', "jstat -gc の MU カラム。"],
        [17, "Metaspace_Cap_KB", "jstat -gc", "Metaspace 容量 [KB]", "Metaspace の現在確保容量 (KB)。", "MaxMetaspaceSize に対する安全マージン。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $9}\'', "jstat -gc の MC カラム。"],
        [18, "YGC_Count", "jstat -gc", "Young GC 累計回数 [回]", "JVM 起動からの Young GC (G1 Evacuation Pause) 累計実行回数。", "頻度の推移を確認。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $13}\'', "jstat -gc の YGC カラム。"],
        [19, "Delta_YGC", "計算値", "直近10秒の Young GC 回数 [回]", "直近 10 秒間での Young GC 発生回数 (YGC - PREV_YGC)。", "10 秒間に 20 回以上など頻発している場合、Eden が狭すぎるか不要オブジェクト生成過多。", 'awk -v cur="$ygc" -v prev="$prev_ygc" \'BEGIN { print (prev>0&&cur>=prev)?(cur-prev):0 }\'', "直前値との差分計算。"],
        [20, "YGCT_s", "jstat -gc", "Young GC 累計停止時間 [秒]", "Young GC による累計 Stop-The-World 停止時間 (秒)。", "平均 Young GC 時間 = YGCT / YGC の算出に使用。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $14}\'', "jstat -gc の YGCT カラム。"],
        [21, "FGC_Count", "jstat -gc", "Full GC 累計回数 [回]", "全作業を止めて行う「大掃除」Full GC の累計回数。", "【CRITICAL判定】通常運用・性能試験において Full GC は 1 回でも発生してはならない！", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $15}\'', "jstat -gc の FGC カラム。"],
        [22, "Delta_FGC", "計算値", "直近10秒の Full GC 回数 [回]", "直近 10 秒間で発生した Full GC 回数。", "【CRITICAL判定】1 以上なら即座に CRITICAL アラート。数秒単位のサービス全面停止が発生。", 'awk -v cur="$fgc" -v prev="$prev_fgc" \'BEGIN { print (prev>0&&cur>=prev)?(cur-prev):0 }\'', "Full GC 差分検出。"],
        [23, "FGCT_s", "jstat -gc", "Full GC 累計停止時間 [秒]", "Full GC による累計 Stop-The-World 停止時間 (秒)。", "Full GC による遅延影響の総計。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $16}\'', "jstat -gc の FGCT カラム。"],
        [24, "CGC_Count", "jstat -gc", "Concurrent GC 累計回数 [回]", "G1GC の並行マーク処理 (Concurrent Marking) 累計サイクル回数。", "Old 領域の回収が並行してスムーズに行われているか確認。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $17}\'', "jstat -gc の CGC カラム。"],
        [25, "CGCT_s", "jstat -gc", "Concurrent GC 累計時間 [秒]", "並行マーク処理にかかった累計時間 (秒)。アプリケーション停止は伴わない。", "並行 GC スレッドの CPU 消費状況を推し量る指標。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $18}\'', "jstat -gc の CGCT カラム。"],
        [26, "GCT_Total_s", "jstat -gc", "GC 総停止時間 [秒]", "全 GC の合計所要時間 (秒)。", "スループットに対する GC オーバーヘッド割合の算出に使用。", jstat_cmd_base + '-gc ${PID} | tail -n 1 | awk \'{print $19}\'', "jstat -gc の GCT カラム。"],
        [27, "Delta_GCT_ms", "計算値", "直近10秒の GC 停止時間 [ミリ秒]", "直近 10 秒間でアプリが GC で停止させられた時間 (ms)。", "【CRITICAL判定】200ms 以上で WARN、1,000ms (1秒) 以上で CRITICAL (レスポンス致命的遅延)。", 'awk -v cur="$gct" -v prev="$prev_gct" \'BEGIN { print (prev>0&&cur>=prev)?((cur-prev)*1000.0):0.0 }\'', "直近停止時間差分 (ms)。"],
        [28, "Last_GC_Cause", "jstat -gccause", "直前の GC 原因", "最後に発生した GC の原因 (例: G1 Evacuation Pause, Metadata GC Threshold, System.gc())。", "なぜ GC が起きたのかの直接原因を特定。System.gc() 呼び出しがないかもチェック。", jstat_cmd_base + '-gccause ${PID} | tail -n 1 | awk \'{print $(NF-1)}\'', "直前 GC 原因 (LGCC) の抽出。"],
        [29, "Curr_GC_Cause", "jstat -gccause", "現在の GC 原因", "サンプリング瞬間に GC が走っていた場合の理由 (通常は No GC)。", "サンプリング時に GC 中だったかどうかの確認。", jstat_cmd_base + '-gccause ${PID} | tail -n 1 | awk \'{print $NF}\'', "現在 GC 原因 (GCC) の抽出。"],
        [30, "Classes_Loaded", "jstat -class", "ロード済クラス総数 [個]", "現在 JVM にロードされているクラスの総数。", "動的クラス生成やモジュールロードによるリークを検知。", jstat_cmd_base + '-class ${PID} | tail -n 1 | awk \'{print $1}\'', "jstat -class の第1カラム。"],
        [31, "JIT_Compiled", "jstat -compiler", "JIT コンパイル済メソッド数 [個]", "HotSpot JIT コンパイラ (C1/C2) がネイティブコードに最適化コンパイルしたメソッド総数。", "試験ウォームアップ完了時にコンパイル数が安定したかを確認。", jstat_cmd_base + '-compiler ${PID} | tail -n 1 | awk \'{print $1}\'', "jstat -compiler の第1カラム。"],
        [32, "CodeCache_Used_KB", "jcmd Compiler.codecache", "CodeCache 使用量 [KB]", "JIT コンパイルされたネイティブコードを格納する CodeCache の現在使用量 (KB)。", "CodeCache が満杯になると JIT コンパイルが停止し、インタープリタ実行に落ちて性能が 10 倍激減する！", jcmd_cmd_base + 'Compiler.codecache | awk \'/used=/ {gsub(/.*used=/,""); gsub(/K.*/,""); sum+=$1} END {print sum+0}\'', "jcmd Compiler.codecache から used=...K を合計抽出。"],
        [33, "CodeCache_Max_KB", "jcmd Compiler.codecache", "CodeCache 最大容量 [KB]", "CodeCache の最大予約サイズ (KB, ReservedCodeCacheSize)。", "使用率 = CodeCache_Used / CodeCache_Max が 90% に迫っていないか確認。", jcmd_cmd_base + 'Compiler.codecache | awk \'/size=/ {if(match($0,/size=[0-9]+K/)){s=substr($0,RSTART+5,RLENGTH-6); sum+=s}} END {print sum+0}\'', "CodeCache の size=...K を抽出。"],
        [34, "NMT_Total_Committed_KB", "jcmd VM.native_memory", "NMT コミット済ネイティブメモリ [KB]", "JVM 全体の物理メモリ使用量 (ヒープ＋DirectBuffer＋スレッドスタック＋GC領域＋メタスペース)。", "ECS Fargate の OOM Killer (Exit Code 137) を防ぐため、コンテナ制限に対する実使用量を監視。", jcmd_cmd_base + 'VM.native_memory summary | sed -n \'s/.*Total: reserved=[0-9]*KB, committed=\\([0-9]*\\)KB.*/\\1/p\'', "NMT summary から committed=...KB を抽出。"],
        [35, "JFR_State", "jcmd JFR.check", "JFR 稼働状態 [RUNNING / OFF]", "Java Flight Recorder の連続録画が正常に RUNNING 状態を維持しているか。", "JFR が正常に稼働し、万が一のコンテナ停止時にもフライトデータが残る状態かを保証。", jcmd_cmd_base + 'JFR.check | grep -o "running" | tr \'a-z\' \'A-Z\' || echo "OFF"', "JFR.check の実行結果判定。"],
        [36, "JFR_Size_KB", "ファイルサイズ", "JFR バイナリファイル容量 [KB]", "EFS 上に出力されている 02_flight_recording.jfr の現在ファイルサイズ (KB)。", "maxsize=250M に達してローテーションしているか、容量肥大化がないかを確認。", 'wc -c < /mnt/logs/front/logs/intra-web/mid/current/02_flight_recording.jfr | awk \'{print int($1/1024)}\'', "JFR バイナリのファイルサイズを KB 単位で取得。"],
        [37, "Status_Eval", "自動評価", "総合評価ステータス", "ヒープ・GC・停止時間の判定 (NORMAL / WARN / CRITICAL)。", "Delta_FGC>0, Old_Pct>=90%, Delta_GCT_ms>=1000 で CRITICAL。Old_Pct>=75% で WARN。", 'awk -v fgc="$dfgc" -v opct="$opct" -v gct="$dgct" \'BEGIN { if(fgc>0||opct>=90||gct>=1000) print "CRITICAL"; else if(opct>=75||gct>=200) print "WARN"; else print "NORMAL" }\'', "総合ステータス評価。"]
    ]
    format_table(ws2, 5, s2_headers, s2_data, [6, 24, 24, 26, 46, 44, 52, 40], code_cols=[6])

    # =========================================================================
    # Sheet 3: ③ top / ps / procfs スレッド・プロセス・OS (03_process_thread_stats.tsv)
    # =========================================================================
    ws3 = wb.create_sheet(title="3_プロセス_スレッド_OS")
    apply_banner(ws3,
                 "③ UBI 9.8 top (-H) / ps (-L) / procfs 深層スレッド状態・FD・コンテキストスイッチ・TCP統計",
                 "出力ファイル: 03_process_thread_stats.tsv / 03_top_ps_detail.log (サンプリング間隔: 10秒)")
    
    s3_headers = [
        "No.", "TSVカラム名", "取得元 / コマンド", "項目名 & 単位",
        "項目の詳細内容・意味・背景 (小学生向けたとえ含む)",
        "性能試験での着眼点・異常判定基準 (WARN / CRITICAL)",
        "そのまま実装に利用できるコマンド (Bash / top / ps / procfs)",
        "コマンド詳細解説・抽出オプション"
    ]
    
    s3_data = [
        [1, "Timestamp_JST", "共通ヘッダ", "計測日時 [YYYY-MM-DD HH:MM:SS]", "メトリクス取得時刻 (日本標準時)。", "基準時刻。", "TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'", "date コマンド。"],
        [2, "Container", "共通ヘッダ", "コンテナ種別 [front / back]", "フロントコンテナかバックコンテナか。", "種別判定。", 'echo "${COMPONENT_ROLE:-front}"', "環境変数正規化。"],
        [3, "Service", "共通ヘッダ", "ECSサービス名", "intra-web / intra-api / inter-api / sf-api。", "サービス識別。", 'echo "${Service_Name:-intra-web}"', "サービス名正規化。"],
        [4, "PID", "OSプロセス", "JavaプロセスPID", "JBoss EAP Java プロセスの PID。", "監視対象プロセス。", 'perf_find_jboss_pid', "JBoss PID 検出関数。"],
        [5, "JVM_Threads_Total", "ps -L", "JVM 総スレッド数 [本]", "Java プロセス内で稼働している OS レベルの全スレッド数 (LWP 数)。", "スレッドリークによりスレッド数が右肩上がりに増え続けていないか確認。", 'LC_ALL=C ps -L -p ${PID} --no-headers | wc -l', "ps -L で対象プロセスの全 LWP (スレッド) 行数をカウント。"],
        [6, "Threads_Running_R", "ps -L (STAT)", "実行中スレッド数 (R) [本]", "今まさに CPU を使って走行中、または CPU 実行待ち状態のスレッド数 (State: R)。", "実効 vCPU 数を大きく超えて常時張り付いている場合は CPU 飽和状態。", 'LC_ALL=C ps -L -p ${PID} -o stat --no-headers | grep -c "^R"', "STAT カラムの先頭が R のスレッド数をカウント。"],
        [7, "Threads_DiskSleep_D", "ps -L (STAT)", "無停止I/O待機スレッド数 (D) [本]", "ディスクI/Oや EFS 応答待ちで固まり、シグナルでも中断できない料理人の数 (State: D)。", "【CRITICAL判定】1 本でも継続する場合、EFS / ストレージ I/O のスタック・応答不能の決定的証拠！", 'LC_ALL=C ps -L -p ${PID} -o stat --no-headers | grep -c "^D"', "STAT カラムの先頭が D のスレッド数をカウント。"],
        [8, "Threads_Sleeping_S", "ps -L (STAT)", "通常スリープ中スレッド数 (S) [本]", "イベント待ち・ロック待ち・ソケット待機で通常スリープしているスレッド数 (State: S / I)。", "プールのアイドルスレッド等の正常な待機状態。", 'LC_ALL=C ps -L -p ${PID} -o stat --no-headers | grep -E -c "^[SI]"', "STAT カラムが S または I のスレッド数をカウント。"],
        [9, "Threads_Zombie_Z", "ps -L (STAT)", "ゾンビ状態スレッド数 (Z) [本]", "終了したのに親プロセスに回収されていないゾンビ状態のスレッド数 (State: Z)。", "【CRITICAL判定】0 より大きい場合はプロセス管理の異常。", 'LC_ALL=C ps -L -p ${PID} -o stat --no-headers | grep -c "^Z"', "STAT カラムが Z のスレッド数をカウント。"],
        [10, "Top1_Thread_TID", "ps -L / top -H", "Top1 スレッド TID (LWP)", "対象プロセス内で現在最も CPU を消費しているスレッドの ID (LWP)。", "jstack / JFR と突き合わせてどのコードを実行中かをピンポイント特定。", 'LC_ALL=C ps -L -p ${PID} -o lwp --sort=-pcpu --no-headers | head -n 1', "CPU 消費率降順でソートした先頭スレッドの LWP を取得。"],
        [11, "Top1_Thread_Name", "ps -L (comm)", "Top1 スレッド名", "最も CPU を食っているスレッドの名前 (例: default task-12, G1 Conc#0, C2 CompilerThre)。", "業務処理(Undertow)か、GCか、JITか、犯人の正体を一目で特定！", 'LC_ALL=C ps -L -p ${PID} -o comm --sort=-pcpu --no-headers | head -n 1', "CPU 降順先頭スレッドのコマンド・スレッド名を取得。"],
        [12, "Top1_Thread_CPU_Pct", "ps -L (pcpu)", "Top1 スレッド CPU使用率 [%]", "Top1 スレッドの CPU 使用率 %。", "1 つのスレッドが 100% 近くに張り付いている場合、無限ループや重い正規表現処理を疑う。", 'LC_ALL=C ps -L -p ${PID} -o pcpu --sort=-pcpu --no-headers | head -n 1', "CPU 降順先頭スレッドの pcpu 値を取得。"],
        [13, "Top1_Thread_State", "ps -L (stat)", "Top1 スレッド状態", "Top1 スレッドの実行状態 (R, S, D 等)。", "実行中(R)か、ロック待ち(S)か、I/O待ち(D)か。", 'LC_ALL=C ps -L -p ${PID} -o stat --sort=-pcpu --no-headers | head -n 1 | cut -c 1', "先頭スレッドの stat の1文字目を取得。"],
        [14, "Top1_Thread_WCHAN", "ps -L (wchan)", "Top1 スレッド待機関数 (wchan)", "スレッドがスリープしているカーネル内の待機関数名 (例: futex_wait_queue_me, ep_poll, do_epoll_wait)。", "futex なら Java ロック競合 (synchronized)、ep_poll ならソケット/DB応答待ち、0 なら CPU 走行中。", 'LC_ALL=C ps -L -p ${PID} -o wchan:24 --sort=-pcpu --no-headers | head -n 1', "ps -L の wchan:24 でカーネル待機シンボルを抽出。"],
        [15, "Top2_Thread_Name", "ps -L (comm)", "Top2 スレッド名", "2番目に CPU を消費しているスレッドの名前。", "Top1 と Top2 を見ることで、並列処理のバランスや GC との競合を把握。", 'LC_ALL=C ps -L -p ${PID} -o comm --sort=-pcpu --no-headers | sed -n "2p"', "CPU 降順 2 行目のスレッド名を取得。"],
        [16, "Top2_Thread_CPU_Pct", "ps -L (pcpu)", "Top2 スレッド CPU使用率 [%]", "Top2 スレッドの CPU 使用率 %。", "第2位の負荷規模。", 'LC_ALL=C ps -L -p ${PID} -o pcpu --sort=-pcpu --no-headers | sed -n "2p"', "CPU 降順 2 行目の pcpu 値を取得。"],
        [17, "Open_FDs", "/proc/<pid>/fd", "オープン済 FD 数 [個]", "プロセスが現在開いているファイルディスクリプタ総数 (ファイル、ソケット、パイプ)。", "FD リークにより上限に迫っていないか監視。", 'ls -1 /proc/${PID}/fd 2>/dev/null | wc -l', "/proc/<pid>/fd ディレクトリ内のエントリ数を高速カウント。"],
        [18, "Max_FDs_Limit", "/proc/<pid>/limits", "FD 上限数 [個]", "プロセスに許容されているオープンファイル数のソフトリミット (Max open files, 例: 65536)。", "ECS タスク定義の ulimits 設定が正しく適用されているか確認。", 'awk \'/Max open files/ {print $4}\' /proc/${PID}/limits', "/proc/<pid>/limits から Max open files の Soft Limit を抽出。"],
        [19, "FD_Usage_Pct", "計算値", "FD 使用率 [%]", "Open_FDs / Max_FDs_Limit * 100。", "【CRITICAL判定】70% 以上で WARN、85% 以上で CRITICAL (Too many open files 障害の直前)。", 'awk -v o="$open_fds" -v m="$max_fds" \'BEGIN { printf "%.1f", (m>0)?(o*100.0/m):0 }\'', "FD 使用率を即時計算。"],
        [20, "Min_PageFaults", "ps (min_flt)", "マイナーページフォルト数 [回]", "ディスク I/O を伴わずに完了したマイナーページフォルト累計回数 (物理ページ割当)。", "メモリ割り当ての活発さを把握。", 'LC_ALL=C ps -p ${PID} -o min_flt --no-headers', "ps の min_flt 出力。"],
        [21, "Maj_PageFaults", "ps (maj_flt)", "メジャーページフォルト数 [回]", "ディスクからのデータ読み込みを伴った重いメジャーページフォルト累計回数。", "【WARN判定】急増している場合、実メモリ不足によりキャッシュが効かずディスク読込が発生中。", 'LC_ALL=C ps -p ${PID} -o maj_flt --no-headers', "ps の maj_flt 出力。"],
        [22, "Voluntary_CtxtSw", "/proc/<pid>/status", "自発的コンテキストスイッチ [回]", "スレッド自ら I/O 完了待ちやロック待ちで CPU を譲り渡した累計回数。", "正常な処理待ちの頻度。", 'awk \'/^voluntary_ctxt_switches:/ {print $2}\' /proc/${PID}/status', "/proc/<pid>/status から voluntary_ctxt_switches を抽出。"],
        [23, "NonVoluntary_CtxtSw", "/proc/<pid>/status", "非自発的コンテキストスイッチ [回]", "まだ実行中なのに、タイムスライス切れや優先度によりカーネルに強制的に CPU を奪われた累計回数。", "CPU コアに対してスレッドが多すぎる場合の強制剥奪回数。", 'awk \'/^nonvoluntary_ctxt_switches:/ {print $2}\' /proc/${PID}/status', "/proc/<pid>/status から nonvoluntary_ctxt_switches を抽出。"],
        [24, "Delta_NonVol_CtxtSw", "計算値", "直近10秒の強制CPU剥奪回数 [回]", "直近 10 秒間での非自発的コンテキストスイッチ増加数。", "【WARN判定】5,000 回以上/10秒 に跳ね上がっている場合、スレッド過多による CPU スラッシングの決定的証拠！", 'awk -v cur="$nonvol" -v prev="$prev_nonvol" \'BEGIN { print (prev>0&&cur>=prev)?(cur-prev):0 }\'', "直前値との差分計算。"],
        [25, "TCP_Established", "/proc/net/tcp", "確立中 TCP 接続数 (ESTABLISHED) [本]", "現在通信が確立している TCP ソケット数 (State 01)。", "クライアントおよび DB との同時接続総数。", 'awk \'$1 ~ /^[0-9]+:/ && $4 == "01" {c++} END {print c+0}\' /proc/net/tcp /proc/net/tcp6', "TCP state 01 (ESTABLISHED) をカウント。"],
        [26, "TCP_CloseWait", "/proc/net/tcp", "クローズ待ち TCP 接続数 (CLOSE_WAIT) [本]", "相手側から切断されたのに、アプリが socket.close() していないソケット数 (State 08)。", "【CRITICAL判定】増加し続ける場合、アプリ側のソケットリークの決定的証拠！", 'awk \'$1 ~ /^[0-9]+:/ && $4 == "08" {c++} END {print c+0}\' /proc/net/tcp /proc/net/tcp6', "TCP state 08 (CLOSE_WAIT) をカウント。"],
        [27, "TCP_TimeWait", "/proc/net/tcp", "タイム待機 TCP 接続数 (TIME_WAIT) [本]", "自側から切断後にパケット遅延を待っているソケット数 (State 06)。", "急増するとローカルポート枯渇 (EADDRNOTAVAIL) を引き起こす。", 'awk \'$1 ~ /^[0-9]+:/ && $4 == "06" {c++} END {print c+0}\' /proc/net/tcp /proc/net/tcp6', "TCP state 06 (TIME_WAIT) をカウント。"],
        [28, "TCP_SynRecv", "/proc/net/tcp", "接続受付待ち TCP 接続数 (SYN_RECV) [本]", "SYN を受信し ACK 待ちの半接続状態ソケット数 (State 03)。", "SYN Flood 攻撃や accept 処理遅延の検知。", 'awk \'$1 ~ /^[0-9]+:/ && $4 == "03" {c++} END {print c+0}\' /proc/net/tcp /proc/net/tcp6', "TCP state 03 (SYN_RECV) をカウント。"],
        [29, "TCP_ListenDrops", "/proc/net/netstat", "Listenキュー溢れ破棄数 [回]", "listen backlog キューが満杯になり、OS カーネルが受信接続をドロップした累計回数。", "【CRITICAL判定】1 回でも発生したら即座に接続拒否障害！Somaxconn や Undertow backlog 不足。", 'awk \'/^TcpExt:/ {if(h==0){for(i=1;i<=NF;i++)if($i=="ListenDrops")c=i; h=1}else if(c>0)print $c+0}\' /proc/net/netstat | tail -n 1', "/proc/net/netstat の ListenDrops カラム値を動的抽出。"],
        [30, "Status_Eval", "自動評価", "総合評価ステータス", "スレッド・FD・TCPの判定 (NORMAL / WARN / CRITICAL)。", "DiskSleep(D)>=3, Zombie>0, FD>=85%, CloseWait>=20, ListenDrops>0 で CRITICAL。D>0, FD>=70% で WARN。", 'awk -v d="$dcnt" -v z="$zcnt" -v fd="$fdpct" -v cw="$cw" -v ld="$ld" \'BEGIN { if(d>=3||z>0||fd>=85||cw>=20||ld>0) print "CRITICAL"; else if(d>0||fd>=70||cw>0) print "WARN"; else print "NORMAL" }\'', "総合ステータス評価。"]
    ]
    format_table(ws3, 5, s3_headers, s3_data, [6, 24, 24, 26, 46, 44, 52, 40], code_cols=[6])

    # =========================================================================
    # Sheet 4: ④ -XX:ActiveProcessorCount 要否判断 (04_active_processor_diag.tsv)
    # =========================================================================
    ws4 = wb.create_sheet(title="4_ActiveProcessorCount要否")
    apply_banner(ws4,
                 "④ -XX:ActiveProcessorCount 設定要否判断・Linux CFS CPU スロットリング診断統計",
                 "出力ファイル: 04_active_processor_diag.tsv / 04_active_processor_report.txt (サンプリング間隔: 10秒)")
    
    s4_headers = [
        "No.", "TSVカラム名", "取得レイヤー / ソース", "項目名 & 単位",
        "項目の詳細内容・意味・背景 (小学生向けたとえ含む)",
        "要否判定ロジックでの役割・推奨アクション",
        "そのまま実装に利用できるコマンド (Bash / cgroup / jcmd)",
        "コマンド詳細解説・抽出オプション"
    ]
    
    s4_data = [
        [1, "Timestamp_JST", "共通ヘッダ", "計測日時 [YYYY-MM-DD HH:MM:SS]", "メトリクス取得時刻 (日本標準時)。", "基準時刻。", "TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'", "date コマンド。"],
        [2, "Container", "共通ヘッダ", "コンテナ種別 [front / back]", "フロントコンテナかバックコンテナか。", "種別判定。", 'echo "${COMPONENT_ROLE:-front}"', "環境変数正規化。"],
        [3, "Service", "共通ヘッダ", "ECSサービス名", "intra-web / intra-api / inter-api / sf-api。", "サービス識別。", 'echo "${Service_Name:-intra-web}"', "サービス名正規化。"],
        [4, "Host_Physical_CPUs", "物理ホスト層", "ホスト物理CPUコア数 [コア]", "Fargate 基盤の物理仮想ホストに存在する物理 CPU コア総数 (例: 2, 4, 8)。", "JVM が cgroup を無視した場合に認識してしまう最大コア数の上限。", "nproc --all 2>/dev/null || grep -c '^processor' /proc/cpuinfo", "ホストの総コア数を取得。"],
        [5, "ECS_Task_CPU_Units", "ECSメタデータ", "ECS タスク全体 CPU ユニット [unit]", "ECS タスク定義全体の CPU 割当 (例: 2048 = 2 vCPU, 4096 = 4 vCPU)。", "タスク全体としての CPU 資源枠。", 'curl -fsS ${ECS_CONTAINER_METADATA_URI_V4}/task | sed -n \'s/.*"Limits".*"CPU":\\([0-9.]*\\).*/\\1/p\'', "ECS メタデータ v4 からタスク制限 CPU を取得。"],
        [6, "ECS_Container_CPU_Units", "ECSメタデータ", "自コンテナ CPU ユニット [unit]", "自コンテナの個別割当 CPU ユニット (例: 768 = 0.75 vCPU, 1024 = 1 vCPU)。", "自コンテナの実質的な割当 vCPU 数。", 'curl -fsS ${ECS_CONTAINER_METADATA_URI_V4} | sed -n \'s/.*"Limits".*"CPU":\\([0-9.]*\\).*/\\1/p\'', "ECS メタデータ v4 からコンテナ個別 CPU を取得。"],
        [7, "Task_Container_Count", "ECSメタデータ", "タスク内同居コンテナ総数 [個]", "同一 ECS タスク内に同居するコンテナ総数 (例: front + back + adot + cwagent = 4)。", "2 個以上の同居時、タスク CPU を奪い合う共食いが発生するため要否判断のキーとなる。", 'curl -fsS ${ECS_CONTAINER_METADATA_URI_V4}/task | grep -o \'"DockerId"\' | wc -l', "タスクメタデータ内のコンテナ数をカウント。"],
        [8, "Cgroup_Version", "OSカーネル層", "cgroup バージョン [v1 / v2]", "UBI 9.8 / カーネル 5.14+ で標準の cgroup v2 か旧式 v1 かの判別。", "v2 では /sys/fs/cgroup/cpu.max、v1 では cpu.cfs_quota_us を参照。", '[ -r /sys/fs/cgroup/cpu.max ] && echo "v2" || echo "v1"', "cpu.max の存在確認で cgroup バージョンを判定。"],
        [9, "Cgroup_Quota_us", "cgroup 制限層", "CFS CPU クォータ [マイクロ秒]", "1 周期あたりにコンテナに許可された最大 CPU 時間 (us)。無制限時は max または -1。", "実効 vCPU = Quota / Period の分子となる最重要制約。", 'awk \'{print $1}\' /sys/fs/cgroup/cpu.max 2>/dev/null || cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us', "cgroup v2 / v1 の CPU クォータ値を取得。"],
        [10, "Cgroup_Period_us", "cgroup 制限層", "CFS 周期長 [マイクロ秒]", "Linux CFS スケジューラの監視周期長 (通常 100,000 us = 100 ms)。", "実効 vCPU = Quota / Period の分母。", 'awk \'{print $2}\' /sys/fs/cgroup/cpu.max 2>/dev/null || cat /sys/fs/cgroup/cpu/cpu.cfs_period_us', "CFS 周期長を取得。"],
        [11, "Cgroup_Effective_vCPU", "計算値", "実効割当 vCPU 数 [vCPU]", "Quota / Period から求めた実効 vCPU 数 (例: 0.75, 1.00, 2.00)。", "コンテナが実際に利用できる論理 vCPU 規模。", 'awk -v q="$quota" -v p="$period" \'BEGIN { printf "%.2f", (q!="max"&&p>0)?(q/p):(task_u/1024.0) }\'', "実効 vCPU を算出。"],
        [12, "Cgroup_Weight_Shares", "cgroup 相対層", "CPU シェア / 重み", "CPU 競合時の重み配分 (cgroup v2: cpu.weight [1-10000], v1: cpu.shares [2-262144])。", "他コンテナと CPU が競合した際の優先度比率。", 'cat /sys/fs/cgroup/cpu.weight 2>/dev/null || cat /sys/fs/cgroup/cpu/cpu.shares', "cpu.weight または cpu.shares を取得。"],
        [13, "Explicit_ActiveProcessorCount_Flag", "起動フラグ", "明示指定 APC フラグ", "現在 -XX:ActiveProcessorCount=N が指定されているか (未指定時は unset(-1))。", "明示設定されているか、JVM による自動エルゴノミクス認識かを区別。", 'tr \'\\0\' \'\\n\' < /proc/${PID}/cmdline | sed -n \'s/^-XX:ActiveProcessorCount=//p\' || echo "unset(-1)"', "プロセスコマンドラインから -XX:ActiveProcessorCount を抽出。"],
        [14, "JVM_Recognized_Processors", "JVM認識層", "JVM 認識コア数 [個]", "OpenJDK 21 の Runtime.getRuntime().availableProcessors() が認識しているコア数。", "実効 vCPU と乖離していないか (過大認識 / 過小認識) を判定する根幹数値。", 'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir=/tmp ${PID} VM.flags -all | awk \'/ActiveProcessorCount/ {for(i=1;i<=NF;i++)if($i=="="){print $(i+1);exit}}\'', "jcmd VM.flags -all から ActiveProcessorCount 値を抽出。"],
        [15, "ParallelGCThreads", "JVMエルゴノミクス", "並列 GC スレッド数 [本]", "G1GC が Young GC / Full GC 停止時に並列稼働させる GC スレッド数。", "過大認識されているとコア数以上の GC スレッドが走りロック競合を起こす。", 'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir=/tmp ${PID} VM.flags -all | awk \'/ParallelGCThreads/ {for(i=1;i<=NF;i++)if($i=="="){print $(i+1);exit}}\'', "ParallelGCThreads を抽出。"],
        [16, "ConcGCThreads", "JVMエルゴノミクス", "並行 GC スレッド数 [本]", "G1GC がバックグラウンドで並行マークを行うスレッド数 (通常 ParallelGCThreads / 4)。", "アプリ稼働中の CPU を奪う並行 GC スレッドの数。", 'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir=/tmp ${PID} VM.flags -all | awk \'/ConcGCThreads/ {for(i=1;i<=NF;i++)if($i=="="){print $(i+1);exit}}\'', "ConcGCThreads を抽出。"],
        [17, "CICompilerCount", "JVMエルゴノミクス", "JIT コンパイラスレッド数 [本]", "HotSpot JIT コンパイルを実行するバックグラウンドスレッド数。", "起動時や高負荷時の JIT CPU 消費を左右。", 'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir=/tmp ${PID} VM.flags -all | awk \'/CICompilerCount/ {for(i=1;i<=NF;i++)if($i=="="){print $(i+1);exit}}\'', "CICompilerCount を抽出。"],
        [18, "ForkJoin_Parallelism", "JVMエルゴノミクス", "ForkJoinPool 並列度 [本]", "共通 ForkJoinPool (parallelStream, CompletableFuture) の並列スレッド数 (Recognized - 1)。", "アプリ内の Java 8 ストリーム並列処理がコア数を超えて暴走していないか確認。", 'awk -v p="$recog_p" \'BEGIN { print (p>1)?(p-1):1 }\'', "JVM 認識コア数から ForkJoin 並列度を算出。"],
        [19, "Undertow_IO_Threads", "JBossエルゴノミクス", "Undertow IO スレッド数 [本]", "XNIO ノンブロッキング通信を処理するセレクタスレッド数 (通常 Recognized * 2)。", "ネットワーク I/O スレッドの適切性。", 'awk -v p="$recog_p" \'BEGIN { print p * 2 }\'', "Undertow IO Threads = コア数 * 2。"],
        [20, "Undertow_Worker_Threads", "JBossエルゴノミクス", "Undertow Worker 最大スレッド [本]", "HTTP リクエストを並列実行するタスクスレッド上限 (通常 Recognized * 16)。", "コア数誤認によりスレッド数が 16 本に縛られたり 128 本に膨らんだりする問題の監視。", 'awk -v p="$recog_p" \'BEGIN { print p * 16 }\'', "Undertow Worker Threads = コア数 * 16。"],
        [21, "CFS_nr_periods", "cgroup 実測層", "CFS 監視周期累計数 [回]", "Linux カーネル CFS スケジューラが 100ms 周期の監視を行った累計回数。", "スロットリング発生率の分母。", 'awk \'/^nr_periods/ {print $2}\' /sys/fs/cgroup/cpu.stat 2>/dev/null || awk \'/^nr_periods/ {print $2}\' /sys/fs/cgroup/cpu/cpu.stat', "cpu.stat から nr_periods を抽出。"],
        [22, "CFS_nr_throttled", "cgroup 実測層", "CFS スロットリング累計数 [回]", "100ms 周期内でクォータを使い果たし、CPU を強制停止させられた累計回数。", "スロットリング発生率の分子。これが増加していると性能劣化中。", 'awk \'/^nr_throttled/ {print $2}\' /sys/fs/cgroup/cpu.stat 2>/dev/null || awk \'/^nr_throttled/ {print $2}\' /sys/fs/cgroup/cpu/cpu.stat', "cpu.stat から nr_throttled を抽出。"],
        [23, "Delta_Periods", "計算値", "直近10秒の CFS 周期数 [回]", "直近 10 秒間での CFS 周期数 (約 100 回/10秒)。", "直近サンプリング区間の分母。", 'awk -v cur="$nr_p" -v prev="$prev_p" \'BEGIN { print (prev>0&&cur>=prev)?(cur-prev):0 }\'', "周期数差分計算。"],
        [24, "Delta_Throttled", "計算値", "直近10秒のスロットリング回数 [回]", "直近 10 秒間で CPU 停止を食らった周期数。", "直近の CPU 停止頻度。", 'awk -v cur="$nr_t" -v prev="$prev_t" \'BEGIN { print (prev>0&&cur>=prev)?(cur-prev):0 }\'', "スロットリング回数差分計算。"],
        [25, "Throttle_Rate_Pct", "計算値", "CFS スロットリング発生率 [%]", "Delta_Throttled / Delta_Periods * 100。直近 10 秒間で何%の周期で CPU 停止を食らったか。", "【最重要指標】5.0% 以上で CPU スロットリング障害認定！レスポンスタイムが激悪化する。", 'awk -v dt="$d_t" -v dp="$d_p" \'BEGIN { printf "%.2f", (dp>0)?(dt*100.0/dp):0 }\'', "スロットリング発生率 % をリアルタイム算出。"],
        [26, "CFS_throttled_ms", "cgroup 実測層", "累計スロットリング停止時間 [ミリ秒]", "CPU を強制停止させられていた時間の累計ミリ秒 (throttled_usec / 1000)。", "CPU が奪われていた時間の総量。", 'awk \'/^throttled_usec/ {print $2 / 1000.0}\' /sys/fs/cgroup/cpu.stat 2>/dev/null', "cpu.stat の throttled_usec をミリ秒変換。"],
        [27, "Delta_Throttled_ms", "計算値", "直近10秒の停止時間 [ミリ秒]", "直近 10 秒間で強制停止させられた時間 (ms)。", "直近 10 秒のうち何ミリ秒間コンテナ全体が凍結されていたか。", 'awk -v cur="$t_usec" -v prev="$prev_u" \'BEGIN { print (prev>0&&cur>=prev)?((cur-prev)/1000.0):0.0 }\'', "停止時間差分ミリ秒。"],
        [28, "LoadAvg_1m", "OS負荷層", "直近1分間ロードアベレージ", "システムの直近 1 分間平均負荷 (実行中＋DiskSleepスレッド数)。", "コンテナ・ホスト全体の負荷規模。", 'awk \'{print $1}\' /proc/loadavg', "/proc/loadavg から 1 分平均負荷を取得。"],
        [29, "Recommended_ActiveProcessorCount", "診断アルゴリズム", "推奨 APC 設定値 [コア]", "マルチコンテナ同居構成および実効 vCPU に基づき自動算出した推奨 -XX:ActiveProcessorCount 値。", "設定変更する場合にそのまま JAVA_OPTS に渡すべき確定推奨値。", 'awk -v v="$eff_vcpu" \'BEGIN { c=int(v+0.49); if(c<1)c=1; print c }\'', "実効 vCPU から推奨 APC を自動算出。"],
        [30, "Necessity_Judgment", "診断アルゴリズム", "要否判定結果コード", "5段階の確定診断コード (REQUIRED_SUB_VCPU / REQUIRED_SET_LOWER / RECOMMENDED_PIN / REQUIRED_INCREASE / OPTIMAL_OK)。", "設定が必要か否か、およびその緊急度判定。", 'perf_diagnose_active_processor_count', "要否判定ルールエンジンによる診断コード出力。"],
        [31, "Diagnosis_Reason", "診断アルゴリズム", "自動判定の具体的理由・アクション", "なぜその判定になったのか、どのようなリスクがあり、どう対処すべきかの日本語詳細説明。", "性能試験報告書・設計レビューでそのまま引用できる診断エビデンス。", 'printf "%s", $Diagnosis_Reason', "診断理由テキスト。"]
    ]
    format_table(ws4, 5, s4_headers, s4_data, [6, 26, 22, 26, 46, 44, 52, 40], code_cols=[6])

    # =========================================================================
    # Sheet 5: ⓪ 起動時環境・設定証跡 (00_perf_metrics_startup_env.txt)
    # =========================================================================
    ws5 = wb.create_sheet(title="5_起動時環境証跡")
    apply_banner(ws5,
                 "⓪ JMeter 性能試験モード 起動時環境設定 & 有効化証跡スナップショット",
                 "出力ファイル: 00_perf_metrics_startup_env.txt (コンテナ起動時に 1 回記録)")
    
    s5_headers = [
        "No.", "設定キー名", "設定種別", "日本語名称 & 設定値例",
        "項目の詳細内容・意味・背景",
        "性能試験での着眼点・監査エビデンスとしての役割",
        "そのまま実装に利用できるコマンド / 参照方法",
        "コマンド詳細解説"
    ]
    
    s5_data = [
        [1, "ENABLE_PERF_METRICS", "ビルド/起動引数", "性能試験メトリクス有効化フラグ [true / false]", "メトリクス収集モードが有効化されているかどうかの最上位スイッチ。", "本番環境では必ず false (デフォルト)、性能試験環境では必ず true であることを確認。", 'echo "${ENABLE_PERF_METRICS:-false}"', "環境変数値の確認。"],
        [2, "CONTAINER_ROLE", "コンテナ設定", "コンテナ役割 [front / back]", "フロントコンテナかバックコンテナかの正規化された役割名称。", "タスク内の役割が正しく反映されているか確認。", 'perf_normalize_role', "役割正規化関数の呼出。"],
        [3, "COMPONENT_NAME", "コンテナ設定", "コンポーネント名 [front / back]", "ECS タスク定義や Dockerfile の Component_name から引き継がれた名前。", "コンテナ名との一致確認。", 'echo "${COMPONENT_NAME}"', "コンポーネント名の出力。"],
        [4, "SERVICE_NAME", "サービス設定", "ECS サービス名 [intra-web, intra-api, etc.]", "4 大業務サービス名 (intra-web / intra-api / inter-api / sf-api) のいずれか。", "出力パスや Excel レポート名に正しく反映されているか確認。", 'perf_normalize_service', "サービス名正規化関数の呼出。"],
        [5, "TASK_LOG_ID", "ログ識別子", "タスク固有ログID [YYYYMMDDHHMMSS-perf 等]", "EFS 実体ディレクトリ名となるタスク固有識別子。", "複数タスク起動時の排他書込の証跡。", 'echo "${PERF_LOG_ID}"', "タスクログIDの出力。"],
        [6, "INTERVAL_SECONDS", "収集デーモン設定", "サンプリング間隔 [秒, 既定: 10]", "バックグラウンド収集デーモンがメトリクスを収集する周期秒数。", "試験中のサンプリング密度 (通常 10 秒) の確認。", 'echo "${PERF_METRICS_INTERVAL:-10}"', "間隔設定値の出力。"],
        [7, "LOGICAL_CURRENT_DIR", "EFS パス", "論理出力ディレクトリ [/mnt/logs/.../mid/current]", "外部運用者や PowerShell スクリプトが参照するシンボリックリンクパス。", "規定のパス規約 (/mnt/logs/<front|back>/logs/<Service_Name>/mid/current) に一致しているか。", 'echo "${PERF_LOGICAL_CURRENT_DIR}"', "論理パスの確認。"],
        [8, "PHYSICAL_WRITE_DIR", "EFS パス", "物理書込ディレクトリ [/mnt/logs/.../mid/<LOG_ID>]", "コンテナが実際に書き込んでいる EFS 実体ディレクトリパス。", "実体ディレクトリの書き込み権限とファイル生成を確認。", 'echo "${PERF_OUT_DIR}"', "物理パスの確認。"],
        [9, "JAVA_OPTS", "JVM 起動オプション", "適用済 JVM 起動フラグ一覧", "readonlyRootFilesystem 対応フラグ (-XX:+StartAttachListener 等) や JFR 設定が注入された最終オプション。", "JFR や NMT、共有メモリフラグが確実に付与されて起動したかの動かぬ証拠。", 'tr \'\\0\' \' \' < /proc/${PID}/cmdline', "起動中プロセスの実効コマンドラインを完全出力。"]
    ]
    format_table(ws5, 5, s5_headers, s5_data, [6, 24, 20, 26, 46, 44, 52, 40], code_cols=[6])

    # =========================================================================
    # Sheet 6: 実装コマンド即座リファレンス (Command Cheat Sheet)
    # =========================================================================
    ws6 = wb.create_sheet(title="6_実装コマンド即座一覧")
    apply_banner(ws6,
                 "JMeter 性能試験コンテナ内部メトリクス そのまま実装・実行できるコマンド完全リファレンス集",
                 "コピー＆ペーストで Linux コンテナ内 Bash ターミナルまたはスクリプトにそのまま実装可能な完全コマンドライン")
    
    s6_headers = [
        "No.", "分類・カテゴリ", "取得目的 / 対象メトリクス", "そのまま実装・ターミナル実行できる完全コマンド", "実行前提条件 / 必須環境変数 / readonlyRootFilesystem 対策"
    ]
    
    s6_data = [
        [
            1, "JBoss CLI 一括取得", "DB接続プール全統計 + Undertow + IO Worker + JTAトランザクション (1回のCLI起動で全取得)",
            'HOME=/tmp JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" \\\n'
            'JAVA_OPTS="-Xms32m -Xmx64m -XX:+UseSerialGC -XX:ActiveProcessorCount=1 -Djava.io.tmpdir=/tmp -Duser.home=/tmp" \\\n'
            '/opt/jboss-eap/bin/jboss-cli.sh --connect --controller=remote+http://127.0.0.1:9990 --commands="\\\n'
            '/subsystem=datasources:read-children-resources(child-type=data-source,include-runtime=true,recursive=true),\\\n'
            '/subsystem=datasources:read-children-resources(child-type=xa-data-source,include-runtime=true,recursive=true),\\\n'
            '/subsystem=undertow/server=default-server/http-listener=default:read-resource(include-runtime=true),\\\n'
            '/subsystem=io/worker=default:read-resource(include-runtime=true),\\\n'
            '/subsystem=transactions:read-resource(include-runtime=true)"',
            "HOME=/tmp と user.home=/tmp でヒストリファイル書き込みを /tmp に誘導。JAVA_TOOL_OPTIONS=\"\" で OTel エージェント等の二重起動を遮断。ポートオフセットがある場合は 9990 + PORT_OFFSET。"
        ],
        [
            2, "JVM ヒープ・GC", "jstat によるヒープ世代別使用量(KB)・GC回数・Stop-The-World累計停止時間(秒)",
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" \\\n'
            'jstat -J-Djava.io.tmpdir=/tmp -gc $(jps -l | grep jboss-modules | awk \'{print $1}\')',
            "-J-Djava.io.tmpdir=/tmp を指定し、readonlyRootFilesystem でも hsperfdata 共有メモリを参照可能にする。"
        ],
        [
            3, "JVM GC原因", "jstat によるヒープ使用率(%)および直前・現在のGC発生原因(LGCC/GCC)",
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" \\\n'
            'jstat -J-Djava.io.tmpdir=/tmp -gccause $(jps -l | grep jboss-modules | awk \'{print $1}\')',
            "LGCC (Last GC Cause) で System.gc() や G1 Evacuation Pause、Metadata Threshold を即座に判別。"
        ],
        [
            4, "JVM クラス/JIT", "jstat によるロード済クラス総数および JIT コンパイル済メソッド数",
            'PID=$(jps -l | grep jboss-modules | awk \'{print $1}\')\n'
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jstat -J-Djava.io.tmpdir=/tmp -class ${PID}\n'
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jstat -J-Djava.io.tmpdir=/tmp -compiler ${PID}',
            "オーバーヘッドほぼゼロ。ウォームアップ完了判定や動的クラスリーク検知に利用。"
        ],
        [
            5, "JVM G1GC詳細", "jcmd による G1GC リージョン内訳 (Eden/Survivor/Old/Humongous)",
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" \\\n'
            'jcmd -J-Djava.io.tmpdir=/tmp $(jps -l | grep jboss-modules | awk \'{print $1}\') GC.heap_info',
            "JBoss 起動時に -XX:+StartAttachListener が必須 (未設定だと readonlyRootFilesystem 下でアタッチ失敗)。"
        ],
        [
            6, "JVM JITコード領域", "jcmd による JIT CodeCache 使用量・最大予約容量 (KB)",
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" \\\n'
            'jcmd -J-Djava.io.tmpdir=/tmp $(jps -l | grep jboss-modules | awk \'{print $1}\') Compiler.codecache',
            "used=...K と max_used=...K を awk で合算して CodeCache 枯渇を監視。"
        ],
        [
            7, "JVM ネイティブメモリ", "jcmd によるヒープ外メモリ内訳追跡 (NMT: Native Memory Tracking)",
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" \\\n'
            'jcmd -J-Djava.io.tmpdir=/tmp $(jps -l | grep jboss-modules | awk \'{print $1}\') VM.native_memory summary',
            "JBoss 起動オプションに -XX:NativeMemoryTracking=summary が必要。DirectBuffer やスレッドスタックの消費を監視し OOM Killer を防止。"
        ],
        [
            8, "JFR ダンプ & サマリ", "jcmd による JFR スナップショットダンプおよび CLI ツール jfr によるイベントサマリ抽出",
            'PID=$(jps -l | grep jboss-modules | awk \'{print $1}\')\n'
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jcmd -J-Djava.io.tmpdir=/tmp ${PID} JFR.dump name=perf-continuous filename=/mnt/logs/02_flight_recording.jfr\n'
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" jfr summary /mnt/logs/02_flight_recording.jfr | head -n 45',
            "UBI 9.8 + Red Hat build of OpenJDK 21 標準機能。ライセンス費用ゼロで本番/試験ともに完全利用可能。"
        ],
        [
            9, "高負荷スレッド特定", "ps -L によるスレッド別 CPU 使用率・待機関数 (wchan) 降順ソート",
            'LC_ALL=C ps -L -p $(jps -l | grep jboss-modules | awk \'{print $1}\') \\\n'
            '  -o pid,lwp,psr,pcpu,pmem,stat,wchan:24,time,comm --no-headers --sort=-pcpu | head -n 25',
            "LC_ALL=C で高速化。wchan:24 でカーネル待機シンボル (futex_wait, ep_poll 等) を確実に表示。"
        ],
        [
            10, "リアルタイムスレッド", "top -H による 1 ショットスレッド CPU スナップショット",
            'LC_ALL=C top -H -b -n 1 -p $(jps -l | grep jboss-modules | awk \'{print $1}\') | head -n 35',
            "バッチモード (-b) かつ 1 回更新 (-n 1) でスクリプトやログ保存に安全に利用可能。"
        ],
        [
            11, "FD 使用数と上限", "/proc によるファイルディスクリプタオープン数とソフトリミット上限",
            'PID=$(jps -l | grep jboss-modules | awk \'{print $1}\')\n'
            'OPEN_FDS=$(ls -1 /proc/${PID}/fd 2>/dev/null | wc -l)\n'
            'MAX_FDS=$(awk \'/Max open files/ {print $4}\' /proc/${PID}/limits)\n'
            'echo "Open FDs: ${OPEN_FDS} / ${MAX_FDS} ($(( OPEN_FDS * 100 / MAX_FDS ))%)"',
            "Too many open files エラーの事前検知。"
        ],
        [
            12, "強制CPU剥奪回数", "/proc/<pid>/status による非自発的コンテキストスイッチ数とスラッシング検知",
            'PID=$(jps -l | grep jboss-modules | awk \'{print $1}\')\n'
            'awk \'/^nonvoluntary_ctxt_switches:/ {print $2}\' /proc/${PID}/status',
            "10秒前の値との差分 (Delta) が急増している場合、スレッド過多による CPU の奪い合いが発生している証拠。"
        ],
        [
            13, "TCP ソケット状態内訳", "/proc/net/tcp による ESTABLISHED, CLOSE_WAIT, TIME_WAIT, SYN_RECV 数集計",
            'awk \'\n'
            '  BEGIN { est=0; cw=0; tw=0; sr=0; }\n'
            '  $1 ~ /^[0-9]+:/ { st=$4; if(st=="01")est++; else if(st=="08")cw++; else if(st=="06")tw++; else if(st=="03")sr++; }\n'
            '  END { printf "ESTABLISHED=%d CLOSE_WAIT=%d TIME_WAIT=%d SYN_RECV=%d\\n", est, cw, tw, sr; }\n'
            '\' /proc/net/tcp /proc/net/tcp6',
            "netstat コマンド不要で /proc からダイレクト集計。CLOSE_WAIT>0 はアプリ側のソケットクローズ漏れ。"
        ],
        [
            14, "Listen キュー溢れ", "/proc/net/netstat によるカーネル ListenDrops 破棄パケット数抽出",
            'awk \'/^TcpExt:/ {if(h==0){for(i=1;i<=NF;i++)if($i=="ListenDrops")c=i; h=1}else if(c>0)print $c+0}\' /proc/net/netstat | tail -n 1',
            "1 以上ならソケット backlog キュー溢れによる接続拒否が発生中。"
        ],
        [
            15, "cgroup v2 CPU制限", "cgroup v2 による CPU クォータ (quota) / 周期 (period) の確認",
            'cat /sys/fs/cgroup/cpu.max\n'
            '# 出力例: 75000 100000 -> 0.75 vCPU相当 (無制限時は max 100000)',
            "UBI 9.8 / ECS Fargate の cgroup v2 制限値。"
        ],
        [
            16, "CFS スロットリング率", "cgroup v2 cpu.stat によるスロットリング発生回数・停止ミリ秒の取得",
            'awk \'\n'
            '  /^nr_periods/   { p=$2 }\n'
            '  /^nr_throttled/ { t=$2 }\n'
            '  /^throttled_usec/ { u=$2 }\n'
            '  END { printf "Periods=%d Throttled=%d Rate=%.2f%% ThrottledTime=%.2fms\\n", p, t, (p>0)?(t*100.0/p):0, u/1000.0 }\n'
            '\' /sys/fs/cgroup/cpu.stat',
            "CFS スロットリング率 5% 以上で要チューニング判定。"
        ],
        [
            17, "ECS メタデータ取得", "ECS Task Metadata Endpoint v4 からタスクCPU・コンテナCPU・コンテナ数を取得",
            'curl -fsS ${ECS_CONTAINER_METADATA_URI_V4}/task | sed -n \'s/.*"Limits"[^}]*"CPU":\\([0-9.]*\\).*/\\1/p\'\n'
            'curl -fsS ${ECS_CONTAINER_METADATA_URI_V4} | sed -n \'s/.*"Limits"[^}]*"CPU":\\([0-9.]*\\).*/\\1/p\'',
            "ECS タスク内でのマルチコンテナ構成を自動検出。"
        ],
        [
            18, "JVM 認識コア数確認", "jcmd VM.flags -all による JVM 認識プロセッサ数と派生スレッド数の確認",
            'JAVA_TOOL_OPTIONS="" JDK_JAVA_OPTIONS="" \\\n'
            'jcmd -J-Djava.io.tmpdir=/tmp $(jps -l | grep jboss-modules | awk \'{print $1}\') VM.flags -all | \\\n'
            'grep -E \'ActiveProcessorCount|ParallelGCThreads|ConcGCThreads|CICompilerCount\'',
            "JVM が cgroup を見て何コアと認識し、GC/JIT スレッドを何本生成したかを確認。"
        ],
        [
            19, "XML 統計属性事前有効化", "standalone.xml の datasources / undertow / transactions 統計属性を一括置換",
            'sed -i \\\n'
            '  -e \'s/statistics-enabled="false"/statistics-enabled="true"/g\' \\\n'
            '  -e \'s/<subsystem xmlns="urn:jboss:domain:undertow:\\([^"]*\\)"\\([^>]*\\)>/<subsystem xmlns="urn:jboss:domain:undertow:\\1"\\2 statistics-enabled="true">/g\' \\\n'
            '  ${JBOSS_HOME}/standalone/configuration/standalone.xml',
            "JBoss EAP 8.1 起動前に実行。これが false のままだと jboss-cli のカウンタがすべて 0 になる。"
        ],
        [
            20, "JVM 必須フラグ注入", "readonlyRootFilesystem 下での JFR / jstat / jcmd / NMT 必須起動オプション",
            'JAVA_OPTS="${JAVA_OPTS} -XX:-PerfDisableSharedMem -XX:+StartAttachListener -Djava.io.tmpdir=/tmp -XX:NativeMemoryTracking=summary -XX:FlightRecorderOptions=repository=/tmp/jfr-repo -XX:StartFlightRecording=name=perf-continuous,settings=profile,disk=true,maxage=1h,maxsize=250M,dumponexit=true,filename=/mnt/logs/02_flight_recording.jfr"',
            "JBoss EAP 起動スクリプト (standalone.sh) 実行前の JAVA_OPTS に追記。"
        ]
    ]
    format_table(ws6, 5, s6_headers, s6_data, [6, 24, 38, 62, 50], code_cols=[3])

    # Remove default sheet
    if default_sheet in wb.worksheets:
        wb.remove(default_sheet)

    # Save workbook
    wb.save(output_path)
    print(f"Successfully generated Excel reference workbook at: {output_path}")

if __name__ == "__main__":
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    out_file = "JMeter性能試験_コンテナメトリクス出力項目・実装コマンド一覧.xlsx"
    if len(sys.argv) > 1:
        out_file = sys.argv[1]
    create_metrics_excel(out_file)
