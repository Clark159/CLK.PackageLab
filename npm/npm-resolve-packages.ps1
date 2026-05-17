param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$npmRegistryUrl = 'https://registry.npmjs.org'
$platformList = @(
    @{ platform = 'linux'; arch = 'x64' },
    @{ platform = 'win32'; arch = 'x64' }
)
do {


    # ===== Require =====
    # 檢查檔案
    foreach ($f in 'packages.txt') {
        if (-not (Test-Path $f)) {
            Write-Host "[ERROR] 找不到 $f"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($d in './node_modules', './packages') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($f in 'package.json', 'package-lock.json', 'packages-lock.txt', 'packages-new.txt') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 package.json
    $packageList = @(Get-Content 'packages.txt' -Encoding UTF8 | Where-Object { $_ -match '\S' } | Where-Object { ($_ -split ':').Count -ge 2 })
    $packageJsonContent = [System.Collections.Generic.List[string]]::new()
    $packageJsonContent.Add('{')
    $packageJsonContent.Add('    "name": "packages",')
    $packageJsonContent.Add('    "version": "1.0.0",')
    $packageJsonContent.Add('    "private": true,')
    $packageJsonContent.Add('    "dependencies": {')
    for ($i = 0; $i -lt $packageList.Count; $i++) {
        $parts = $packageList[$i] -split ':'
        $packageName    = $parts[0].Trim()
        $packageVersion = $parts[1].Trim()
        $comma = if ($i -lt $packageList.Count - 1) { ',' } else { '' }
        $packageJsonContent.Add("    `"$packageName`": `"$packageVersion`"$comma")
    }
    $packageJsonContent.Add('    }')
    $packageJsonContent.Add('}')
    Set-Content 'package.json' -Value $packageJsonContent -Encoding UTF8

    # 收集各平台相依套件
    $allPackages = [System.Collections.Generic.SortedSet[string]]::new()

    foreach ($platformConfig in $platformList) {
        $platform = $platformConfig.platform
        $arch     = $platformConfig.arch
        Write-Host "[INFO] 解析 $platform-$arch 相依套件..."

        # 移除舊的 lock
        if (Test-Path 'package-lock.json') { Remove-Item 'package-lock.json' -Force }

        # 設定平台環境變數
        $env:npm_config_platform = $platform
        $env:npm_config_arch     = $arch

        # 解析相依套件 (不安裝到 node_modules)
        & npm install --package-lock-only --ignore-scripts
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] npm install 執行失敗 ($platform-$arch)"
            $exitCode = 1
            break
        }

        # 解析 package-lock.json
        $lockJson = Get-Content 'package-lock.json' -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $lockJson.packages.PSObject.Properties) {
            if ($prop.Name -eq '') { continue }
            # 取得最後一段 node_modules/ 後的名稱，處理巢狀模組
            $lastIdx = $prop.Name.LastIndexOf('node_modules/')
            $packageName    = $prop.Name.Substring($lastIdx + 'node_modules/'.Length)
            $packageVersion = $prop.Value.version
            if ($packageVersion) {
                $null = $allPackages.Add("$packageName`:$packageVersion")
            }
        }

        Write-Host "[INFO] $platform-$arch 解析完成"
    }

    # 還原環境變數
    Remove-Item Env:\npm_config_platform -ErrorAction SilentlyContinue
    Remove-Item Env:\npm_config_arch     -ErrorAction SilentlyContinue

    if ($exitCode -ne 0) { break }

    # 建立 packages-lock.txt
    $lockContent = $allPackages | ForEach-Object { $_ }
    Set-Content 'packages-lock.txt' -Value $lockContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package.json"
    Write-Host "[INFO] 已建立 packages-lock.txt ($($allPackages.Count) 個套件)"

    # 建立 packages-new.txt
    $newDependencyList = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $allPackages) {
        $colonIdx       = $entry.LastIndexOf(':')
        $packageName    = $entry.Substring(0, $colonIdx)
        $packageVersion = $entry.Substring($colonIdx + 1)

        if ($packageName -match '^@([^/]+)/(.+)$') {
            $unscoped   = $Matches[2]
            $packageUrl = "$npmRegistryUrl/$packageName/-/$unscoped-$packageVersion.tgz"
        } else {
            $packageUrl = "$npmRegistryUrl/$packageName/-/$packageName-$packageVersion.tgz"
        }

        $packageExists = $false
        try {
            $null = Invoke-WebRequest -Uri $packageUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $packageExists = $true
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $packageExists = $false
            } else {
                $packageExists = $true
            }
        }
        if (-not $packageExists) {
            $newDependencyList.Add($entry)
        }
    }
    Set-Content 'packages-new.txt' -Value $newDependencyList -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-new.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除暫存
    foreach ($f in 'package-lock.json') {
        if (Test-Path $f) { Remove-Item $f -Force }
    }
    foreach ($d in './node_modules') {
        if (Test-Path $d) { Remove-Item -Path $d -Recurse -Force }
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
