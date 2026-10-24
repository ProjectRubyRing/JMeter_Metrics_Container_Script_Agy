#Requires -Version 5.1
<#
.SYNOPSIS
    JMeter Performance Test Container Metrics (1: jboss-cli, 2: jstat/jcmd/JFR, 3: top/ps, 4: ActiveProcessorCount)
    to Monotone Excel (.xlsx) Report Generator for Windows 11 PowerShell
    Font: Meiryo UI / Color Theme: Monotone (Charcoal / Slate / Gray / White)

.DESCRIPTION
    Reads the metrics files output under /mnt/logs/<front|back>/logs/<Service_Name>/mid/current:
      (1) 01_jboss_cli_stats.tsv      / 01_jboss_cli_raw.log
      (2) 02_jvm_heap_gc_stats.tsv    / 02_jcmd_jfr_detail.log / 02_flight_recording.jfr
      (3) 03_process_thread_stats.tsv / 03_top_ps_detail.log
      (4) 04_active_processor_diag.tsv / 04_active_processor_report.txt
    Extracts the container role (front/back) and service name (intra-web/intra-api/inter-api/sf-api)
    from the log file path (e.g., /mnt/logs/front/logs/intra-web/mid/current) or file metadata headers:
      - front -> フロントコンテナ, back -> バックコンテナ
      - intra-web -> intra-webサービス, intra-api -> intra-apiサービス,
        inter-api -> inter-apiサービス, sf-api -> sf-apiサービス
    Includes these Japanese container/service names in the output Excel report filename and
    generates a beautifully formatted monotone Excel (.xlsx) report using standard .NET libraries only.

.PARAMETER InputPath
    One or more directories (e.g. /mnt/logs/front/logs/intra-web/mid/current) or metrics files (.tsv, .log, .txt).

.PARAMETER OutputPath
    Destination directory or Excel (.xlsx) file path. Automatically includes the container and service labels in the filename.

.EXAMPLE
    .\Convert-PerfMetricsToExcel.ps1 -InputPath .\mnt\logs\front\logs\intra-web\mid\current
    .\Convert-PerfMetricsToExcel.ps1 -InputPath .\mnt\logs\back\logs\intra-api\mid\current -OutputPath .\reports
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromPipeline = $true)]
    [Alias("i", "LogPath", "Path")]
    [string[]]$InputPath = @(),

    [Parameter(Position = 1)]
    [Alias("o", "OutFile", "OutputDirectory", "OutDir")]
    [string]$OutputPath = "",

    [Parameter()]
    [Alias("h")]
    [switch]$Help
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function U {
        param([string]$EscapedText)
        return [System.Text.RegularExpressions.Regex]::Unescape($EscapedText)
    }

    function Show-Usage {
        Write-Host "Usage:"
        Write-Host "  .\Convert-PerfMetricsToExcel.ps1 [-InputPath] <dir_or_files...> [[-OutputPath] <dir_or_xlsx>]"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  .\Convert-PerfMetricsToExcel.ps1 -InputPath .\mnt\logs\front\logs\intra-web\mid\current"
        Write-Host "  .\Convert-PerfMetricsToExcel.ps1 -InputPath .\mnt\logs\back\logs\sf-api\mid\current -OutputPath .\reports"
    }

    $CollectedInputs = New-Object System.Collections.Generic.List[string]
}

process {
    if ($null -ne $InputPath) {
        foreach ($p in $InputPath) {
            if (-not [string]::IsNullOrWhiteSpace($p)) {
                $CollectedInputs.Add($p)
            }
        }
    }
}

