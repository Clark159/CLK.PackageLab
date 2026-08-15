param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$scriptVersion = '20260815-00'
$exitCode = 0
$projectName    = 'fetch-packages'
$projectVersion = '1.0.0'
$npmSourceList  = @(
    @{ id = 'npmjs'; url = 'https://registry.npmjs.org/'; username = ''; token = '' }
)
$npmRepository  = @{ id = 'npmjs'; url = 'https://registry.npmjs.org/'; username = ''; token = '' }
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
        $npmRepository.url = "$($npmRepository.url.TrimEnd('/'))/$folderName/"
    }

    # 移除資料夾
    foreach ($directoryPath in './npm_caches', './node_modules', './packages') {
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


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 讀取 package.txt
    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object {
        $_.Trim() -ne ''
    }

    # 產生 package.json
    $dependencyList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            $dependencyList.Add("        `"$($Matches[1])`": `"$($Matches[2])`"")
        }
    }
    $packageJsonContent = [System.Collections.Generic.List[string]]::new()
    $packageJsonContent.Add('{')
    $packageJsonContent.Add("    `"name`": `"$projectName`",")
    $packageJsonContent.Add("    `"version`": `"$projectVersion`",")
    $packageJsonContent.Add('    "dependencies": {')
    $packageJsonContent.Add(($dependencyList -join ",`n"))
    $packageJsonContent.Add('    }')
    $packageJsonContent.Add('}')
    Set-Content './package.json' -Value $packageJsonContent -Encoding UTF8

    # 建立 .npmrc (npmSourceList:default-registry)
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

    # 建立 .npmrc (npmSourceList:scope-registry)
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

    # 下載目標套件
    & npm install --ignore-scripts --no-audit --force --verbose
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗 (npmSourceList)"
        $exitCode = 1
        break
    }

    # 建立 .npmrc (npmRepository)
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmRepository.url.TrimEnd('/'))/")
    $npmrcContent.Add("cache=./npm_caches")
    if ($npmRepository.token) {
        $authUrl = $npmRepository.url.TrimEnd('/') -replace '^https?:', ''
        $npmrcContent.Add("$authUrl/:_authToken=$($npmRepository.token)")
    }
    [System.IO.File]::WriteAllLines("$PSScriptRoot\.npmrc", $npmrcContent, [System.Text.UTF8Encoding]::new($false))

    # 刪除目標套件
    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            $packagePath = "./node_modules/$($Matches[1])"
            if (Test-Path $packagePath) {
                Remove-Item -Path $packagePath -Recurse -Force
            }
        }
    }
    if (Test-Path './npm_caches') {
        Remove-Item -Path './npm_caches' -Recurse -Force
    }

    # 產生 package.json
    if (Test-Path './package-lock.json') {
        $lockContent = Get-Content './package-lock.json' -Encoding UTF8 -Raw
        foreach ($npmSource in $npmSourceList) {
            $lockContent = $lockContent -replace [regex]::Escape($npmSource.url), $npmRepository.url
        }
        Set-Content './package-lock.json' -Value $lockContent -Encoding UTF8
    }

    # 下載目標套件
    & npm install --ignore-scripts --no-audit --force --verbose
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗 (npmRepository)"
        $exitCode = 1
        break
    }

    # 複製目標套件
    $missingList = @()
    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            $name    = $Matches[1]
            $version = $Matches[2]
            $packagePath = "./node_modules/$name"
            if (Test-Path $packagePath) {
                if ($name -match '^(@[^/]+)/') {
                    $destinationDirectory = "./packages/$($Matches[1])"
                } else {
                    $destinationDirectory = './packages'
                }
                New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
                Copy-Item -Path $packagePath -Destination $destinationDirectory -Recurse -Force
            } else {
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
