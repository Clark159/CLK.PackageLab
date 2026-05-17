param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode          = 0
$npmRegistryUrl    = 'https://registry.npmjs.org'
$npmSourceProxyUrl = 'https://example.com'  # 私有倉庫 URL，用於檢查新套件

do {

    # ===== Require =====
    # 檢查 npm
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] 找不到 npm，請確認 Node.js 已安裝並在 PATH 中"
        $exitCode = 1
        break
    }

    # 檢查檔案
    foreach ($f in 'packages.txt') {
        if (-not (Test-Path $f)) {
            Write-Host "[ERROR] 找不到 $f"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($d in './node_modules', './packages') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($f in 'package.json', 'package-lock.json', 'packages-lock.txt', 'packages-new.txt') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 解析 "name@version"，支援 scoped packages (如 @scope/name@version)
    # version 分隔符號為最後一個 @ 字元
    function Split-PackageRef($ref) {
        $lastAt = $ref.LastIndexOf('@')
        if ($lastAt -le 0) {
            return [PSCustomObject]@{ Name = $ref; Version = 'latest' }
        }
        return [PSCustomObject]@{
            Name    = $ref.Substring(0, $lastAt)
            Version = $ref.Substring($lastAt + 1)
        }
    }

    # 將 package 名稱編碼為 Registry URL 格式
    # scoped packages 的 / 需要 URL encode: @types/node → @types%2Fnode
    function Get-EncodedName($name) {
        if ($name.StartsWith('@')) {
            return $name.Replace('/', '%2F')
        }
        return $name
    }

    # 將 package 名稱轉為安全的 Windows 檔案名稱
    # @types/node → @types-node (保留 @，替換 /)
    function Get-PackageFilename($name, $version) {
        $safeName = $name -replace '/', '-'
        return "$safeName-$version.tgz"
    }

    # 讀取 packages.txt，跳過空行與 # 註解
    $packageList = Get-Content 'packages.txt' -Encoding UTF8 |
        Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }

    if ($packageList.Count -eq 0) {
        Write-Host "[ERROR] packages.txt 沒有有效的套件定義"
        $exitCode = 1
        break
    }

    # 建立 package.json
    $depsObj = [ordered]@{}
    foreach ($pkg in $packageList) {
        $parsed = Split-PackageRef $pkg
        $depsObj[$parsed.Name] = $parsed.Version
    }
    $packageJson = [ordered]@{
        name         = 'packages'
        version      = '1.0.0'
        description  = ''
        private      = $true
        dependencies = $depsObj
    }
    Set-Content 'package.json' -Value ($packageJson | ConvertTo-Json -Depth 10) -Encoding UTF8

    # 執行 npm install --package-lock-only 解析完整相依樹
    & npm install --package-lock-only --ignore-scripts
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗"
        $exitCode = 1
        break
    }
    Write-Host "[INFO] 已建立 package.json"
    Write-Host "[INFO] 已建立 package-lock.json"

    # 解析 package-lock.json (lockfileVersion 2/3 使用 packages 欄位)
    if (-not (Test-Path 'package-lock.json')) {
        Write-Host "[ERROR] npm 未產生 package-lock.json"
        $exitCode = 1
        break
    }
    $lockJson = Get-Content 'package-lock.json' -Raw -Encoding UTF8 | ConvertFrom-Json

    # 收集所有套件 (HashSet 以 "name@version" 為單位)
    $allPackages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $toProcess   = [System.Collections.Generic.Queue[string]]::new()

    function Add-Package($ref) {
        if ($script:allPackages.Add($ref)) {
            $script:toProcess.Enqueue($ref)
            return $true
        }
        return $false
    }

    # 從 package-lock.json packages 欄位收集 (npm v7+, lockfileVersion 2/3)
    if ($null -ne $lockJson.packages) {
        foreach ($prop in $lockJson.packages.PSObject.Properties) {
            $entryPath = $prop.Name
            if ($entryPath -eq '') { continue }  # 跳過根目錄
            # 取得最後一個 node_modules/ 之後的套件名稱
            # 處理巢狀路徑如 node_modules/a/node_modules/b
            $lastIdx = $entryPath.LastIndexOf('node_modules/')
            if ($lastIdx -ge 0) {
                $pkgName    = $entryPath.Substring($lastIdx + 'node_modules/'.Length)
                $pkgVersion = $prop.Value.version
                if ($pkgName -and $pkgVersion) {
                    Add-Package "$pkgName@$pkgVersion" | Out-Null
                }
            }
        }
    }

    Write-Host "[INFO] 從 package-lock.json 取得 $($allPackages.Count) 個套件"
    Write-Host "[INFO] 正在解析所有平台的選擇性相依套件..."

    # BFS: 透過 Registry API 取得每個套件的 optionalDependencies
    # 確保下載所有平台的套件 (不只有當前平台)
    $apiCallCount = 0
    while ($toProcess.Count -gt 0) {
        $pkgRef     = $toProcess.Dequeue()
        $lastAt     = $pkgRef.LastIndexOf('@')
        $pkgName    = $pkgRef.Substring(0, $lastAt)
        $pkgVersion = $pkgRef.Substring($lastAt + 1)
        $encodedName = Get-EncodedName $pkgName

        try {
            $meta = Invoke-RestMethod -Uri "$npmRegistryUrl/$encodedName/$pkgVersion" -TimeoutSec 30 -ErrorAction Stop
            $apiCallCount++

            if ($null -ne $meta.optionalDependencies) {
                foreach ($optProp in $meta.optionalDependencies.PSObject.Properties) {
                    $optName         = $optProp.Name
                    $optVersionRange = [string]$optProp.Value

                    # 若已在清單中則跳過
                    $alreadyExists = $false
                    foreach ($existing in $allPackages) {
                        $lastAt2 = $existing.LastIndexOf('@')
                        if ($lastAt2 -gt 0 -and $existing.Substring(0, $lastAt2) -eq $optName) {
                            $alreadyExists = $true
                            break
                        }
                    }
                    if ($alreadyExists) { continue }

                    # 解析版本範圍
                    $resolvedVer = $null
                    if ($optVersionRange -match '^\d') {
                        # 精確版本號，直接使用
                        $resolvedVer = $optVersionRange
                    } else {
                        # 版本範圍 (^x.y.z, ~x.y.z, >=x 等)，使用 npm view 解析
                        $rawOutput = (& npm view "$optName@$optVersionRange" version 2>$null) -join "`n"
                        if ($LASTEXITCODE -eq 0 -and $rawOutput.Trim()) {
                            $lines = $rawOutput -split "`n" | Where-Object { $_.Trim() -match '^\d' }
                            if ($lines) {
                                $resolvedVer = $lines[-1].Trim()
                            }
                        }
                        # Fallback: 使用 dist-tags.latest
                        if (-not $resolvedVer) {
                            try {
                                $optMeta     = Invoke-RestMethod -Uri "$npmRegistryUrl/$(Get-EncodedName $optName)" -TimeoutSec 30 -ErrorAction Stop
                                $apiCallCount++
                                $resolvedVer = $optMeta.'dist-tags'.latest
                            } catch {
                                Write-Host "[WARN] 無法解析 $optName@$optVersionRange"
                            }
                        }
                    }

                    if ($resolvedVer) {
                        Add-Package "$optName@$resolvedVer" | Out-Null
                    }
                }
            }
        } catch {
            # API 錯誤時跳過此套件的 optional deps 檢查
        }
    }

    Write-Host "[INFO] Registry API 呼叫次數: $apiCallCount"
    Write-Host "[INFO] 共解析 $($allPackages.Count) 個套件（含所有平台）"

    # 建立 packages-lock.txt
    $lockContent = $allPackages | Sort-Object
    Set-Content 'packages-lock.txt' -Value $lockContent -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-lock.txt"

    # 建立 packages-new.txt (檢查哪些套件不在私有倉庫)
    $newPackageList = [System.Collections.Generic.List[string]]::new()
    foreach ($pkgRef in ($allPackages | Sort-Object)) {
        $lastAt      = $pkgRef.LastIndexOf('@')
        $pkgName     = $pkgRef.Substring(0, $lastAt)
        $pkgVersion  = $pkgRef.Substring($lastAt + 1)
        $encodedName = Get-EncodedName $pkgName
        $checkUrl    = "$npmSourceProxyUrl/$encodedName/$pkgVersion"
        $pkgExists   = $false
        try {
            $null = Invoke-WebRequest -Uri $checkUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $pkgExists = $true
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $pkgExists = $false
            } else {
                $pkgExists = $true
            }
        }
        if (-not $pkgExists) {
            $newPackageList.Add($pkgRef)
        }
    }
    Set-Content 'packages-new.txt' -Value $newPackageList -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-new.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除暫存檔案
    foreach ($f in 'package.json') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }
    foreach ($d in './node_modules') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
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