end {
    if ($Help.IsPresent) {
        Show-Usage
        exit 0
    }

    if ($CollectedInputs.Count -eq 0 -and $null -ne $InputPath) {
        foreach ($p in $InputPath) {
            if (-not [string]::IsNullOrWhiteSpace($p)) {
                $CollectedInputs.Add($p)
            }
        }
    }

    if ($CollectedInputs.Count -eq 0) {
        $defaultSearch = Join-Path -Path (Get-Location).Path -ChildPath "mnt\logs"
        if (Test-Path -LiteralPath $defaultSearch) {
            $CollectedInputs.Add($defaultSearch)
        }
        else {
            $CollectedInputs.Add((Get-Location).Path)
        }
    }

    # Resolve all metrics files (.tsv, .log, .txt, .jfr)
    $ResolvedFiles = New-Object System.Collections.Generic.List[string]
    foreach ($rawItem in $CollectedInputs) {
        if (Test-Path -LiteralPath $rawItem -PathType Container) {
            $dirFiles = Get-ChildItem -LiteralPath $rawItem -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -match '^(0[1-4]_|perf_)' -or
                    $_.Extension -in @(".tsv", ".jfr")
                } |
                Sort-Object FullName
            foreach ($df in $dirFiles) {
                if (-not $ResolvedFiles.Contains($df.FullName)) {
                    $ResolvedFiles.Add($df.FullName)
                }
            }
        }
        elseif (Test-Path -LiteralPath $rawItem -PathType Leaf) {
            $fullP = (Resolve-Path -LiteralPath $rawItem).Path
            if (-not $ResolvedFiles.Contains($fullP)) {
                $ResolvedFiles.Add($fullP)
            }
        }
        else {
            Write-Warning "Path not found: $rawItem"
        }
    }

    if ($ResolvedFiles.Count -eq 0) {
        Write-Error (U "[ERROR] \u8aad\u307f\u8fbc\u307f\u5bfe\u8c61\u306e\u6027\u80fd\u8a66\u9a13\u30e1\u30c8\u30ea\u30af\u30b9\u30d5\u30a1\u30a4\u30eb (01_jboss_cli_stats.tsv \u7b49) \u304c\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3002")
        exit 1
    }

    # ==========================================================================
    # 1. Container Role (front/back) & Service Name Mapping
    # ==========================================================================
    $LblFrontCnt = U "\u30d5\u30ed\u30f3\u30c8\u30b3\u30f3\u30c6\u30ca"   # フロントコンテナ
    $LblBackCnt  = U "\u30d0\u30c3\u30af\u30b3\u30f3\u30c6\u30ca"       # バックコンテナ
    $LblSvcSuffix = U "\u30b5\u30fc\u30d3\u30b9"                        # サービス

    function ConvertTo-ContainerLabel {
        param([string]$RawRole)
        if ([string]::IsNullOrWhiteSpace($RawRole)) { return "" }
        $r = $RawRole.Trim().ToLowerInvariant()
        if ($r -eq "front" -or $r.EndsWith("-front") -or $r.Contains("front")) {
            return $LblFrontCnt
        }
        if ($r -eq "back" -or $r.EndsWith("-back") -or $r.Contains("back")) {
            return $LblBackCnt
        }
        return ""
    }

    function ConvertTo-CanonicalRole {
        param([string]$RawRole)
        if ([string]::IsNullOrWhiteSpace($RawRole)) { return "" }
        $r = $RawRole.Trim().ToLowerInvariant()
        if ($r -eq "front" -or $r.EndsWith("-front") -or $r.Contains("front")) { return "front" }
        if ($r -eq "back" -or $r.EndsWith("-back") -or $r.Contains("back")) { return "back" }
        return ""
    }

    function ConvertTo-CanonicalService {
        param([string]$RawSvc)
        if ([string]::IsNullOrWhiteSpace($RawSvc)) { return "" }
        $s = $RawSvc.Trim().ToLowerInvariant()
        switch -Regex ($s) {
            '^intra-?web$' { return "intra-web" }
            '^intra-?api$' { return "intra-api" }
            '^inter-?api$' { return "inter-api" }
            '^sf-?api$'    { return "sf-api" }
        }
        return ""
    }

    function ConvertTo-ServiceLabel {
        param([string]$RawSvc)
        $canon = ConvertTo-CanonicalService -RawSvc $RawSvc
        if (-not [string]::IsNullOrEmpty($canon)) {
            return "${canon}${LblSvcSuffix}"
        }
        return ""
    }

    function Extract-PathMetadata {
        param([string]$PathText)
        $res = @{ Role = ""; Service = ""; LogicalDir = "" }
        if ([string]::IsNullOrWhiteSpace($PathText)) { return $res }
        $norm = $PathText.Replace("\", "/")

        # Pattern 1: /mnt/logs/<front|back>/logs/<intra-web|intra-api|inter-api|sf-api>/mid/...
        $m = [regex]::Match($norm, '(?i)/mnt/logs/([^/]+)/logs/([^/]+)/mid/(current|[^/]+)')
        if ($m.Success) {
            $r = ConvertTo-CanonicalRole -RawRole $m.Groups[1].Value
            $s = ConvertTo-CanonicalService -RawSvc $m.Groups[2].Value
            if ($r) { $res.Role = $r }
            if ($s) { $res.Service = $s }
            $res.LogicalDir = "/mnt/logs/$($m.Groups[1].Value)/logs/$($m.Groups[2].Value)/mid/$($m.Groups[3].Value)"
            return $res
        }

        # Pattern 2: /<front|back>/logs/<service>/ anywhere in path
        $m2 = [regex]::Match($norm, '(?i)/(front|back|[^/]*-front|[^/]*-back)/logs/(intra-?web|intra-?api|inter-?api|sf-?api)(/|$)')
        if ($m2.Success) {
            $res.Role = ConvertTo-CanonicalRole -RawRole $m2.Groups[1].Value
            $res.Service = ConvertTo-CanonicalService -RawSvc $m2.Groups[2].Value
            $res.LogicalDir = "/mnt/logs/$($res.Role)/logs/$($res.Service)/mid/current"
            return $res
        }

        # Pattern 3: Segment scan
        $parts = $norm -split '/'
        foreach ($seg in $parts) {
            if (-not $res.Role) {
                $cr = ConvertTo-CanonicalRole -RawRole $seg
                if ($cr -and ($seg -match '^(?i)(front|back|.*-front|.*-back)$')) { $res.Role = $cr }
            }
            if (-not $res.Service) {
                $cs = ConvertTo-CanonicalService -RawSvc $seg
                if ($cs) { $res.Service = $cs }
            }
        }
        return $res
    }

    # ==========================================================================
    # 2. File Reading & Parsing Helpers
    # ==========================================================================
    $ReCtrlChars = [regex]::new("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", [System.Text.RegularExpressions.RegexOptions]::Compiled)

    function Read-LinesAutoEncoding {
        param([string]$FilePath)
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($FilePath)
        if ($bytes.Length -eq 0) { return @() }
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
            return $text -split "\r?\n|\r"
        }
        try {
            $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
            $text = $utf8Strict.GetString($bytes)
            return $text -split "\r?\n|\r"
        }
        catch {
            $cp932 = [System.Text.Encoding]::GetEncoding(932)
            $text = $cp932.GetString($bytes)
            return $text -split "\r?\n|\r"
        }
    }

    $DetectedRoles    = New-Object System.Collections.Generic.List[string]
    $DetectedServices = New-Object System.Collections.Generic.List[string]
    $DetectedLogDirs  = New-Object System.Collections.Generic.List[string]
    $DetectedRealDirs = New-Object System.Collections.Generic.List[string]
    $DetectedIntervals = New-Object System.Collections.Generic.List[string]
    $JfrFilesInfo     = New-Object System.Collections.Generic.List[string]

    function Register-TargetMeta {
        param([string]$Role, [string]$Service, [string]$LogDir = "", [string]$RealDir = "", [string]$Interval = "")
        $cr = ConvertTo-CanonicalRole -RawRole $Role
        if ($cr -and (-not $DetectedRoles.Contains($cr))) { $DetectedRoles.Add($cr) }
        $cs = ConvertTo-CanonicalService -RawSvc $Service
        if ($cs -and (-not $DetectedServices.Contains($cs))) { $DetectedServices.Add($cs) }
        if ($LogDir -and (-not $DetectedLogDirs.Contains($LogDir))) { $DetectedLogDirs.Add($LogDir) }
        if ($RealDir -and (-not $DetectedRealDirs.Contains($RealDir))) { $DetectedRealDirs.Add($RealDir) }
        if ($Interval -and (-not $DetectedIntervals.Contains($Interval))) { $DetectedIntervals.Add($Interval) }
    }

    # Check InputPath arguments first for path metadata
    foreach ($inArg in $CollectedInputs) {
        $pm = Extract-PathMetadata -PathText $inArg
        Register-TargetMeta -Role $pm.Role -Service $pm.Service -LogDir $pm.LogicalDir
    }

    # Data structures for the 4 categories + raw logs
    $Tables = @{
        "01_cli"  = @{ Headers = @(); Rows = New-Object System.Collections.Generic.List[object] }
        "02_jvm"  = @{ Headers = @(); Rows = New-Object System.Collections.Generic.List[object] }
        "03_proc" = @{ Headers = @(); Rows = New-Object System.Collections.Generic.List[object] }
        "04_cpu"  = @{ Headers = @(); Rows = New-Object System.Collections.Generic.List[object] }
    }
    $RawLogLines = New-Object System.Collections.Generic.List[object]

    foreach ($fp in $ResolvedFiles) {
        $fName = [System.IO.Path]::GetFileName($fp)
        $pm = Extract-PathMetadata -PathText $fp
        Register-TargetMeta -Role $pm.Role -Service $pm.Service -LogDir $pm.LogicalDir

        if ($fName.EndsWith(".jfr")) {
            $fInfo = Get-Item -LiteralPath $fp
            $kb = [Math]::Round($fInfo.Length / 1024.0, 1)
            $JfrFilesInfo.Add("$fName (${kb} KB)")
            continue
        }

        $lines = Read-LinesAutoEncoding -FilePath $fp
        $tableKey = ""
        if ($fName -match '^01_.*\.tsv$' -or $fName -match 'jboss_cli.*\.tsv$') { $tableKey = "01_cli" }
        elseif ($fName -match '^02_.*\.tsv$' -or $fName -match 'jvm_heap.*\.tsv$') { $tableKey = "02_jvm" }
        elseif ($fName -match '^03_.*\.tsv$' -or $fName -match 'process_thread.*\.tsv$') { $tableKey = "03_proc" }
        elseif ($fName -match '^04_.*\.tsv$' -or $fName -match 'active_processor.*\.tsv$') { $tableKey = "04_cpu" }

        $headerParsed = $false
        foreach ($rawLine in $lines) {
            if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
            $trimmed = $rawLine.Trim()

            # Metadata comment lines (# KEY: VALUE)
            if ($trimmed.StartsWith("#")) {
                if ($trimmed -match '^#\s*METRICS_LOG_PATH:\s*(.+)$') {
                    $logP = $Matches[1].Trim()
                    $pmMeta = Extract-PathMetadata -PathText $logP
                    $logDir = [System.IO.Path]::GetDirectoryName($logP).Replace("\", "/")
                    Register-TargetMeta -Role $pmMeta.Role -Service $pmMeta.Service -LogDir $logDir
                }
                elseif ($trimmed -match '^#\s*METRICS_REAL_PATH:\s*(.+)$') {
                    $realP = $Matches[1].Trim()
                    $realDir = [System.IO.Path]::GetDirectoryName($realP).Replace("\", "/")
                    Register-TargetMeta -Role "" -Service "" -RealDir $realDir
                }
                elseif ($trimmed -match '^#\s*(CONTAINER_ROLE|COMPONENT_NAME):\s*(.+)$') {
                    Register-TargetMeta -Role $Matches[2].Trim() -Service ""
                }
                elseif ($trimmed -match '^#\s*SERVICE_NAME:\s*(.+)$') {
                    Register-TargetMeta -Role "" -Service $Matches[1].Trim()
                }
                elseif ($trimmed -match '^#\s*INTERVAL_SECONDS:\s*(.+)$') {
                    Register-TargetMeta -Role "" -Service "" -Interval ($Matches[1].Trim() + "s")
                }
                continue
            }

            if ($tableKey -ne "") {
                $cols = @($rawLine -split "`t")
                if (-not $headerParsed -and $cols[0] -eq "Timestamp_JST") {
                    if ($Tables[$tableKey].Headers.Count -eq 0) {
                        $Tables[$tableKey].Headers = $cols
                    }
                    $headerParsed = $true
                    continue
                }
                if ($cols.Count -ge 4) {
                    Register-TargetMeta -Role $cols[1] -Service $cols[2]
                    $evalSt = $cols[$cols.Count - 1].Trim()
                    if ($tableKey -eq "04_cpu" -and $cols.Count -ge 30) {
                        $evalSt = $cols[29].Trim()
                    }
                    $Tables[$tableKey].Rows.Add([PSCustomObject]@{
                        Cols     = [string[]]$cols
                        Status   = $evalSt
                    })
                }
            }
            else {
                # Raw log / report file (.log / .txt)
                if ($trimmed -match '^===\s*' -or $trimmed -match '^---\s*\[' -or $trimmed -match '^\[20\d\d-') {
                    $lvl = "SECTION"
                }
                elseif ($trimmed -match 'CRITICAL|REQUIRED_|ERROR|FATAL|TimedOut=[1-9]') {
                    $lvl = "CRITICAL"
                }
                elseif ($trimmed -match 'WARN|RECOMMENDED_') {
                    $lvl = "WARN"
                }
                else {
                    $lvl = "INFO"
                }
                $RawLogLines.Add([PSCustomObject]@{
                    SourceFile = $fName
                    Level      = $lvl
                    Text       = $rawLine
                })
            }
        }
    }

    # Ensure defaults if path/content didn't specify
    if ($DetectedRoles.Count -eq 0) { $DetectedRoles.Add("front") }
    if ($DetectedServices.Count -eq 0) { $DetectedServices.Add("intra-web") }

    $ContainerLabels = @($DetectedRoles | ForEach-Object { ConvertTo-ContainerLabel -RawRole $_ } | Where-Object { $_ -ne "" })
    $ServiceLabels   = @($DetectedServices | ForEach-Object { ConvertTo-ServiceLabel -RawSvc $_ } | Where-Object { $_ -ne "" })

    $ContainerFileTag = ($ContainerLabels -join "-")
    $ServiceFileTag   = ($ServiceLabels -join "-")
    $TsFileTag        = (Get-Date).ToString("yyyyMMdd_HHmmss")

    # Determine final OutputPath with mandatory container & service labels in filename
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $fileName = "JMeter_PerfMetrics_Report_${ContainerFileTag}_${ServiceFileTag}_${TsFileTag}.xlsx"
        $OutputPath = Join-Path -Path (Get-Location).Path -ChildPath $fileName
    }
    else {
        if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
            $OutputPath = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $OutputPath))
        }
        if ((Test-Path -LiteralPath $OutputPath -PathType Container) -or (-not $OutputPath.EndsWith(".xlsx", [System.StringComparison]::OrdinalIgnoreCase))) {
            $fileName = "JMeter_PerfMetrics_Report_${ContainerFileTag}_${ServiceFileTag}_${TsFileTag}.xlsx"
            $OutputPath = Join-Path -Path $OutputPath -ChildPath $fileName
        }
        else {
            $dirPart  = [System.IO.Path]::GetDirectoryName($OutputPath)
            $basePart = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
            $extPart  = [System.IO.Path]::GetExtension($OutputPath)
            if (-not $basePart.Contains($ContainerFileTag)) {
                $basePart = "${basePart}_${ContainerFileTag}"
            }
            if (-not $basePart.Contains($ServiceFileTag)) {
                $basePart = "${basePart}_${ServiceFileTag}"
            }
            $OutputPath = Join-Path -Path $dirPart -ChildPath "${basePart}${extPart}"
        }
    }

    # ==========================================================================
    # 3. OpenXML Shared Strings & Monotone Style System (Meiryo UI)
    # ==========================================================================
    $SstStrings = New-Object System.Collections.Generic.List[string]
    $SstMap = New-Object 'System.Collections.Generic.Dictionary[string,int]'
    $script:SstTotalRefs = 0

    function Get-SharedStringIndex {
        param([AllowNull()][string]$Text)
        $script:SstTotalRefs++
        $s = if ($null -eq $Text) { "" } else { $Text }
        $s = $ReCtrlChars.Replace($s, "")
        if ($s.Length -gt 32760) {
            $s = $s.Substring(0, 32757) + "..."
        }
        $idx = 0
        if (-not $SstMap.TryGetValue($s, [ref]$idx)) {
            $idx = $SstStrings.Count
            $SstStrings.Add($s)
            $SstMap[$s] = $idx
        }
        return $idx
    }

    function Get-ColumnLetter {
        param([int]$ColIndex1Based)
        $res = ""
        [int]$n = $ColIndex1Based
        while ($n -gt 0) {
            [int]$rem = ($n - 1) % 26
            $res = [char][int](65 + $rem) + $res
            $n = [int][Math]::Floor(($n - 1) / 26)
        }
        return $res
    }

    function Get-DisplayWidth {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text)) { return 0 }
        $w = 0
        foreach ($ch in $Text.ToCharArray()) {
            if ([int]$ch -gt 0x7F) { $w += 2 } else { $w += 1 }
        }
        return $w
    }

    function Escape-XmlText {
        param([string]$Text)
        if ($null -eq $Text) { return "" }
        $cleaned = $ReCtrlChars.Replace($Text, "")
        if ($cleaned.Length -gt 32760) {
            $cleaned = $cleaned.Substring(0, 32757) + "..."
        }
        return [System.Security.SecurityElement]::Escape($cleaned)
    }

    function New-StrCell {
        param([string]$Ref, [int]$StyleId, [AllowNull()][string]$Text)
        $idx = Get-SharedStringIndex -Text $Text
        return "<c r=`"$Ref`" s=`"$StyleId`" t=`"s`"><v>$idx</v></c>"
    }

    function New-NumCell {
        param([string]$Ref, [int]$StyleId, $Value)
        $vStr = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0}", $Value)
        return "<c r=`"$Ref`" s=`"$StyleId`"><v>$vStr</v></c>"
    }

    # Style Indices (Monotone Palette)
    $ST_TITLE_BANNER = 1
    $ST_SUBTITLE_BAR = 2
    $ST_META_BAR     = 3
    $ST_SECTION_HDR  = 4
    $ST_TBL_HDR_C    = 5
    $ST_TBL_HDR_L    = 6
    $ST_TBL_HDR_R    = 7
    $ST_EVEN_C       = 8
    $ST_EVEN_L       = 9
    $ST_EVEN_R       = 10
    $ST_ODD_C        = 11
    $ST_ODD_L        = 12
    $ST_ODD_R        = 13
    $ST_WARN_C       = 14
    $ST_WARN_L       = 15
    $ST_WARN_R       = 16
    $ST_WARN_BADGE   = 17
    $ST_CRIT_C       = 18
    $ST_CRIT_L       = 19
    $ST_CRIT_R       = 20
    $ST_CRIT_BADGE   = 21
    $ST_OK_BADGE     = 22
    $ST_KV_KEY       = 23
    $ST_KV_VAL       = 24

    function Build-StylesXml {
        $fonts = @(
            '<font><sz val="9.5"/><color rgb="FF1A1A1A"/><name val="Meiryo UI"/><family val="2"/><charset val="128"/></font>',
            '<font><b/><sz val="13"/><color rgb="FFFFFFFF"/><name val="Meiryo UI"/><family val="2"/><charset val="128"/></font>',
            '<font><sz val="9.5"/><color rgb="FFEAEAEA"/><name val="Meiryo UI"/><family val="2"/><charset val="128"/></font>',
            '<font><b/><sz val="9.5"/><color rgb="FF1A1A1A"/><name val="Meiryo UI"/><family val="2"/><charset val="128"/></font>',
            '<font><b/><sz val="11"/><color rgb="FF1A1A1A"/><name val="Meiryo UI"/><family val="2"/><charset val="128"/></font>',
            '<font><b/><sz val="9.5"/><color rgb="FFFFFFFF"/><name val="Meiryo UI"/><family val="2"/><charset val="128"/></font>',
            '<font><b/><sz val="9.5"/><color rgb="FF000000"/><name val="Meiryo UI"/><family val="2"/><charset val="128"/></font>',
            '<font><b/><sz val="9.5"/><color rgb="FF262626"/><name val="Meiryo UI"/><family val="2"/><charset val="128"/></font>'
        )

        $fills = @(
            '<fill><patternFill patternType="none"/></fill>',
            '<fill><patternFill patternType="gray125"/></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FF1A1A1A"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FF2D2D2D"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FFD9D9D9"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FFF0F0F0"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FF333333"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FFFFFFFF"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FFF7F7F7"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FFE8E8E8"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FF595959"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FFD0D0D0"/><bgColor indexed="64"/></patternFill></fill>',
            '<fill><patternFill patternType="solid"><fgColor rgb="FFE2E2E2"/><bgColor indexed="64"/></patternFill></fill>'
        )

        $borders = @(
            '<border><left/><right/><top/><bottom/><diagonal/></border>',
            '<border><left style="thin"><color rgb="FF595959"/></left><right style="thin"><color rgb="FF595959"/></right><top style="medium"><color rgb="FF1A1A1A"/></top><bottom style="medium"><color rgb="FF000000"/></bottom><diagonal/></border>',
            '<border><left style="thin"><color rgb="FFD0D0D0"/></left><right style="thin"><color rgb="FFD0D0D0"/></right><top style="thin"><color rgb="FFBFBFBF"/></top><bottom style="thin"><color rgb="FFBFBFBF"/></bottom><diagonal/></border>',
            '<border><left style="thin"><color rgb="FF808080"/></left><right style="thin"><color rgb="FF808080"/></right><top style="thin"><color rgb="FF808080"/></top><bottom style="thin"><color rgb="FF808080"/></bottom><diagonal/></border>',
            '<border><left/><right/><top/><bottom style="medium"><color rgb="FF262626"/></bottom><diagonal/></border>'
        )

        function New-Xf([int]$nf, [int]$fn, [int]$fl, [int]$bd, [string]$ha, [int]$wrap = 0, [int]$ind = 0) {
            $indAttr = if ($ind -gt 0) { " indent=`"$ind`"" } else { "" }
            return "<xf numFmtId=`"$nf`" fontId=`"$fn`" fillId=`"$fl`" borderId=`"$bd`" xfId=`"0`" applyNumberFormat=`"1`" applyFont=`"1`" applyFill=`"1`" applyBorder=`"1`" applyAlignment=`"1`"><alignment horizontal=`"$ha`" vertical=`"center`" wrapText=`"$wrap`"$indAttr/></xf>"
        }

        $cellXfs = @(
            (New-Xf 49 0 0 0 "left"),          # 0: Default
            (New-Xf 49 1 2 3 "left" 0 1),      # 1: ST_TITLE_BANNER
            (New-Xf 49 2 3 3 "left" 0 1),      # 2: ST_SUBTITLE_BAR
            (New-Xf 49 3 4 3 "left" 0 1),      # 3: ST_META_BAR
            (New-Xf 49 4 5 4 "left" 0 0),      # 4: ST_SECTION_HDR
            (New-Xf 49 5 6 1 "center" 1),      # 5: ST_TBL_HDR_C
            (New-Xf 49 5 6 1 "left" 1),        # 6: ST_TBL_HDR_L
            (New-Xf 49 5 6 1 "right" 1),       # 7: ST_TBL_HDR_R
            (New-Xf 49 0 7 2 "center"),        # 8: ST_EVEN_C
            (New-Xf 49 0 7 2 "left"),          # 9: ST_EVEN_L
            (New-Xf 49 0 7 2 "right"),         # 10: ST_EVEN_R
            (New-Xf 49 0 8 2 "center"),        # 11: ST_ODD_C
            (New-Xf 49 0 8 2 "left"),          # 12: ST_ODD_L
            (New-Xf 49 0 8 2 "right"),         # 13: ST_ODD_R
            (New-Xf 49 7 9 2 "center"),        # 14: ST_WARN_C
            (New-Xf 49 7 9 2 "left"),          # 15: ST_WARN_L
            (New-Xf 49 7 9 2 "right"),         # 16: ST_WARN_R
            (New-Xf 49 5 10 2 "center"),       # 17: ST_WARN_BADGE
            (New-Xf 49 6 11 2 "center"),       # 18: ST_CRIT_C
            (New-Xf 49 6 11 2 "left"),         # 19: ST_CRIT_L
            (New-Xf 49 6 11 2 "right"),        # 20: ST_CRIT_R
            (New-Xf 49 5 2 2 "center"),        # 21: ST_CRIT_BADGE
            (New-Xf 49 3 12 2 "center"),       # 22: ST_OK_BADGE
            (New-Xf 49 3 5 2 "left"),          # 23: ST_KV_KEY
            (New-Xf 49 0 7 2 "left")           # 24: ST_KV_VAL
        )

        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
            "<fonts count=`"$($fonts.Count)`">$($fonts -join '')</fonts>" +
            "<fills count=`"$($fills.Count)`">$($fills -join '')</fills>" +
            "<borders count=`"$($borders.Count)`">$($borders -join '')</borders>" +
            '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"><alignment vertical="center"/></xf></cellStyleXfs>' +
            "<cellXfs count=`"$($cellXfs.Count)`">$($cellXfs -join '')</cellXfs>" +
            '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>' +
            '<dxfs count="0"/>' +
            '<tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>' +
            '</styleSheet>'
        )
    }

    function Classify-StatusSeverity {
        param([string]$StatusText)
        if ([string]::IsNullOrWhiteSpace($StatusText)) { return "NORMAL" }
        $s = $StatusText.Trim().ToUpperInvariant()
        if ($s -match 'CRITICAL|ERROR|REQUIRED_') { return "CRITICAL" }
        if ($s -match 'WARN|RECOMMENDED_') { return "WARN" }
        return "NORMAL"
    }

    function Test-IsNumericValue {
        param([string]$Val)
        if ([string]::IsNullOrWhiteSpace($Val)) { return $false }
        $d = 0.0
        return [double]::TryParse($Val.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)
    }

    # ==========================================================================
    # 4. Build Generic Time-Series Worksheet XML (For Sheets 1, 2, 3, 4)
    # ==========================================================================
    function Build-MetricsTableSheetXml {
        param(
            [string]$TitleText,
            [string]$SubTitleText,
            [string[]]$Headers,
            $Rows,
            [int]$TabSelected = 0
        )

        $numCols = [Math]::Max(1, $Headers.Count)
        $lastColLet = Get-ColumnLetter -ColIndex1Based $numCols

        $colWidths = New-Object int[] $numCols
        for ($i = 0; $i -lt $numCols; $i++) {
            $w = [Math]::Max(13, (Get-DisplayWidth -Text $Headers[$i]) + 5)
            $colWidths[$i] = [Math]::Min(65, $w)
        }

        $critCnt = 0; $warnCnt = 0; $normCnt = 0
        foreach ($rObj in $Rows) {
            $sev = Classify-StatusSeverity -StatusText $rObj.Status
            if ($sev -eq "CRITICAL") { $critCnt++ }
            elseif ($sev -eq "WARN") { $warnCnt++ }
            else { $normCnt++ }

            $cols = $rObj.Cols
            $lim = [Math]::Min($numCols, $cols.Count)
            for ($i = 0; $i -lt $lim; $i++) {
                $cw = (Get-DisplayWidth -Text $cols[$i]) + 4
                if ($cw -gt $colWidths[$i]) {
                    $colWidths[$i] = [Math]::Min(90, $cw)
                }
            }
        }

        $logPathDisp = if ($DetectedLogDirs.Count -gt 0) { $DetectedLogDirs -join ", " } else { "/mnt/logs/$($DetectedRoles[0])/logs/$($DetectedServices[0])/mid/current" }
        $intDisp     = if ($DetectedIntervals.Count -gt 0) { $DetectedIntervals -join "/" } else { "10s" }
        $metaLine = (U "\u5bfe\u8c61\u30b3\u30f3\u30c6\u30ca: ") + $ContainerFileTag +
                    (U "   |   \u5bfe\u8c61\u30b5\u30fc\u30d3\u30b9: ") + $ServiceFileTag +
                    (U "   |   \u51fa\u529b\u9818\u57df: ") + $logPathDisp +
                    (U "   |   \u8a08\u6e2c\u9593\u9694: ") + $intDisp +
                    (U "   |   \u30b5\u30f3\u30d7\u30eb\u6570: ") + "$($Rows.Count) (NORMAL=$normCnt / WARN=$warnCnt / CRITICAL=$critCnt)"

        $sbRows = New-Object System.Text.StringBuilder
        $merges = New-Object System.Collections.Generic.List[string]

        # Row 1: Title Banner
        [void]$sbRows.Append('<row r="1" ht="28" customHeight="1">')
        [void]$sbRows.Append((New-StrCell -Ref "A1" -StyleId $ST_TITLE_BANNER -Text $TitleText))
        for ($c = 2; $c -le $numCols; $c++) {
            [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)1" -StyleId $ST_TITLE_BANNER -Text ""))
        }
        [void]$sbRows.Append('</row>')
        $merges.Add("A1:${lastColLet}1")

        # Row 2: Subtitle Bar
        [void]$sbRows.Append('<row r="2" ht="20" customHeight="1">')
        [void]$sbRows.Append((New-StrCell -Ref "A2" -StyleId $ST_SUBTITLE_BAR -Text $SubTitleText))
        for ($c = 2; $c -le $numCols; $c++) {
            [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)2" -StyleId $ST_SUBTITLE_BAR -Text ""))
        }
        [void]$sbRows.Append('</row>')
        $merges.Add("A2:${lastColLet}2")

        # Row 3: Meta Bar
        [void]$sbRows.Append('<row r="3" ht="20" customHeight="1">')
        [void]$sbRows.Append((New-StrCell -Ref "A3" -StyleId $ST_META_BAR -Text $metaLine))
        for ($c = 2; $c -le $numCols; $c++) {
            [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)3" -StyleId $ST_META_BAR -Text ""))
        }
        [void]$sbRows.Append('</row>')
        $merges.Add("A3:${lastColLet}3")

        # Row 4: Spacer
        [void]$sbRows.Append('<row r="4" ht="8" customHeight="1"/>')

        # Row 5: Table Headers
        [void]$sbRows.Append('<row r="5" ht="26" customHeight="1">')
        for ($c = 1; $c -le $numCols; $c++) {
            [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)5" -StyleId $ST_TBL_HDR_C -Text $Headers[$c - 1]))
        }
        [void]$sbRows.Append('</row>')

        # Rows 6+: Data Rows
        $curRow = 6
        if ($Rows.Count -eq 0) {
            [void]$sbRows.Append('<row r="6" ht="20" customHeight="1">')
            for ($c = 1; $c -le $numCols; $c++) {
                [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)6" -StyleId $ST_EVEN_C -Text "-"))
            }
            [void]$sbRows.Append('</row>')
        }
        else {
            for ($rIdx = 0; $rIdx -lt $Rows.Count; $rIdx++) {
                $curRow = 6 + $rIdx
                $rObj = $Rows[$rIdx]
                $cols = $rObj.Cols
                $sev  = Classify-StatusSeverity -StatusText $rObj.Status
                $even = (($rIdx % 2) -eq 0)

                if ($sev -eq "CRITICAL") {
                    $stC = $ST_CRIT_C; $stL = $ST_CRIT_L; $stR = $ST_CRIT_R; $stBadge = $ST_CRIT_BADGE
                }
                elseif ($sev -eq "WARN") {
                    $stC = $ST_WARN_C; $stL = $ST_WARN_L; $stR = $ST_WARN_R; $stBadge = $ST_WARN_BADGE
                }
                else {
                    if ($even) { $stC = $ST_EVEN_C; $stL = $ST_EVEN_L; $stR = $ST_EVEN_R }
                    else       { $stC = $ST_ODD_C;  $stL = $ST_ODD_L;  $stR = $ST_ODD_R  }
                    $stBadge = $ST_OK_BADGE
                }

                [void]$sbRows.Append("<row r=`"$curRow`" ht=`"20`" customHeight=`"1`">")
                for ($c = 1; $c -le $numCols; $c++) {
                    $val = if (($c - 1) -lt $cols.Count) { $cols[$c - 1] } else { "" }
                    $hName = $Headers[$c - 1]
                    $ref = "$(Get-ColumnLetter $c)$curRow"

                    if ($hName -in @("Status_Eval", "Necessity_Judgment")) {
                        [void]$sbRows.Append((New-StrCell -Ref $ref -StyleId $stBadge -Text $val))
                    }
                    elseif ($hName -eq "Diagnosis_Reason") {
                        [void]$sbRows.Append((New-StrCell -Ref $ref -StyleId $stL -Text $val))
                    }
                    elseif ($c -ge 4 -and (Test-IsNumericValue -Val $val)) {
                        [void]$sbRows.Append((New-StrCell -Ref $ref -StyleId $stR -Text $val))
                    }
                    else {
                        [void]$sbRows.Append((New-StrCell -Ref $ref -StyleId $stC -Text $val))
                    }
                }
                [void]$sbRows.Append('</row>')
            }
        }

        $sbCols = New-Object System.Text.StringBuilder
        [void]$sbCols.Append('<cols>')
        for ($c = 1; $c -le $numCols; $c++) {
            [void]$sbCols.Append("<col min=`"$c`" max=`"$c`" width=`"$($colWidths[$c - 1])`" customWidth=`"1`"/>")
        }
        [void]$sbCols.Append('</cols>')

        $mergeXml = "<mergeCells count=`"$($merges.Count)`">" + (($merges | ForEach-Object { "<mergeCell ref=`"$_`"/>" }) -join "") + "</mergeCells>"

        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
            '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>' +
            "<dimension ref=`"A1:${lastColLet}${curRow}`"/>" +
            "<sheetViews><sheetView tabSelected=`"$TabSelected`" showGridLines=`"1`" workbookViewId=`"0`">" +
            '<pane ySplit="5" topLeftCell="A6" activePane="bottomLeft" state="frozen"/>' +
            '<selection pane="bottomLeft" activeCell="A6" sqref="A6"/>' +
            '</sheetView></sheetViews>' +
            '<sheetFormatPr defaultRowHeight="20" customHeight="1"/>' +
            $sbCols.ToString() +
            "<sheetData>$($sbRows.ToString())</sheetData>" +
            "<autoFilter ref=`"A5:${lastColLet}${curRow}`"/>" +
            $mergeXml +
            '<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.2" footer="0.2"/>' +
            '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>' +
            '</worksheet>'
        )
    }

    # ==========================================================================
    # 5. Build Executive Summary Sheet XML (Sheet 0: サマリー)
    # ==========================================================================
    function Build-SummarySheetXml {
        $numCols = 8
        $lastColLet = Get-ColumnLetter -ColIndex1Based $numCols
        $sbRows = New-Object System.Text.StringBuilder
        $merges = New-Object System.Collections.Generic.List[string]

        $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $logPathDisp = if ($DetectedLogDirs.Count -gt 0) { $DetectedLogDirs -join ", " } else { "/mnt/logs/$($DetectedRoles[0])/logs/$($DetectedServices[0])/mid/current" }
        $realPathDisp = if ($DetectedRealDirs.Count -gt 0) { $DetectedRealDirs -join ", " } else { $logPathDisp }
        $intDisp = if ($DetectedIntervals.Count -gt 0) { $DetectedIntervals -join ", " } else { "10s" }

        $titleBanner = (U "JMeter \u6027\u80fd\u8a66\u9a13 \u30b3\u30f3\u30c6\u30ca\u30e1\u30c8\u30ea\u30af\u30b9\u7d71\u5408\u89e3\u6790\u30ec\u30dd\u30fc\u30c8 [") + "${ContainerFileTag} / ${ServiceFileTag}]"
        $subBanner   = (U "ECS Fargate (readonlyRootFilesystem=true) | Red Hat UBI 9.8 | OpenJDK 21 Red Hat build | JBoss EAP 8.1 | Generated: ") + "$nowStr (JST)"

        # Row 1: Title
        [void]$sbRows.Append('<row r="1" ht="30" customHeight="1">')
        [void]$sbRows.Append((New-StrCell -Ref "A1" -StyleId $ST_TITLE_BANNER -Text $titleBanner))
        for ($c = 2; $c -le $numCols; $c++) { [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)1" -StyleId $ST_TITLE_BANNER -Text "")) }
        [void]$sbRows.Append('</row>')
        $merges.Add("A1:${lastColLet}1")

        # Row 2: Subtitle
        [void]$sbRows.Append('<row r="2" ht="20" customHeight="1">')
        [void]$sbRows.Append((New-StrCell -Ref "A2" -StyleId $ST_SUBTITLE_BAR -Text $subBanner))
        for ($c = 2; $c -le $numCols; $c++) { [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)2" -StyleId $ST_SUBTITLE_BAR -Text "")) }
        [void]$sbRows.Append('</row>')
        $merges.Add("A2:${lastColLet}2")

        # Row 3: Spacer
        [void]$sbRows.Append('<row r="3" ht="8" customHeight="1"/>')

        # Section 1: Target Metadata Overview
        $curR = 4
        $sec1Hdr = U "\u25a0 1. \u8a08\u6e2c\u5bfe\u8c61\u30b3\u30f3\u30c6\u30ca\u30fb\u30b5\u30fc\u30d3\u30b9\u30fbEFS\u51fa\u529b\u30d1\u30b9\u60c5\u5831 (Target Container & EFS Storage Path)"
        [void]$sbRows.Append("<row r=`"$curR`" ht=`"24`" customHeight=`"1`">")
        [void]$sbRows.Append((New-StrCell -Ref "A$curR" -StyleId $ST_SECTION_HDR -Text $sec1Hdr))
        for ($c = 2; $c -le $numCols; $c++) { [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)$curR" -StyleId $ST_SECTION_HDR -Text "")) }
        [void]$sbRows.Append('</row>')
        $merges.Add("A${curR}:${lastColLet}${curR}")
        $curR++

        $metaPairs = @(
            @((U "\u5bfe\u8c61\u30b3\u30f3\u30c6\u30ca\u533a\u5206 (front / back)"), "$ContainerFileTag ($($DetectedRoles -join ', '))", (U "\u5bfe\u8c61ECS\u30b5\u30fc\u30d3\u30b9\u540d"), "$ServiceFileTag ($($DetectedServices -join ', '))"),
            @((U "\u8ad6\u7406\u30ed\u30b0\u51fa\u529b\u30d1\u30b9 (mid/current)"), $logPathDisp, (U "\u5b9f\u4f53\u66f8\u304d\u8fbc\u307f\u30d1\u30b9 (pin\u5b9f\u4f53)"), $realPathDisp),
            @((U "\u8a08\u6e2c\u9593\u9694 (PERF_METRICS_INTERVAL)"), $intDisp, (U "JFR\u8a18\u9332\u30d5\u30a1\u30a4\u30eb"), $(if ($JfrFilesInfo.Count -gt 0) { $JfrFilesInfo -join ", " } else { "02_flight_recording.jfr (Active)" }))
        )
        foreach ($mp in $metaPairs) {
            [void]$sbRows.Append("<row r=`"$curR`" ht=`"21`" customHeight=`"1`">")
            [void]$sbRows.Append((New-StrCell -Ref "A$curR" -StyleId $ST_KV_KEY -Text $mp[0]))
            [void]$sbRows.Append((New-StrCell -Ref "B$curR" -StyleId $ST_KV_VAL -Text $mp[1]))
            [void]$sbRows.Append((New-StrCell -Ref "C$curR" -StyleId $ST_KV_VAL -Text ""))
            [void]$sbRows.Append((New-StrCell -Ref "D$curR" -StyleId $ST_KV_VAL -Text ""))
            [void]$sbRows.Append((New-StrCell -Ref "E$curR" -StyleId $ST_KV_KEY -Text $mp[2]))
            [void]$sbRows.Append((New-StrCell -Ref "F$curR" -StyleId $ST_KV_VAL -Text $mp[3]))
            [void]$sbRows.Append((New-StrCell -Ref "G$curR" -StyleId $ST_KV_VAL -Text ""))
            [void]$sbRows.Append((New-StrCell -Ref "H$curR" -StyleId $ST_KV_VAL -Text ""))
            [void]$sbRows.Append('</row>')
            $merges.Add("B${curR}:D${curR}")
            $merges.Add("F${curR}:H${curR}")
            $curR++
        }

        [void]$sbRows.Append("<row r=`"$curR`" ht=`"10`" customHeight=`"1`"/>")
        $curR++

        # Section 2: 4 Categories Summary Table
        $sec2Hdr = U "\u25a0 2. \u6027\u80fd\u8a66\u9a13 4\u5927\u30e1\u30c8\u30ea\u30af\u30b9\u53ce\u96c6\u30fb\u5224\u5b9a\u30b5\u30de\u30ea\u30fc (\u203bContainer Insights\u62e1\u5f35\u3067\u78ba\u8a8d\u53ef\u80fd\u306a\u9805\u76ee\u306f\u9664\u5916\u6e08)"
        [void]$sbRows.Append("<row r=`"$curR`" ht=`"24`" customHeight=`"1`">")
        [void]$sbRows.Append((New-StrCell -Ref "A$curR" -StyleId $ST_SECTION_HDR -Text $sec2Hdr))
        for ($c = 2; $c -le $numCols; $c++) { [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)$curR" -StyleId $ST_SECTION_HDR -Text "")) }
        [void]$sbRows.Append('</row>')
        $merges.Add("A${curR}:${lastColLet}${curR}")
        $curR++

        $s2Cols = @(
            (U "\u9805\u76eeNo."),
            (U "\u30e1\u30c8\u30ea\u30af\u30b9\u5206\u985e (\u30b7\u30fc\u30c8\u540d)"),
            (U "\u4e3b\u306a\u53d6\u5f97\u30b3\u30de\u30f3\u30c9\u30fb\u6280\u8853"),
            (U "\u30b5\u30f3\u30d7\u30eb\u6570"),
            (U "NORMAL"),
            (U "WARN"),
            (U "CRITICAL"),
            (U "\u7dcf\u5408\u5224\u5b9a / \u4e3b\u8981\u89b3\u6e2c\u5024")
        )
        [void]$sbRows.Append("<row r=`"$curR`" ht=`"25`" customHeight=`"1`">")
        for ($c = 1; $c -le $numCols; $c++) {
            [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)$curR" -StyleId $ST_TBL_HDR_C -Text $s2Cols[$c - 1]))
        }
        [void]$sbRows.Append('</row>')
        $curR++

        $catDefs = @(
            @{ Key = "01_cli";  No = (U "\u2460"); Name = (U "1_DB\u63a5\u7d9a\u30d7\u30fc\u30eb_JBossCLI"); Cmd = "jboss-cli.sh (Datasources / Undertow / Worker / JTA)" },
            @{ Key = "02_jvm";  No = (U "\u2461"); Name = (U "2_\u30d2\u30fc\u30d7_GC_JFR");        Cmd = "jstat (-gc/-gccause) / jcmd (NMT/CodeCache) / JFR" },
            @{ Key = "03_proc"; No = (U "\u2462"); Name = (U "3_top_ps_\u30d7\u30ed\u30bb\u30b9\u72b6\u6cc1"); Cmd = "top -H / ps -L / /proc (FD / ContextSwitch / TCP)" },
            @{ Key = "04_cpu";  No = (U "\u2463"); Name = (U "4_ActiveProcessorCount\u8981\u5426"); Cmd = "cgroup v2 cpu.max & cpu.stat / jcmd VM.flags" }
        )

        for ($idx = 0; $idx -lt $catDefs.Count; $idx++) {
            $cd = $catDefs[$idx]
            $tRows = $Tables[$cd.Key].Rows
            $nCnt = 0; $wCnt = 0; $cCnt = 0
            foreach ($r in $tRows) {
                $sv = Classify-StatusSeverity -StatusText $r.Status
                if ($sv -eq "CRITICAL") { $cCnt++ }
                elseif ($sv -eq "WARN") { $wCnt++ }
                else { $nCnt++ }
            }
            $even = (($idx % 2) -eq 0)
            $stC = if ($even) { $ST_EVEN_C } else { $ST_ODD_C }
            $stL = if ($even) { $ST_EVEN_L } else { $ST_ODD_L }
            $stR = if ($even) { $ST_EVEN_R } else { $ST_ODD_R }

            if ($cCnt -gt 0) { $verdict = "CRITICAL ($cCnt)"; $stB = $ST_CRIT_BADGE }
            elseif ($wCnt -gt 0) { $verdict = "WARN ($wCnt)"; $stB = $ST_WARN_BADGE }
            else { $verdict = "NORMAL (OK)"; $stB = $ST_OK_BADGE }

            [void]$sbRows.Append("<row r=`"$curR`" ht=`"21`" customHeight=`"1`">")
            [void]$sbRows.Append((New-StrCell -Ref "A$curR" -StyleId $stC -Text $cd.No))
            [void]$sbRows.Append((New-StrCell -Ref "B$curR" -StyleId $stL -Text $cd.Name))
            [void]$sbRows.Append((New-StrCell -Ref "C$curR" -StyleId $stL -Text $cd.Cmd))
            [void]$sbRows.Append((New-NumCell -Ref "D$curR" -StyleId $stR -Value $tRows.Count))
            [void]$sbRows.Append((New-NumCell -Ref "E$curR" -StyleId $stR -Value $nCnt))
            [void]$sbRows.Append((New-NumCell -Ref "F$curR" -StyleId $stR -Value $wCnt))
            [void]$sbRows.Append((New-NumCell -Ref "G$curR" -StyleId $stR -Value $cCnt))
            [void]$sbRows.Append((New-StrCell -Ref "H$curR" -StyleId $stB -Text $verdict))
            [void]$sbRows.Append('</row>')
            $curR++
        }

        [void]$sbRows.Append("<row r=`"$curR`" ht=`"10`" customHeight=`"1`"/>")
        $curR++

        # Section 3: ActiveProcessorCount Final Diagnosis Box
        $sec3Hdr = U "\u25a0 3. \u2463 -XX:ActiveProcessorCount \u8a2d\u5b9a\u8981\u5426 \u81ea\u52d5\u8a3a\u65ad\u7d50\u679c (\u6700\u65b0\u30b5\u30f3\u30d7\u30eb\u5224\u5b9a)"
        [void]$sbRows.Append("<row r=`"$curR`" ht=`"24`" customHeight=`"1`">")
        [void]$sbRows.Append((New-StrCell -Ref "A$curR" -StyleId $ST_SECTION_HDR -Text $sec3Hdr))
        for ($c = 2; $c -le $numCols; $c++) { [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)$curR" -StyleId $ST_SECTION_HDR -Text "")) }
        [void]$sbRows.Append('</row>')
        $merges.Add("A${curR}:${lastColLet}${curR}")
        $curR++

        $cpuRows = $Tables["04_cpu"].Rows
        if ($cpuRows.Count -gt 0) {
            $lastCpu = $cpuRows[$cpuRows.Count - 1].Cols
            $hostC  = if ($lastCpu.Count -gt 3)  { $lastCpu[3] }  else { "-" }
            $taskU  = if ($lastCpu.Count -gt 4)  { $lastCpu[4] }  else { "-" }
            $cntU   = if ($lastCpu.Count -gt 5)  { $lastCpu[5] }  else { "-" }
            $cntN   = if ($lastCpu.Count -gt 6)  { $lastCpu[6] }  else { "-" }
            $effV   = if ($lastCpu.Count -gt 10) { $lastCpu[10] } else { "-" }
            $expFlg = if ($lastCpu.Count -gt 12) { $lastCpu[12] } else { "-" }
            $jvmP   = if ($lastCpu.Count -gt 13) { $lastCpu[13] } else { "-" }
            $thRate = if ($lastCpu.Count -gt 24) { $lastCpu[24] + "%" } else { "-" }
            $recApc = if ($lastCpu.Count -gt 28) { "-XX:ActiveProcessorCount=" + $lastCpu[28] } else { "-" }
            $judg   = if ($lastCpu.Count -gt 29) { $lastCpu[29] } else { "-" }
            $reason = if ($lastCpu.Count -gt 30) { $lastCpu[30] } else { "-" }

            $diagPairs = @(
                @((U "\u30db\u30b9\u30c8\u7269\u7406CPU / \u540c\u5c45\u30b3\u30f3\u30c6\u30ca\u6570"), "${hostC} cores / ${cntN} containers", (U "ECS\u30bf\u30b9\u30afCPU / \u30b3\u30f3\u30c6\u30caCPU"), "${taskU} units / ${cntU} units (Effective: ${effV} vCPU)"),
                @((U "\u73fe\u884cActiveProcessorCount\u6307\u5b9a"), $expFlg, (U "JVM\u8a8d\u8b58\u30b3\u30a2\u6570 / CFS\u30b9\u30ed\u30c3\u30c8\u30ea\u30f3\u30b0\u7387"), "${jvmP} cores / ThrottleRate=${thRate}"),
                @((U "\u63a8\u5968 JVM \u30aa\u30d7\u30b7\u30e7\u30f3\u8a2d\u5b9a\u5024"), $recApc, (U "\u8a2d\u5b9a\u8981\u5426 \u5224\u5b9a\u7d50\u679c"), $judg)
            )
            foreach ($dp in $diagPairs) {
                [void]$sbRows.Append("<row r=`"$curR`" ht=`"21`" customHeight=`"1`">")
                [void]$sbRows.Append((New-StrCell -Ref "A$curR" -StyleId $ST_KV_KEY -Text $dp[0]))
                [void]$sbRows.Append((New-StrCell -Ref "B$curR" -StyleId $ST_KV_VAL -Text $dp[1]))
                [void]$sbRows.Append((New-StrCell -Ref "C$curR" -StyleId $ST_KV_VAL -Text ""))
                [void]$sbRows.Append((New-StrCell -Ref "D$curR" -StyleId $ST_KV_VAL -Text ""))
                [void]$sbRows.Append((New-StrCell -Ref "E$curR" -StyleId $ST_KV_KEY -Text $dp[2]))
                [void]$sbRows.Append((New-StrCell -Ref "F$curR" -StyleId $ST_KV_VAL -Text $dp[3]))
                [void]$sbRows.Append((New-StrCell -Ref "G$curR" -StyleId $ST_KV_VAL -Text ""))
                [void]$sbRows.Append((New-StrCell -Ref "H$curR" -StyleId $ST_KV_VAL -Text ""))
                [void]$sbRows.Append('</row>')
                $merges.Add("B${curR}:D${curR}")
                $merges.Add("F${curR}:H${curR}")
                $curR++
            }

            # Reason row
            [void]$sbRows.Append("<row r=`"$curR`" ht=`"24`" customHeight=`"1`">")
            [void]$sbRows.Append((New-StrCell -Ref "A$curR" -StyleId $ST_KV_KEY -Text (U "\u8981\u5426\u5224\u5b9a\u306e\u6839\u62e0\u30fb\u8a3a\u65ad\u7406\u7531")))
            [void]$sbRows.Append((New-StrCell -Ref "B$curR" -StyleId $ST_KV_VAL -Text $reason))
            for ($c = 3; $c -le $numCols; $c++) { [void]$sbRows.Append((New-StrCell -Ref "$(Get-ColumnLetter $c)$curR" -StyleId $ST_KV_VAL -Text "")) }
            [void]$sbRows.Append('</row>')
            $merges.Add("B${curR}:H${curR}")
            $curR++
        }

        $colWidths = @(30, 32, 42, 16, 14, 14, 14, 34)
        $colsXml = "<cols>" + ((1..$numCols | ForEach-Object { "<col min=`"$_`" max=`"$_`" width=`"$($colWidths[$_ - 1])`" customWidth=`"1`"/>" }) -join "") + "</cols>"
        $mergeXml = "<mergeCells count=`"$($merges.Count)`">" + (($merges | ForEach-Object { "<mergeCell ref=`"$_`"/>" }) -join "") + "</mergeCells>"

        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
            '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>' +
            "<dimension ref=`"A1:${lastColLet}$($curR - 1)`"/>" +
            '<sheetViews><sheetView tabSelected="1" showGridLines="1" workbookViewId="0"/></sheetViews>' +
            '<sheetFormatPr defaultRowHeight="20" customHeight="1"/>' +
            $colsXml +
            "<sheetData>$($sbRows.ToString())</sheetData>" +
            $mergeXml +
            '<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.2" footer="0.2"/>' +
            '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>' +
            '</worksheet>'
        )
    }

    # ==========================================================================
    # 6. Build Raw Detail Log Sheet XML (Sheet 5: 5_詳細ログ_jcmd_JFR_top)
    # ==========================================================================
    function Build-RawLogSheetXml {
        $headers = @(
            (U "No."),
            (U "\u51fa\u529b\u5143\u30d5\u30a1\u30a4\u30eb (Source File)"),
            (U "\u533a\u5206 (Category)"),
            (U "\u8a73\u7d30\u30ed\u30b0\u5185\u5bb9 (jcmd GC.heap_info / VM.native_memory / JFR summary / top -H / ps -L / ActiveProcessorCount Report)")
        )
        $rowsList = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $RawLogLines.Count; $i++) {
            $item = $RawLogLines[$i]
            $st = if ($item.Level -eq "CRITICAL") { "CRITICAL" } elseif ($item.Level -eq "WARN") { "WARN" } else { "NORMAL" }
            $rowsList.Add([PSCustomObject]@{
                Cols   = [string[]]@([string]($i + 1), $item.SourceFile, $item.Level, $item.Text)
                Status = $st
            })
        }
        return Build-MetricsTableSheetXml `
            -TitleText (U "5. \u8a73\u7d30\u8a3a\u65ad\u30ed\u30b0 (jboss-cli DMR / jcmd NMT & Heap / JFR Summary / top -H & ps -L / ActiveProcessorCount Report)") `
            -SubTitleText (U "Container Insights \u62e1\u5f35\u3067\u306f\u4e0d\u53ef\u8996\u306a JVM \u5185\u90e8\u69cb\u9020\u30fbJFR\u30a4\u30d9\u30f3\u30c8\u96c6\u8a08\u30fb\u30b9\u30ec\u30c3\u30c9\u5225\u7a3c\u50cd\u30b9\u30ca\u30c3\u30d7\u30b7\u30e7\u30c3\u30c8") `
            -Headers $headers `
            -Rows $rowsList `
            -TabSelected 0
    }

    function Build-SharedStringsXml {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$sb.Append("<sst xmlns=`"http://schemas.openxmlformats.org/spreadsheetml/2006/main`" count=`"$script:SstTotalRefs`" uniqueCount=`"$($SstStrings.Count)`">")
        foreach ($s in $SstStrings) {
            $esc = Escape-XmlText -Text $s
            if ($s.StartsWith(" ") -or $s.EndsWith(" ") -or $s.Contains("`n") -or $s.Contains("`t") -or $s.Contains("  ")) {
                [void]$sb.Append("<si><t xml:space=`"preserve`">$esc</t></si>")
            }
            else {
                [void]$sb.Append("<si><t>$esc</t></si>")
            }
        }
        [void]$sb.Append('</sst>')
        return $sb.ToString()
    }

    # ==========================================================================
    # 7. Assemble All Worksheets & Package OpenXML (.xlsx)
    # ==========================================================================
    $defaultHeaders01 = @("Timestamp_JST","Container","Service","Task_LogID","Datasource_Name","DS_Type","MaxPoolSize","ActiveCount","InUseCount","AvailableCount","PoolUsage_Pct","MaxUsedCount","WaitCount","MaxWaitTime_ms","TimedOut","TotalBlockingTime_ms","AvgCreationTime_ms","DestroyedCount","PrepStmtCache_HitCnt","PrepStmtCache_MissCnt","Undertow_ReqCount","Undertow_ErrCount","Undertow_MaxProcTime_ms","Undertow_ProcTime_ms","Worker_BusyThreads","Worker_MaxThreads","Worker_QueueSize","Worker_Rejected","JTA_TotalTx","JTA_CommittedTx","JTA_AbortedTx","JTA_TimedOutTx","JTA_InFlightTx","JTA_Heuristics","Status_Eval")
    $defaultHeaders02 = @("Timestamp_JST","Container","Service","PID","S0_Pct","S1_Pct","Eden_Pct","Old_Pct","Metaspace_Pct","CCS_Pct","Eden_Used_KB","Eden_Cap_KB","Survivor_Used_KB","Old_Used_KB","Old_Cap_KB","Metaspace_Used_KB","Metaspace_Cap_KB","YGC_Count","Delta_YGC","YGCT_s","FGC_Count","Delta_FGC","FGCT_s","CGC_Count","CGCT_s","GCT_Total_s","Delta_GCT_ms","Last_GC_Cause","Curr_GC_Cause","Classes_Loaded","JIT_Compiled","CodeCache_Used_KB","CodeCache_Max_KB","NMT_Total_Committed_KB","JFR_State","JFR_Size_KB","Status_Eval")
    $defaultHeaders03 = @("Timestamp_JST","Container","Service","PID","JVM_Threads_Total","Threads_Running_R","Threads_DiskSleep_D","Threads_Sleeping_S","Threads_Zombie_Z","Top1_Thread_TID","Top1_Thread_Name","Top1_Thread_CPU_Pct","Top1_Thread_State","Top1_Thread_WCHAN","Top2_Thread_Name","Top2_Thread_CPU_Pct","Open_FDs","Max_FDs_Limit","FD_Usage_Pct","Min_PageFaults","Maj_PageFaults","Voluntary_CtxtSw","NonVoluntary_CtxtSw","Delta_NonVol_CtxtSw","TCP_Established","TCP_CloseWait","TCP_TimeWait","TCP_SynRecv","TCP_ListenDrops","Status_Eval")
    $defaultHeaders04 = @("Timestamp_JST","Container","Service","Host_Physical_CPUs","ECS_Task_CPU_Units","ECS_Container_CPU_Units","Task_Container_Count","Cgroup_Version","Cgroup_Quota_us","Cgroup_Period_us","Cgroup_Effective_vCPU","Cgroup_Weight_Shares","Explicit_ActiveProcessorCount_Flag","JVM_Recognized_Processors","ParallelGCThreads","ConcGCThreads","CICompilerCount","ForkJoin_Parallelism","Undertow_IO_Threads","Undertow_Worker_Threads","CFS_nr_periods","CFS_nr_throttled","Delta_Periods","Delta_Throttled","Throttle_Rate_Pct","CFS_throttled_ms","Delta_Throttled_ms","LoadAvg_1m","Recommended_ActiveProcessorCount","Necessity_Judgment","Diagnosis_Reason")

    $h01 = if ($Tables["01_cli"].Headers.Count -gt 0)  { $Tables["01_cli"].Headers }  else { $defaultHeaders01 }
    $h02 = if ($Tables["02_jvm"].Headers.Count -gt 0)  { $Tables["02_jvm"].Headers }  else { $defaultHeaders02 }
    $h03 = if ($Tables["03_proc"].Headers.Count -gt 0) { $Tables["03_proc"].Headers } else { $defaultHeaders03 }
    $h04 = if ($Tables["04_cpu"].Headers.Count -gt 0)  { $Tables["04_cpu"].Headers }  else { $defaultHeaders04 }

    $SheetsInfo = New-Object System.Collections.Generic.List[object]
    $SheetsInfo.Add([PSCustomObject]@{
        Name = (U "\u30b5\u30de\u30ea\u30fc")
        Xml  = (Build-SummarySheetXml)
    })
    $SheetsInfo.Add([PSCustomObject]@{
        Name = (U "1_DB\u63a5\u7d9a\u30d7\u30fc\u30eb_JBossCLI")
        Xml  = (Build-MetricsTableSheetXml `
            -TitleText (U "\u2460 JBoss EAP 8.1 jboss-cli DB\u63a5\u7d9a\u30d7\u30fc\u30eb\u30fbUndertow\u30fbWorker\u30fbJTA\u30c8\u30e9\u30f3\u30b6\u30af\u30b7\u30e7\u30f3\u7d71\u8a08") `
            -SubTitleText (U "Container Insights \u62e1\u5f35\u3067\u306f\u53d6\u5f97\u4e0d\u53ef\u80fd\u306a AP\u30b5\u30fc\u30d0\u30fc\u5185\u90e8\u30d7\u30fc\u30eb\u67af\u6e07\u30fb\u5f85\u3061\u884c\u5217\u30fb2PC\u30c8\u30e9\u30f3\u30b6\u30af\u30b7\u30e7\u30f3\u72b6\u614b") `
            -Headers $h01 -Rows $Tables["01_cli"].Rows)
    })
    $SheetsInfo.Add([PSCustomObject]@{
        Name = (U "2_\u30d2\u30fc\u30d7_GC_JFR")
        Xml  = (Build-MetricsTableSheetXml `
            -TitleText (U "\u2461 OpenJDK 21 (Red Hat build) jstat / jcmd / JFR \u30d2\u30fc\u30d7\u4e16\u4ee3\u5225\u30fbGC\u30fb\u30cd\u30a4\u30c6\u30a3\u30d6\u30e1\u30e2\u30ea\u7d71\u8a08") `
            -SubTitleText (U "Eden / Survivor / Old / Metaspace / CodeCache / NMT / YGC & FGC \u505c\u6b62\u6642\u9593\u30fbGC\u539f\u56e0\u30fbJFR (Java Flight Recorder) \u7a3c\u50cd\u7d71\u8a08") `
            -Headers $h02 -Rows $Tables["02_jvm"].Rows)
    })
    $SheetsInfo.Add([PSCustomObject]@{
        Name = (U "3_top_ps_\u30d7\u30ed\u30bb\u30b9\u72b6\u6cc1")
        Xml  = (Build-MetricsTableSheetXml `
            -TitleText (U "\u2462 UBI 9.8 top (-H) / ps (-L) / procfs \u30b9\u30ec\u30c3\u30c9\u72b6\u614b\u30fbFD\u67af\u6e07\u7387\u30fbTCP\u30bd\u30b1\u30c3\u30c8\u7d71\u8a08") `
            -SubTitleText (U "\u30b9\u30ec\u30c3\u30c9\u72b6\u614b\u5185\u8a33 (R/D/S/Z)\u30fb\u9ad8\u8ca0\u8377\u30b9\u30ec\u30c3\u30c9\u7279\u5b9a\u30fb\u30ab\u30fc\u30cd\u30eb\u5f85\u6a5f\u95a2\u6570(wchan)\u30fbFD\u4e0a\u9650\u30fb\u5f37\u5236\u30b3\u30f3\u30c6\u30ad\u30b9\u30c8\u30b9\u30a4\u30c3\u30c1\u30fbCLOSE_WAIT") `
            -Headers $h03 -Rows $Tables["03_proc"].Rows)
    })
    $SheetsInfo.Add([PSCustomObject]@{
        Name = (U "4_ActiveProcessorCount\u8981\u5426")
        Xml  = (Build-MetricsTableSheetXml `
            -TitleText (U "\u2463 -XX:ActiveProcessorCount \u8a2d\u5b9a\u8981\u5426\u5224\u65ad\u30fbCFS CPU\u30b9\u30ed\u30c3\u30c8\u30ea\u30f3\u30b0\u8a3a\u65ad\u7d71\u8a08") `
            -SubTitleText (U "Host CPU vs ECS Task/Container CPU vs cgroup v2 cpu.max vs JVM availableProcessors() \u304a\u3088\u3073 CFS nr_throttled \u30b9\u30ed\u30c3\u30c8\u30ea\u30f3\u30b0\u7387\u5224\u5b9a") `
            -Headers $h04 -Rows $Tables["04_cpu"].Rows)
    })
    $SheetsInfo.Add([PSCustomObject]@{
        Name = (U "5_\u8a73\u7d30\u30ed\u30b0_jcmd_JFR_top")
        Xml  = (Build-RawLogSheetXml)
    })

    $ctOverrides = New-Object System.Collections.Generic.List[string]
    $ctOverrides.Add('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    $ctOverrides.Add('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
    $ctOverrides.Add('<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>')
    for ($idx = 1; $idx -le $SheetsInfo.Count; $idx++) {
        $ctOverrides.Add("<Override PartName=`"/xl/worksheets/sheet${idx}.xml`" ContentType=`"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml`"/>")
    }
    $contentTypesXml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        ($ctOverrides -join '') +
        '</Types>'
    )

    $rootRelsXml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
        '</Relationships>'
    )

    $wbSheets = New-Object System.Collections.Generic.List[string]
    $wbRels   = New-Object System.Collections.Generic.List[string]
    for ($idx = 1; $idx -le $SheetsInfo.Count; $idx++) {
        $escName = Escape-XmlText -Text $SheetsInfo[$idx - 1].Name
        $wbSheets.Add("<sheet name=`"$escName`" sheetId=`"$idx`" r:id=`"rId$idx`"/>")
        $wbRels.Add("<Relationship Id=`"rId$idx`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet`" Target=`"worksheets/sheet${idx}.xml`"/>")
    }
    $styleRid = $SheetsInfo.Count + 1
    $sstRid   = $SheetsInfo.Count + 2
    $wbRels.Add("<Relationship Id=`"rId$styleRid`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles`" Target=`"styles.xml`"/>")
    $wbRels.Add("<Relationship Id=`"rId$sstRid`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings`" Target=`"sharedStrings.xml`"/>")

    $workbookXml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
        '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="16200"/></bookViews>' +
        "<sheets>$($wbSheets -join '')</sheets>" +
        '</workbook>'
    )

    $workbookRelsXml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        ($wbRels -join '') +
        '</Relationships>'
    )

    $stylesXml = Build-StylesXml
    $sstXml    = Build-SharedStringsXml

    $outDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        [void](New-Item -ItemType Directory -Path $outDir -Force)
    }
    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $fs = New-Object System.IO.FileStream($OutputPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            function Write-ZipEntry {
                param($ZipArchive, [string]$EntryPath, [string]$Content, $Encoding)
                $entry = $ZipArchive.CreateEntry($EntryPath, [System.IO.Compression.CompressionLevel]::Optimal)
                $stream = $entry.Open()
                try {
                    $bytes = $Encoding.GetBytes($Content)
                    $stream.Write($bytes, 0, $bytes.Length)
                }
                finally {
                    $stream.Dispose()
                }
            }

            Write-ZipEntry -ZipArchive $zip -EntryPath "[Content_Types].xml"        -Content $contentTypesXml -Encoding $utf8NoBom
            Write-ZipEntry -ZipArchive $zip -EntryPath "_rels/.rels"                -Content $rootRelsXml    -Encoding $utf8NoBom
            Write-ZipEntry -ZipArchive $zip -EntryPath "xl/workbook.xml"            -Content $workbookXml    -Encoding $utf8NoBom
            Write-ZipEntry -ZipArchive $zip -EntryPath "xl/_rels/workbook.xml.rels" -Content $workbookRelsXml -Encoding $utf8NoBom
            Write-ZipEntry -ZipArchive $zip -EntryPath "xl/styles.xml"              -Content $stylesXml      -Encoding $utf8NoBom
            Write-ZipEntry -ZipArchive $zip -EntryPath "xl/sharedStrings.xml"       -Content $sstXml         -Encoding $utf8NoBom

            for ($idx = 1; $idx -le $SheetsInfo.Count; $idx++) {
                Write-ZipEntry -ZipArchive $zip -EntryPath "xl/worksheets/sheet${idx}.xml" -Content $SheetsInfo[$idx - 1].Xml -Encoding $utf8NoBom
            }
        }
        finally {
            $zip.Dispose()
        }
    }
    finally {
        $fs.Dispose()
    }

    Write-Host "================================================================================"
    Write-Host " JMeter Performance Metrics Monotone Excel Report Generator (Meiryo UI)"
    Write-Host "================================================================================"
    Write-Host " Container Role : $ContainerFileTag ($($DetectedRoles -join ', '))"
    Write-Host " ECS Service    : $ServiceFileTag ($($DetectedServices -join ', '))"
    Write-Host " Output Excel   : $OutputPath"
    Write-Host " Metrics Loaded :"
    Write-Host "   - [1] jboss-cli DB Pool/AP Stats : $($Tables['01_cli'].Rows.Count) rows"
    Write-Host "   - [2] jstat/jcmd/JFR Heap & GC   : $($Tables['02_jvm'].Rows.Count) rows"
    Write-Host "   - [3] top/ps Process & Threads   : $($Tables['03_proc'].Rows.Count) rows"
    Write-Host "   - [4] ActiveProcessorCount Diag  : $($Tables['04_cpu'].Rows.Count) rows"
    Write-Host "   - [5] Raw Detail Log Lines       : $($RawLogLines.Count) lines"
    Write-Host "================================================================================"
}
