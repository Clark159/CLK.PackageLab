param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$scriptVersion = '20260815-00'
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
    foreach ($directoryPath in './npm_caches', './node_modules', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in '.npmrc', 'package-lock.json', 'package-all.txt', 'package-adding.txt', 'package-updating.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }

    # 整併 npmRepository 至 npmSourceList
    if (-not ($npmSourceList | Where-Object { $_.url -eq $npmRepository.url })) {

        # npmSourceId
        $suffix = 2
        $npmSourceId = $npmRepository.id
        while ($npmSourceList | Where-Object { $_.id -eq $npmSourceId }) {
            $npmSourceId = "$($npmRepository.id)$suffix"
            $suffix++
        }

        # npmSource
        $npmSource = $npmRepository.Clone()
        $npmSource.id = $npmSourceId
        $npmSourceList += $npmSource
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 讀取 package.json
    $packageJson = (Get-Content 'package.json' -Encoding UTF8 -Raw) | ConvertFrom-Json
    if ($null -eq $packageJson) {
        Write-Host "[ERROR] package.json 解析失敗"
        $exitCode = 1
        break
    }
    $dependencyList = [System.Collections.Generic.List[object]]::new()
    foreach ($dependencyType in 'dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies') {
        if ($packageJson.$dependencyType) {
            $dependencyList.AddRange(@($packageJson.$dependencyType.PSObject.Properties))
        }
    }

    # 建立 .npmrc (default-registry)
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmSourceList[0].url.TrimEnd('/'))/")
    $npmrcContent.Add("cache=./npm_caches")
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

    # 建立 .npmrc (scope-registry)
    foreach ($npmSource in $npmSourceList) {
        foreach ($dependency in $dependencyList) {
            $scope = ($dependency.Name -split '/')[0]
            $encodedName = $dependency.Name -replace '/', '%2F'
            if ($dependency.Name -notmatch '^@[^/]+/') { continue }
            if ($dependency.Value -notmatch '^\d+\.\d+\.\d+') { continue }
            if ($npmrcContent | Where-Object { $_ -like "$scope`:registry=*" }) { continue }
            $tarballUrl = "$($npmSource.url.TrimEnd('/'))/$encodedName/-/$($dependency.Name.Split('/')[-1])-$($dependency.Value).tgz"
            $isExisting = $true
            try {
                $null = Invoke-WebRequest -Uri $tarballUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            } catch {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                    $isExisting = $false
                }
            }
            if ($isExisting) {
                $npmrcContent.Add("$scope`:registry=$($npmSource.url.TrimEnd('/'))/")
            }
        }
    }
    [System.IO.File]::WriteAllLines("$PSScriptRoot\.npmrc", $npmrcContent, [System.Text.UTF8Encoding]::new($false))

    # 建立 package-lock.json
    & npm install --package-lock-only --ignore-scripts --no-audit --legacy-peer-deps
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

    # 建立 package-all.txt
    $packageMap = @{}
    foreach ($packageParts in $lockJson.packages.PSObject.Properties) {
        if ($packageParts.Name -eq '') { continue }
        $package = $packageParts.Value
        if ($packageParts.Name -match 'node_modules/(@[^/]+/[^/]+|[^/]+)$') {
            $name = $Matches[1]
        } else {
            continue
        }
        if ($package.name) {
            $name = $package.name
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
    $allList = @($packageMap.Values | Sort-Object { $_.name })
    $packageContent = $allList | ForEach-Object { "$($_.name)@$($_.version)" }
    Set-Content 'package-all.txt' -Value $packageContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package-all.txt"

    # 建立 package-adding.txt
    $addingList = [System.Collections.Generic.List[object]]::new()
    foreach ($package in $allList) {
        $encodedName = $package.name -replace '/', '%2F'
        $packageUrl  = "$($npmRepository.url.TrimEnd('/'))/-/package/$encodedName/dist-tags"
        $isAdding = $true
        try {
            $null = Invoke-WebRequest -Uri $packageUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $isAdding = $false
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $isAdding = $true
            } else {
                $isAdding = $false
            }
        }
        if ($isAdding) {
            $addingList.Add($package)
        }
    }
    Set-Content 'package-adding.txt' -Value ($addingList | ForEach-Object { "$($_.name)@$($_.version)" }) -Encoding UTF8
    Write-Host "[INFO] 已建立 package-adding.txt"

    # 建立 package-updating.txt (已列在 package-adding.txt 的套件本來就不存在，不重複列入)
    $updatingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $allList) {
        $encodedName = $package.name -replace '/', '%2F'
        $tarballUrl  = "$($npmRepository.url.TrimEnd('/'))/$encodedName/-/$($package.name.Split('/')[-1])-$($package.version).tgz"
        $isUpdating  = $false
        try {
            $null = Invoke-WebRequest -Uri $tarballUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $isUpdating = $true
            }
        }
        $isAdding = $addingList | Where-Object { $_.name -eq $package.name }
        if ($isUpdating -and -not $isAdding) {
            $updatingList.Add("$($package.name)@$($package.version)")
        }
    }
    Set-Content 'package-updating.txt' -Value $updatingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-updating.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除資料夾
    foreach ($directoryPath in './npm_caches', './node_modules') {
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
