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
    foreach ($directoryPath in './.npm-fetch-tmp', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 讀取 package.txt
    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }

    # 建立暫存目錄
    New-Item -ItemType Directory -Force './.npm-fetch-tmp' | Out-Null

    # 產生 package.json
    $depsStr = ($packageList | ForEach-Object {
        if ($_ -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            "    `"$($Matches[1])`": `"$($Matches[2])`""
        }
    }) -join ",`n"
    $packageJsonStr = "{`n  `"name`": `"fetch-packages`",`n  `"version`": `"1.0.0`",`n  `"dependencies`": {`n$depsStr`n  }`n}"
    Set-Content './.npm-fetch-tmp/package.json' -Value $packageJsonStr -Encoding UTF8

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
    Set-Content './.npm-fetch-tmp/.npmrc' -Value $npmrcContent -Encoding UTF8

    # 下載所有套件
    Push-Location './.npm-fetch-tmp'
    & npm install --ignore-scripts --no-audit
    $installExitCode = $LASTEXITCODE
    Pop-Location
    if ($installExitCode -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗 (npmSourceList)"
        $exitCode = 1
        break
    }

    # 建立 .npmrc - npmRegistry
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmRegistry.url)")
    if ($npmRegistry.scope) {
        $npmrcContent.Add("$($npmRegistry.scope):registry=$($npmRegistry.url)")
    }
    if ($npmRegistry.username -and $npmRegistry.password) {
        $authUrl = $npmRegistry.url -replace '^https?:', ''
        $token   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($npmRegistry.username):$($npmRegistry.password)"))
        $npmrcContent.Add("$authUrl/:_auth=$token")
    }
    Set-Content './.npm-fetch-tmp/.npmrc' -Value $npmrcContent -Encoding UTF8

    # 刪除目標套件
    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            $name = $Matches[1]
            $packagePath = "./.npm-fetch-tmp/node_modules/$name"
            if (Test-Path $packagePath) {
                Remove-Item -Path $packagePath -Recurse -Force
            }
        }
    }

    # 刪除 package-lock.json（讓 npm 重新解析來源）
    if (Test-Path './.npm-fetch-tmp/package-lock.json') {
        Remove-Item './.npm-fetch-tmp/package-lock.json' -Force
    }

    # 下載目標套件
    Push-Location './.npm-fetch-tmp'
    & npm install --ignore-scripts --no-audit
    $installExitCode = $LASTEXITCODE
    Pop-Location
    if ($installExitCode -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗 (npmRegistry)"
        $exitCode = 1
        break
    }

    # 複製目標套件
    $missingList = @()
    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            $name    = $Matches[1]
            $version = $Matches[2]
            $packagePath = "./.npm-fetch-tmp/node_modules/$name"
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

    if ($missingList.Count -eq 0) {
        $packageList | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] 套件下載完成，取得 $($packageList.Count) 個套件"
        Write-Host "[INFO] ------------------------------------------------------------------------"
    } else {
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
    }

    # 移除資料夾
    foreach ($directoryPath in './.npm-fetch-tmp') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
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
