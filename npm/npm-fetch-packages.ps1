param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode          = 0
$npmRegistryUrl    = 'https://registry.npmjs.org'
$npmSourceProxyUrl = 'https://registry.npmjs.org'  # 實際下載來源 (可改為私有 proxy URL)

do {

    # ===== Require =====
    # 檢查 npm
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] 找不到 npm，請確認 Node.js 已安裝並在 PATH 中"
        $exitCode = 1
        break
    }

    # 檢查檔案
    foreach ($f in 'packages-lock.txt', 'packages-new.txt') {
        if (-not (Test-Path $f)) {
            Write-Host "[ERROR] 找不到 $f，請先執行 npm-resolve-packages"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除 packages 目錄
    foreach ($d in './packages') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Path './packages' | Out-Null


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 解析 "name@version"，支援 scoped packages (如 @scope/name@version)
    function Split-PackageRef($ref) {
        $lastAt = $ref.LastIndexOf('@')
        if ($lastAt -le 0) {
            return [PSCustomObject]@{ Name = $ref; Version = '' }
        }
        return [PSCustomObject]@{
            Name    = $ref.Substring(0, $lastAt)
            Version = $ref.Substring($lastAt + 1)
        }
    }

    # 將 package 名稱編碼為 Registry URL 格式
    function Get-EncodedName($name) {
        if ($name.StartsWith('@')) {
            return $name.Replace('/', '%2F')
        }
        return $name
    }

    # 將 package 名稱轉為安全的 Windows 檔案名稱
    # @types/node-18.0.0.tgz (保留 @，替換 / 為 -)
    function Get-PackageFilename($name, $version) {
        $safeName = $name -replace '/', '-'
        return "$safeName-$version.tgz"
    }

    # 讀取 packages-lock.txt
    $packageList = Get-Content 'packages-lock.txt' -Encoding UTF8 |
        Where-Object { $_.Trim() -ne '' }

    if ($packageList.Count -eq 0) {
        Write-Host "[ERROR] packages-lock.txt 為空"
        $exitCode = 1
        break
    }

    # 建立下載清單: pkgRef → 預期檔案名稱
    $downloadList = [ordered]@{}
    foreach ($pkg in $packageList) {
        $parsed = Split-PackageRef $pkg
        if ($parsed.Name -and $parsed.Version) {
            $filename = Get-PackageFilename $parsed.Name $parsed.Version
            $downloadList[$pkg] = $filename
        }
    }

    # 下載所有套件的 tarball
    $downloadCount = 0
    $failedList    = [System.Collections.Generic.List[string]]::new()

    foreach ($kv in $downloadList.GetEnumerator()) {
        $pkgRef      = $kv.Key
        $filename    = $kv.Value
        $parsed      = Split-PackageRef $pkgRef
        $encodedName = Get-EncodedName $parsed.Name

        # 取得 tarball 下載 URL (從 registry 取得正確位址)
        $tarballUrl = $null
        try {
            $meta = Invoke-RestMethod -Uri "$npmRegistryUrl/$encodedName/$($parsed.Version)" -TimeoutSec 30 -ErrorAction Stop
            $tarballUrl = $meta.dist.tarball

            # 若設定了 proxy，替換 tarball URL 的 host
            if ($npmSourceProxyUrl -ne $npmRegistryUrl) {
                $registryHost = ([System.Uri]$npmRegistryUrl).Host
                $proxyHost    = ([System.Uri]$npmSourceProxyUrl).Host
                $proxyScheme  = ([System.Uri]$npmSourceProxyUrl).Scheme
                $tarballUrl   = $tarballUrl -replace "https?://$([regex]::Escape($registryHost))", "$proxyScheme`://$proxyHost"
            }
        } catch {
            Write-Host "[ERROR] 無法取得 $pkgRef 的下載 URL : $($_.Exception.Message)"
            $failedList.Add($pkgRef)
            continue
        }

        # 下載 tarball
        $outputPath = "./packages/$filename"
        try {
            Invoke-WebRequest -Uri $tarballUrl -OutFile $outputPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
            $downloadCount++
        } catch {
            Write-Host "[ERROR] 下載失敗 $pkgRef : $($_.Exception.Message)"
            $failedList.Add($pkgRef)
        }
    }

    # 比對套件清單，確認所有 .tgz 都已下載
    $missingList = [System.Collections.Generic.List[string]]::new()
    foreach ($kv in $downloadList.GetEnumerator()) {
        if (-not (Test-Path "./packages/$($kv.Value)")) {
            $missingList.Add($kv.Key)
        }
    }

    if ($missingList.Count -gt 0) {
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
        break
    } else {
        Write-Host "[INFO] 套件下載完成，取得 $downloadCount 個套件"
        $downloadList.Keys | Sort-Object | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] ------------------------------------------------------------------------"
    }


# ===== End =====
} while ($false)
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] 所有作業已完成'
}
if ($Pause) {
    Write-Host
    Write-Host '按任意鍵繼續...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
exit $exitCode
