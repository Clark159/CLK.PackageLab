param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$npmSourceList     = @('https://registry.npmjs.org')
$packageSourceList = @('https://registry.npmjs.org')
do {


    # ===== Require =====
    # 檢查檔案
    foreach ($f in 'package.json', 'packages-lock.txt', 'packages-lock.json') {
        if (-not (Test-Path $f)) {
            Write-Host "[ERROR] 找不到 $f"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($d in './.npm-cache', './packages') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($f in '.npmrc') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 .npmrc
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmSourceList[0])")
    $npmrcContent | Set-Content '.npmrc' -Encoding UTF8

    # 下載基礎環境
    & npm install --ignore-scripts --cache './.npm-cache'
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗"
        $exitCode = 1
        break
    }

    # 刪除套件快取
    $dependencyList = Get-Content 'packages-lock.txt' -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }
    foreach ($dependency in $dependencyList) {
        if ($dependency -match '^(@[^@]+/[^@]+)@(.+)$') {
            $pkgName    = $Matches[1]
            $pkgVersion = $Matches[2]
        } elseif ($dependency -match '^([^@]+)@(.+)$') {
            $pkgName    = $Matches[1]
            $pkgVersion = $Matches[2]
        } else { continue }
        & npm cache clean --force $pkgName 2>$null | Out-Null
    }

    # 建立 .npmrc (packageSourceList)
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($packageSourceList[0])")
    $npmrcContent | Set-Content '.npmrc' -Encoding UTF8

    # 下載套件清單
    New-Item -ItemType Directory -Path './packages' -Force | Out-Null
    foreach ($dependency in $dependencyList) {
        & npm pack $dependency --pack-destination './packages' --cache './.npm-cache'
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] npm pack $dependency 執行失敗"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 比對套件清單
    $missingList = @()
    foreach ($dependency in $dependencyList) {
        if ($dependency -match '^(@[^@]+/[^@]+)@(.+)$') {
            $pkgName    = $Matches[1] -replace '^@', '' -replace '/', '-'
            $pkgVersion = $Matches[2]
        } elseif ($dependency -match '^([^@]+)@(.+)$') {
            $pkgName    = $Matches[1]
            $pkgVersion = $Matches[2]
        } else { continue }
        $fileName = "$pkgName-$pkgVersion.tgz"
        if (-not (Test-Path "./packages/$fileName")) {
            $missingList += $dependency
        }
    }
    if ($missingList.Count -gt 0) {
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
        break
    } else {
        Write-Host "[INFO] 套件下載完成，取得 $($dependencyList.Count) 個套件"
        $dependencyList | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] ------------------------------------------------------------------------"
    }

    # 移除資料夾
    foreach ($d in './.npm-cache', './node_modules') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($f in '.npmrc') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
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
