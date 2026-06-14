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
$npmRepository = @{ id = 'npmjs'; url = 'https://registry.npmjs.org' }
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

    # 移除資料夾
    foreach ($directoryPath in './npm_caches', './node_modules', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in '.npmrc', 'package.json', 'package-lock.json', 'package-adding.txt', 'package-missing.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host
   
    # 建立 .npmrc - npmSourceList
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmSourceList[0].url)")
    $npmrcContent.Add("cache=./npm_caches")
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
    Set-Content './.npmrc' -Value $npmrcContent -Encoding UTF8

    # 讀取 package.txt
    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object { 
        $_.Trim() -ne '' 
    }

    # 產生 package.json
    $depsStr = ($packageList | ForEach-Object {
        if ($_ -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            "    `"$($Matches[1])`": `"$($Matches[2])`""
        }
    }) -join ",`n"
    $packageJsonStr = "{`n  `"name`": `"fetch-packages`",`n  `"version`": `"1.0.0`",`n  `"dependencies`": {`n$depsStr`n  }`n}"
    Set-Content './package.json' -Value $packageJsonStr -Encoding UTF8

    # 下載所有套件
    & npm install --ignore-scripts --no-audit --force --verbose
    $installExitCode = $LASTEXITCODE
    if ($installExitCode -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗 (npmSourceList)"
        $exitCode = 1
        break
    }
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 .npmrc - npmRepository
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmRepository.url)")
    $npmrcContent.Add("cache=./npm_caches")
    if ($npmRepository.scope) {
        $npmrcContent.Add("$($npmRepository.scope):registry=$($npmRepository.url)")
    }
    if ($npmRepository.username -and $npmRepository.password) {
        $authUrl = $npmRepository.url -replace '^https?:', ''
        $token   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($npmRepository.username):$($npmRepository.password)"))
        $npmrcContent.Add("$authUrl/:_auth=$token")
    }
    Set-Content './.npmrc' -Value $npmrcContent -Encoding UTF8

    # 刪除目標套件
    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            $packagePath = "./node_modules/$($Matches[1])"
            if (Test-Path $packagePath) {
                Remove-Item -Path $packagePath -Recurse -Force
            }
        }
    }
    Remove-Item -Path './npm_caches' -Recurse -Force

    # 修改 package-lock.json 的 registry 來源
    if (Test-Path './package-lock.json') {
        $lockContent = Get-Content './package-lock.json' -Encoding UTF8 -Raw
        foreach ($npmSource in $npmSourceList) {
            $lockContent = $lockContent -replace [regex]::Escape($npmSource.url), $npmRepository.url
        }
        Set-Content './package-lock.json' -Value $lockContent -Encoding UTF8
    }

    # 下載目標套件
    & npm install --ignore-scripts --no-audit --force --verbose
    $installExitCode = $LASTEXITCODE
    if ($installExitCode -ne 0) {
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
    foreach ($fileName in '.npmrc', 'package.json', 'package-lock.json') {
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
