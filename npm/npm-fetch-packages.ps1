param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
do {


    # ===== Require =====
    foreach ($f in 'package.json', 'packages-lock.txt') {
        if (-not (Test-Path $f)) {
            Write-Host "[ERROR] 找不到 $f"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($d in './packages') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Force './packages' | Out-Null


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    $dependencyList = Get-Content 'packages-lock.txt' -Encoding UTF8 |
        Where-Object { $_.Trim() -ne '' }

    # 下載所有套件
    foreach ($dependency in $dependencyList) {
        $colonIdx   = $dependency.LastIndexOf(':')
        $pkgName    = $dependency.Substring(0, $colonIdx)
        $pkgVersion = $dependency.Substring($colonIdx + 1)
        Write-Host "[INFO] 下載 $pkgName@$pkgVersion ..."
        & npm pack "$pkgName@$pkgVersion" --pack-destination './packages'
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] npm pack 失敗: $pkgName@$pkgVersion"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 驗證所有套件
    $missingList = @()
    foreach ($dependency in $dependencyList) {
        $colonIdx   = $dependency.LastIndexOf(':')
        $pkgName    = $dependency.Substring(0, $colonIdx)
        $pkgVersion = $dependency.Substring($colonIdx + 1)
        # npm pack 輸出檔名規則：去掉 @，/ 換成 -，全小寫
        $safeName = ($pkgName -replace '^@', '' -replace '/', '-').ToLower()
        $tgzName  = "$safeName-$pkgVersion.tgz"
        if (-not (Test-Path "./packages/$tgzName")) {
            $missingList += $dependency
        }
    }
    if ($missingList.Count -eq 0) {
        $dependencyList | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] 套件下載完成，取得 $($dependencyList.Count) 個套件"
        Write-Host "[INFO] ------------------------------------------------------------------------"
    } else {
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
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
