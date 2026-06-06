param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$npmSourceList = @(
    @{ id = 'npmjs'; url = 'https://registry.npmjs.org' }
)
$npmRegistry = @{ id = 'npmjs'; url = 'https://registry.npmjs.org' }
do {


    # ===== Require =====
    foreach ($fileName in 'package.json') {
        if (-not (Test-Path $fileName)) {
            Write-Host "[ERROR] 找不到 $fileName"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($directoryPath in './node_modules', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in '.npmrc', 'package-lock.json', 'packages.txt', 'packages-lock.json', 'packages-adding.txt', 'packages-missing.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 .npmrc - npmSourceList
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmSourceList[0].url)")
    foreach ($npmSource in $npmSourceList) {
        if ($npmSource.scope) {
            $npmrcContent.Add("$($npmSource.scope):registry=$($npmSource.url)")
        }
        if ($npmSource.username -and $npmSource.password) {
            $authUrl = $npmSource.url -replace '^https?:', ''
            $token   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($npmSource.username):$($npmSource.password)"))
            $npmrcContent.Add("$authUrl/:_auth=$token")
        }
    }
    Set-Content '.npmrc' -Value $npmrcContent -Encoding UTF8

    # 建立 package-lock.json
    & npm install --package-lock-only --ignore-scripts --no-audit
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗 (npmSourceList)"
        $exitCode = 1
        break
    }
    $lockJson = Get-Content 'package-lock.json' -Encoding UTF8 -Raw | ConvertFrom-Json

    # 建立 packages.txt
    $packageMap = @{}
    foreach ($packageParts in $lockJson.packages.PSObject.Properties) {
        $key = $packageParts.Name
        if ($key -eq '') { continue }
        $pkg = $packageParts.Value
        if ($key -match 'node_modules/(@[^/]+/[^/]+|[^/]+)$') {
            $name = $Matches[1]
        } else {
            continue
        }
        $nameVersion = "$name@$($pkg.version)"
        if (-not $packageMap.ContainsKey($nameVersion)) {
            $packageMap[$nameVersion] = @{
                name     = $name
                version  = $pkg.version
                resolved = $pkg.resolved
            }
        }
    }
    $packageList = @($packageMap.Values | Sort-Object { $_.name })    
    $packagesContent = $packageList | ForEach-Object { "$($_.name)@$($_.version)" }
    Set-Content 'packages.txt' -Value $packagesContent -Encoding UTF8
    Write-Host "[INFO] 已建立 packages.txt"

    # 建立 packages-lock.json
    Copy-Item 'package-lock.json' 'packages-lock.json'
    Write-Host "[INFO] 已建立 packages-lock.json"

    # 建立 packages-adding.txt
    $addingList = [System.Collections.Generic.List[string]]::new()
    foreach ($pkg in $packageList) {
        $encodedName = $pkg.name -replace '/', '%2F'
        $packageUrl  = "$($npmRegistry.url)/$encodedName"
        $exists = $false
        try {
            $null = Invoke-WebRequest -Uri $packageUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $exists = $true
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $exists = $false
            } else {
                $exists = $true
            }
        }
        if (-not $exists) {
            $addingList.Add("$($pkg.name)@$($pkg.version)")
        }
    }
    Set-Content 'packages-adding.txt' -Value $addingList -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-adding.txt"

    # 建立 packages-missing.txt
    $missingList = [System.Collections.Generic.List[string]]::new()
    foreach ($pkg in $packageList) {
        $isMissing   = $false
        $encodedName = $pkg.name -replace '/', '%2F'

        # 檢查版本資訊
        $versionUrl = "$($npmRegistry.url)/$encodedName/$($pkg.version)"
        try {
            $null = Invoke-WebRequest -Uri $versionUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $isMissing = $true
            }
        }

        # 檢查 tarball
        if (-not $isMissing -and $pkg.resolved) {
            try {
                $null = Invoke-WebRequest -Uri $pkg.resolved -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            } catch {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                    $isMissing = $true
                }
            }
        }

        if ($isMissing) {
            $missingList.Add("$($pkg.name)@$($pkg.version)")
        }
    }
    Set-Content 'packages-missing.txt' -Value $missingList -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-missing.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除資料夾
    foreach ($directoryPath in './node_modules', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in '.npmrc', 'package-lock.json') {
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
