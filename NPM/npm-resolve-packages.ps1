param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$npmSourceList = @(
    @{ id = 'npmjs'; url = 'https://registry.npmjs.org/' }
)
$npmRepository = @{ id = 'npmjs'; url = 'https://registry.npmjs.org/' }
do {


    # ===== Require =====
    # 檢查檔案
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
    $npmrcContent.Add("registry=$($npmSourceList[0].url.TrimEnd('/'))/")
    foreach ($npmSource in $npmSourceList) {        
        if ($npmSource.token) {
            $authUrl = $npmSource.url.TrimEnd('/') -replace '^https?:', ''
            $npmrcContent.Add("$authUrl/:_authToken=$($npmSource.token)")
        } elseif ($npmSource.username -and $npmSource.password) {
            $authUrl  = $npmSource.url.TrimEnd('/') -replace '^https?:', ''
            $b64token = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($npmSource.username):$($npmSource.password)"))
            $npmrcContent.Add("$authUrl/:_auth=$b64token")
            $npmrcContent.Add("$authUrl/:always-auth=true")
        }
    }
    [System.IO.File]::WriteAllLines("$PSScriptRoot\.npmrc", $npmrcContent, [System.Text.UTF8Encoding]::new($false))

    # 建立 package-lock.json
    & npm install --package-lock-only --ignore-scripts --no-audit
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗 (npmSourceList)"
        $exitCode = 1
        break
    }
	Write-Host
	Write-Host
	Write-Host "[INFO] ------------------------------------------------------------------------"
    Write-Host "[INFO] 已建立 package-lock.json"
    
    # 讀取 package-lock.json
    $lockJson = (Get-Content 'package-lock.json' -Encoding UTF8 -Raw) -replace '(?s)"packages"\s*:\s*\{\s*"":', '"packages":{"__root__":' | ConvertFrom-Json
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
        $packageUrl  = "$($npmRepository.url.TrimEnd('/'))/$encodedName"
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
            $addingList.Add("$($package.name)@$($package.version)")
        }
    }
    Set-Content 'package-adding.txt' -Value $addingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-adding.txt"

    # 建立 package-missing.txt
    $missingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $encodedName = $package.name -replace '/', '%2F'
        $tarballUrl  = "$($npmRepository.url.TrimEnd('/'))/$encodedName/-/$($package.name.Split('/')[-1])-$($package.version).tgz"
        $isMissing   = $false
        try {
            $null = Invoke-WebRequest -Uri $tarballUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $isMissing = $true
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
