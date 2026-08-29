param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$scriptVersion = '20260829-00'
$exitCode = 0
$nugetSourceList = @(
    @{ id = 'nuget.org'; url = 'https://api.nuget.org/v3/index.json'; username = ''; token = '' }
)
$nugetRepository = @{ id = 'nuget.org'; url = 'https://api.nuget.org/v3/index.json'; username = ''; token = '' }
do {


    # ===== Require =====
    # 檢查檔案
    if (-not (Test-Path 'package.txt')) {
        if (Test-Path 'package-all.txt') {
            Copy-Item -Path 'package-all.txt' -Destination 'package.txt' -Force
        } else {
            Write-Host "[ERROR] 找不到 package.txt"
            $exitCode = 1
        }
    }
    if ($exitCode -ne 0) { break }

    # 檢查資料夾
    $folderName = Split-Path $PSScriptRoot -Leaf
    if ($folderName -match '^\d{12}-\d{2}$') {
        $nugetRepository.url = $nugetRepository.url -replace '(?<=/)(index\.json)$', "$folderName/`$1"
    }

    # 移除資料夾
    foreach ($directoryPath in './nuget_caches', './obj', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'nuget.config') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "nuget-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 讀取 package.txt
    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object {
        $_.Trim() -ne ''
    }

    # 下載目標套件 (nugetRepository)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $nugetRepository.headers = @{}
    if ($nugetRepository.token) {
        $username  = if ($nugetRepository.username) { $nugetRepository.username } else { 'PAT' }
        $authBytes = [System.Text.Encoding]::ASCII.GetBytes("$username`:$($nugetRepository.token)")
        $nugetRepository.headers = @{ Authorization = "Basic $([Convert]::ToBase64String($authBytes))" }
    }
    $nugetRepository.packageBaseUrl = $null
    try {
        $serviceIndex = Invoke-RestMethod -Uri $nugetRepository.url -Method Get -Headers $nugetRepository.headers -TimeoutSec 15 -ErrorAction Stop
        $nugetRepository.packageBaseUrl = (($serviceIndex.resources | Where-Object { $_.'@type' -like 'PackageBaseAddress/*' } | Select-Object -First 1).'@id') -replace '/$', ''
    } catch { }
    foreach ($package in $packageList) {
        $packageParts = $package -split '\s+'
        if ($packageParts.Count -ge 2) {
            $packageIdLower      = $packageParts[0].ToLower()
            $packageVersion      = $packageParts[1]
            $packageVersionLower = $packageVersion.ToLower()
            $packagePath         = "./nuget_caches/$packageIdLower/$packageVersion"
            $packageFile         = "./nuget_caches/$packageIdLower.$packageVersion.nupkg"
            if ($nugetRepository.packageBaseUrl) {
                $packageUrl = "$($nugetRepository.packageBaseUrl)/$packageIdLower/$packageVersionLower/$packageIdLower.$packageVersionLower.nupkg"
                try {
                    Invoke-WebRequest -Uri $packageUrl -Headers $nugetRepository.headers -OutFile $packageFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                    if (Test-Path $packagePath) {
                        Remove-Item -Path $packagePath -Recurse -Force
                    }
                    New-Item -ItemType Directory -Force $packagePath | Out-Null
                    [System.IO.Compression.ZipFile]::ExtractToDirectory($packageFile, $packagePath)
                    Remove-Item $packageFile -Force
                } catch { }
            }
        }
    }

    # 複製目標套件
    $missingList = @()
    foreach ($package in $packageList) {
        $packageParts = $package -split '\s+'
        if ($packageParts.Count -ge 2) {
            $packageIdLower = $packageParts[0].ToLower()
            $packageVersion = $packageParts[1]
            $packagePath    = "./nuget_caches/$packageIdLower/$packageVersion"
            if (Test-Path $packagePath) {
                $destinationDirectory = "./packages/$packageIdLower"
                New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
                Copy-Item -Path $packagePath -Destination $destinationDirectory -Recurse -Force
            } else {
                $missingList += $package
            }
        }
    }
    Get-ChildItem -Path './packages' -Recurse -Filter '.nupkg.metadata' | Remove-Item -Force

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
    foreach ($directoryPath in './nuget_caches', './obj') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'nuget.config') {
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
