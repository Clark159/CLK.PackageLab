param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$projectName    = 'packages'
$projectVersion = '1.0.0'
$npmSourceList  = @('https://registry.npmjs.org')
do {


    # ===== Require =====
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
    foreach ($d in './node_modules') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($f in 'package.json', 'package-lock.json', '.npmrc', 'packages-lock.txt', 'packages-lock.json') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 package.json
    $packageList = Get-Content 'packages.txt' -Encoding UTF8 | Where-Object { $_ -match '\S' }
    $dependencies = [ordered]@{}
    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+)@(.+)$') {
            $dependencies[$Matches[1]] = $Matches[2]
        } elseif ($package -match '^([^@]+)@(.+)$') {
            $dependencies[$Matches[1]] = $Matches[2]
        }
    }
    $packageJson = [ordered]@{
        name         = $projectName
        version      = $projectVersion
        private      = $true
        dependencies = $dependencies
    }
    Set-Content 'package.json' -Value ($packageJson | ConvertTo-Json -Depth 10) -Encoding UTF8

    # 建立 .npmrc
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmSourceList[0])")
    Set-Content '.npmrc' -Value $npmrcContent -Encoding UTF8

    # 解析套件清單
    & npm install --package-lock-only --ignore-scripts
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install 執行失敗"
        $exitCode = 1
        break
    }
    Write-Host "[INFO] 已建立 package.json"

    # 建立 packages-lock.txt 與 packages-lock.json
    $lockJson = Get-Content 'package-lock.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    $resolvedList = [System.Collections.Generic.List[string]]::new()
    $bomJson = [ordered]@{}
    $lockJson.packages.PSObject.Properties |
        Where-Object { $_.Name -match '^node_modules/(@[^/]+/[^/]+|[^/]+)$' } |
        Sort-Object Name |
        ForEach-Object {
            $pkgName    = $_.Name -replace '^node_modules/', ''
            $pkgVersion = $_.Value.version
            $resolvedList.Add("$pkgName@$pkgVersion")
            $bomEntry = [ordered]@{ version = $pkgVersion }
            if ($_.Value.resolved)  { $bomEntry['resolved']  = $_.Value.resolved }
            if ($_.Value.integrity) { $bomEntry['integrity'] = $_.Value.integrity }
            $bomJson[$pkgName] = $bomEntry
        }
    Set-Content 'packages-lock.txt' -Value $resolvedList -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-lock.txt"
    Set-Content 'packages-lock.json' -Value ($bomJson | ConvertTo-Json -Depth 10) -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-lock.json"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除資料夾
    foreach ($d in './node_modules') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($f in '.npmrc', 'package-lock.json') {
        if (Test-Path $f) {
            Remove-Item $f -Force
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
