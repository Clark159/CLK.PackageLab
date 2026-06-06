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
    foreach ($fileName in '.npmrc', 'package.txt', 'package-lock.json', 'package-adding.txt', 'package-missing.txt') {
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
    # PS 5.1 ConvertFrom-Json 無法處理空字串 key，先將 "" 重新命名再解析
    $rawJson = (Get-Content 'package-lock.json' -Encoding UTF8 -Raw) -replace '(?s)"packages"\s*:\s*\{\s*"":', '"packages":{"__root__":'
    $lockJson = $rawJson | ConvertFrom-Json
    if ($null -eq $lockJson) {
        Write-Host "[ERROR] package-lock.json 解析失敗"
        $exitCode = 1
        break
    }

    # 建立 package.txt
    $packageMap = @{}
    foreach ($packageParts in $lockJson.packages.PSObject.Properties) {
        $key = $packageParts.Name
        if ($key -eq '') { continue }
        $package = $packageParts.Value
        if ($key -match 'node_modules/(@[^/]+/[^/]+|[^/]+)$') {
            $name = $Matches[1]
        } else {
            continue
        }
        $nameVersion = "$name@$($package.version)"
        if (-not $packageMap.ContainsKey($nameVersion)) {
            $packageMap[$nameVersion] = @{
                name     = $name
                version  = $package.version
                resolved = $package.resolved
            }
        }
    }
    $packageList = @($packageMap.Values | Sort-Object { $_.name })    
    $packageContent = $packageList | ForEach-Object { "$($_.name)@$($_.version)" }
    Set-Content 'package.txt' -Value $packageContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package.txt"

    # 建立 package-adding.txt
    $addingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $encodedName = $package.name -replace '/', '%2F'
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
            $addingList.Add("$($package.name)@$($package.version)")
        }
    }
    Set-Content 'package-adding.txt' -Value $addingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-adding.txt"

    # 建立 package-missing.txt
    $missingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $isMissing   = $false
        $encodedName = $package.name -replace '/', '%2F'

        # 檢查 version
        $versionUrl = "$($npmRegistry.url)/$encodedName/$($package.version)"
        try {
            $null = Invoke-WebRequest -Uri $versionUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $isMissing = $true
            }
        }

        # 檢查 tarball
        if (-not $isMissing -and $package.resolved) {
            try {
                $null = Invoke-WebRequest -Uri $package.resolved -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            } catch {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                    $isMissing = $true
                }
            }
        }

        if ($isMissing) {
            $missingList.Add("$($package.name)@$($package.version)")
        }
    }
    Set-Content 'package-missing.txt' -Value $missingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-missing.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除資料夾
    foreach ($directoryPath in './node_modules') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in '.npmrc') {
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
