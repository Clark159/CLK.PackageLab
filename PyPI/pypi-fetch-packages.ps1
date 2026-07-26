param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$pypiSourceList = @(
    @{ id = 'pypi'; url = 'https://pypi.org/simple/'; username = ''; token = '' }
)
$pypiRepository = @{ id = 'pypi'; url = 'https://pypi.org/simple/'; username = ''; token = '' }
do {


    # ===== Require =====
    # 檢查檔案
    foreach ($fileName in 'package.txt') {
        if (-not (Test-Path $fileName)) {
            Write-Host "[ERROR] 找不到 $fileName"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 檢查資料夾
    $folderName = Split-Path $PSScriptRoot -Leaf
    if ($folderName -match '^\d{12}-\d{2}$') {
        $pypiRepository.url = "$($pypiRepository.url.TrimEnd('/'))/$folderName-AP/"
    }

    # 移除資料夾
    foreach ($directoryPath in './pip_caches', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'pip.ini', 'requirements.txt', 'package-lock.json', 'package-adding.txt', 'package-missing.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "pypi-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 pip.ini - pypiSourceList
    $pipIniContent = [System.Collections.Generic.List[string]]::new()
    $pipIniContent.Add('[global]')
    $firstSource = $pypiSourceList[0]
    $firstUrl = $firstSource.url
    if ($firstSource.token) {
        $firstUrl = $firstUrl -replace '^(https?://)', "`$1$($firstSource.token)@"
    }
    $pipIniContent.Add("index-url = $firstUrl")
    if ($pypiSourceList.Count -gt 1) {
        $pipIniContent.Add('extra-index-url =')
        foreach ($pypiSource in $pypiSourceList | Select-Object -Skip 1) {
            $extraUrl = $pypiSource.url
            if ($pypiSource.token) {
                $extraUrl = $extraUrl -replace '^(https?://)', "`$1$($pypiSource.token)@"
            }
            $pipIniContent.Add("    $extraUrl")
        }
    }
    Set-Content 'pip.ini' -Value $pipIniContent -Encoding UTF8
    $env:PIP_CONFIG_FILE = Join-Path $PSScriptRoot 'pip.ini'

    # 讀取 package.txt
    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object {
        $_.Trim() -ne ''
    }

    # 產生 requirements.txt
    $requirementsContent = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $requirementsContent.Add($package)
    }
    Set-Content 'requirements.txt' -Value $requirementsContent -Encoding UTF8

    # 下載所有套件
    & pip download `
        "-r" "requirements.txt" `
        "--no-deps" `
        "--dest" "./pip_caches" `
        "--cache-dir" "./pip_caches"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] pip download 執行失敗 (pypiSourceList)"
        $exitCode = 1
        break
    }

    # 建立 pip.ini - pypiRepository
    $pipIniContent = [System.Collections.Generic.List[string]]::new()
    $pipIniContent.Add('[global]')
    $repositoryUrl = $pypiRepository.url
    if ($pypiRepository.token) {
        $repositoryUrl = $repositoryUrl -replace '^(https?://)', "`$1$($pypiRepository.token)@"
    }
    $pipIniContent.Add("index-url = $repositoryUrl")
    Set-Content 'pip.ini' -Value $pipIniContent -Encoding UTF8

    # 清除快取
    if (Test-Path './pip_caches') {
        Remove-Item -Path './pip_caches' -Recurse -Force
    }

    # 下載目標套件
    & pip download `
        "-r" "requirements.txt" `
        "--no-deps" `
        "--dest" "./packages" `
        "--cache-dir" "./pip_caches"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] pip download 執行失敗 (pypiRepository)"
        $exitCode = 1
        break
    }

    # 驗證下載結果
    $missingList = @()
    foreach ($package in $packageList) {
        $packageParts = $package -split '=='
        if ($packageParts.Count -ge 2) {
            $safeName = $packageParts[0] -replace '[-_.]+', '*'
            $matched = $null
            if (Test-Path './packages') {
                $matched = Get-ChildItem -Path './packages' -Filter "$safeName-$($packageParts[1])*"
            }
            if (-not $matched) {
                $missingList += $package
            }
        }
    }

    # 顯示下載結果
    if ($missingList.Count -eq 0) {
        Write-Host
        Write-Host
        Write-Host "[INFO] ------------------------------------------------------------------------"
        $packageList | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] 套件下載完成，取得 $($packageList.Count) 個套件"
        Write-Host "[INFO] ------------------------------------------------------------------------"
    } else {
        Write-Host
        Write-Host
        Write-Host "[INFO] ------------------------------------------------------------------------"
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
    }

    # 移除資料夾
    foreach ($directoryPath in './pip_caches') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'pip.ini', 'requirements.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
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
