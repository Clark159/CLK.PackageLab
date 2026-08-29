param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$scriptVersion = '20260829-00'
$exitCode = 0
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
    foreach ($directoryPath in './npm_caches', './npm_packages', './packages') {
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
    $packageInfoList = [System.Collections.Generic.List[object]]::new()
    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            $packageInfoList.Add([pscustomobject]@{
                Name    = $Matches[1]
                Version = $Matches[2]
                Spec    = "$($Matches[1])@$($Matches[2])"
            })
        }
    }
    if ($packageInfoList.Count -eq 0) {
        Write-Host "[ERROR] package.txt 未包含有效套件"
        $exitCode = 1
        break
    }

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
    if ($npmSourceList.Count -gt 1) {
        foreach ($npmSource in $npmSourceList) {
            foreach ($packageInfo in $packageInfoList) {
                $scope = ($packageInfo.Name -split '/')[0]
                $encodedName = $packageInfo.Name -replace '/', '%2F'
                if ($packageInfo.Name -notmatch '^@[^/]+/') { continue }
                if ($packageInfo.Version -notmatch '^\d+\.\d+\.\d+') { continue }
                if ($npmrcContent | Where-Object { $_ -like "$scope`:registry=*" }) { continue }
                $tarballUrl = "$($npmSource.url.TrimEnd('/'))/$encodedName/-/$($packageInfo.Name.Split('/')[-1])-$($packageInfo.Version).tgz"
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
    }
    [System.IO.File]::WriteAllLines("$PSScriptRoot\.npmrc", $npmrcContent, [System.Text.UTF8Encoding]::new($false))

    # 下載目標套件 (npmSourceList)
    New-Item -ItemType Directory -Force './npm_packages' | Out-Null
    & npm pack @($packageInfoList.Spec) --ignore-scripts --pack-destination './npm_packages' --verbose
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] npm pack 執行失敗 (npmSourceList)"
    }
    foreach ($packageInfo in $packageInfoList) {
        $tarballName = "$($packageInfo.Name.TrimStart('@') -replace '/', '-')-$($packageInfo.Version).tgz"
        if (-not (Test-Path (Join-Path './npm_packages' $tarballName))) {
            Write-Host "[ERROR] 找不到套件 $($packageInfo.Spec) (npmSourceList)"
            $exitCode = 1
        }
    }
    if ($exitCode -ne 0) { break }

    # 刪除目標套件
    if (Test-Path './npm_packages') {
        Remove-Item -Path './npm_packages' -Recurse -Force
    }

    # 建立 .npmrc (npmRepository)
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmRepository.url.TrimEnd('/'))/")
    $npmrcContent.Add("cache=./npm_caches")
    if ($npmRepository.token) {
        $authUrl = $npmRepository.url.TrimEnd('/') -replace '^https?:', ''
        $npmrcContent.Add("$authUrl/:_authToken=$($npmRepository.token)")
    } elseif ($npmRepository.username -and $npmRepository.password) {
        $authUrl  = $npmRepository.url.TrimEnd('/') -replace '^https?:', ''
        $b64token = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($npmRepository.username):$($npmRepository.password)"))
        $npmrcContent.Add("$authUrl/:_auth=$b64token")
        $npmrcContent.Add("$authUrl/:always-auth=true")
    }
    [System.IO.File]::WriteAllLines("$PSScriptRoot\.npmrc", $npmrcContent, [System.Text.UTF8Encoding]::new($false))

    # 下載目標套件 (npmRepository)
    New-Item -ItemType Directory -Force './npm_packages' | Out-Null
    & npm pack @($packageInfoList.Spec) --ignore-scripts --pack-destination './npm_packages' --verbose
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] npm pack 部分套件下載失敗 (npmRepository)"
    }

    # 複製目標套件
    $missingList = @()
    foreach ($packageInfo in $packageInfoList) {
        $tarballName = "$($packageInfo.Name.TrimStart('@') -replace '/', '-')-$($packageInfo.Version).tgz"
        $tarballPath = Join-Path './npm_packages' $tarballName
        if (Test-Path $tarballPath) {
            if ($packageInfo.Name -match '^(@[^/]+)/') {
                $destinationDirectory = "./packages/$($Matches[1])/$($packageInfo.Name.Split('/')[-1])@$($packageInfo.Version)"
            } else {
                $destinationDirectory = "./packages/$($packageInfo.Name)@$($packageInfo.Version)"
            }
            New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
            & tar -xzf $tarballPath -C $destinationDirectory --strip-components=1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[ERROR] 解壓縮失敗 $($packageInfo.Spec)"
                $missingList += $packageInfo.Spec
            }
        } else {
            $missingList += $packageInfo.Spec
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
    foreach ($directoryPath in './npm_caches', './npm_packages') {
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
