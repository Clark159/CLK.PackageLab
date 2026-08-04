param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$scriptVersion = '20260808-00'
$exitCode = 0
$pypiSourceList = @(
    @{ id = 'pypi'; url = 'https://pypi.org/simple/' }
)
$pypiRepository = @{ id = 'pypi'; url = 'https://pypi.org/simple/' }
do {


    # ===== Require =====
    # 檢查檔案
    foreach ($fileName in 'requirements.txt') {
        if (-not (Test-Path $fileName)) {
            Write-Host "[ERROR] 找不到 $fileName"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($directoryPath in './pip_caches', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'pip.ini', 'package-lock.json', 'package-all.txt', 'package-adding.txt', 'package-updating.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }

    # 整併 pypiRepository 至 pypiSourceList (以 url 為 key，id 重複則重新命名)
    if (-not ($pypiSourceList | Where-Object { $_.url -eq $pypiRepository.url })) {

        # pypiSourceId
        $suffix = 2
        $pypiSourceId = $pypiRepository.id
        while ($pypiSourceList | Where-Object { $_.id -eq $pypiSourceId }) {
            $pypiSourceId = "$($pypiRepository.id)$suffix"
            $suffix++
        }

        # pypiSource
        $pypiSource = $pypiRepository.Clone()
        $pypiSource.id = $pypiSourceId
        $pypiSourceList += $pypiSource
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "pypi-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 pip.ini - pypiSourceList
    $pipIniContent = [System.Collections.Generic.List[string]]::new()
    $pipIniContent.Add('[global]')
    $firstSource = $pypiSourceList[0]
    $firstUrl = $firstSource.url
    if ($firstSource.token) {
        $firstUrl = $firstUrl -replace '^(https?://)', "`$1$($firstSource.token)@"
    } elseif ($firstSource.username -and $firstSource.password) {
        $firstUrl = $firstUrl -replace '^(https?://)', "`$1$($firstSource.username):$($firstSource.password)@"
    }
    $pipIniContent.Add("index-url = $firstUrl")
    if ($pypiSourceList.Count -gt 1) {
        $pipIniContent.Add('extra-index-url =')
        foreach ($pypiSource in $pypiSourceList | Select-Object -Skip 1) {
            $extraUrl = $pypiSource.url
            if ($pypiSource.token) {
                $extraUrl = $extraUrl -replace '^(https?://)', "`$1$($pypiSource.token)@"
            } elseif ($pypiSource.username -and $pypiSource.password) {
                $extraUrl = $extraUrl -replace '^(https?://)', "`$1$($pypiSource.username):$($pypiSource.password)@"
            }
            $pipIniContent.Add("    $extraUrl")
        }
    }
    [System.IO.File]::WriteAllLines("$PSScriptRoot\pip.ini", $pipIniContent, [System.Text.UTF8Encoding]::new($false))
    $env:PIP_CONFIG_FILE = Join-Path $PSScriptRoot 'pip.ini'

    # 建立 package-lock.json
    & pip install `
        "--dry-run" `
        "--ignore-installed" `
        "--report" "package-lock.json" `
        "-r" "requirements.txt" `
        "--cache-dir" "./pip_caches"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] pip install 執行失敗 (pypiSourceList)"
        $exitCode = 1
        break
    }
    Write-Host
    Write-Host
    Write-Host "[INFO] ------------------------------------------------------------------------"
    Write-Host "[INFO] 已建立 package-lock.json"

    # 讀取 package-lock.json
    $lockJson = Get-Content 'package-lock.json' -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($null -eq $lockJson) {
        Write-Host "[ERROR] package-lock.json 解析失敗"
        $exitCode = 1
        break
    }

    # 建立 package-all.txt
    $packageMap = @{}
    foreach ($installItem in $lockJson.install) {
        $name    = $installItem.metadata.name
        $version = $installItem.metadata.version
        if ($name -and $version) {
            $nameVersion = "$name==$version"
            if (-not $packageMap.ContainsKey($nameVersion)) {
                $packageMap[$nameVersion] = @{
                    name    = $name
                    version = $version
                }
            }
        }
    }
    $allList        = @($packageMap.Values | Sort-Object { $_.name })
    $packageContent = $allList | ForEach-Object { "$($_.name)==$($_.version)" }
    Set-Content 'package-all.txt' -Value $packageContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package-all.txt"

    # 建立 package-adding.txt
    $addingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $allList) {
        $normalizedName = ($package.name.ToLower() -replace '[-_.]+', '-')
        $packageUrl = "$($pypiRepository.url.TrimEnd('/'))/$normalizedName/"
        $isAdding = $true
        try {
            $null = Invoke-WebRequest -Uri $packageUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $isAdding = $false
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $isAdding = $true
            } else {
                $isAdding = $false
            }
        }
        if ($isAdding) {
            $addingList.Add("$($package.name)==$($package.version)")
        }
    }
    Set-Content 'package-adding.txt' -Value $addingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-adding.txt"

    # 建立 package-updating.txt (已列在 package-adding.txt 的套件本來就不存在，不重複列入)
    $updatingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $allList) {
        $normalizedName = ($package.name.ToLower() -replace '[-_.]+', '-')
        $packageUrl = "$($pypiRepository.url.TrimEnd('/'))/$normalizedName/"
        $isUpdating = $true
        try {
            $indexPage = Invoke-WebRequest -Uri $packageUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            if ($indexPage.Content -match [regex]::Escape($package.version)) {
                $isUpdating = $false
            }
        } catch {
            $isUpdating = $true
        }
        $isAdding = $addingList | Where-Object { ($_ -split '==')[0] -eq $package.name }
        if ($isUpdating -and -not $isAdding) {
            $updatingList.Add("$($package.name)==$($package.version)")
        }
    }
    Set-Content 'package-updating.txt' -Value $updatingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-updating.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除資料夾
    foreach ($directoryPath in './pip_caches') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'pip.ini') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }


# ===== End =====
} while ($false)

Write-Host "[VERSION] $scriptVersion"
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] 所有作業已完成'
}
if ($Pause) {
    Write-Host
    Write-Host '按任意鍵繼續...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
exit $exitCode
