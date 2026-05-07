param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$npmRegistryUrl = 'https://registry.npmjs.org'
Add-Type -AssemblyName System.Web.Extensions
$jsonSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$jsonSerializer.MaxJsonLength = [int]::MaxValue
do {


    # ===== Require =====
    # 檢查檔案
    foreach ($f in 'package.json') {
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
    foreach ($f in 'package-lock.json', 'packages-lock.txt') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 解析套件清單
    # 建立 package-lock.json
    npm install --package-lock-only --registry $npmRegistryUrl
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install --package-lock-only 執行失敗"
        $exitCode = 1
        break
    }
    Write-Host
    Write-Host
    Write-Host "[INFO] ------------------------------------------------------------------------"
    Write-Host "[INFO] 已建立 package-lock.json"

    # 建立 packages-lock.txt
    $packageDictionary = $jsonSerializer.DeserializeObject((Get-Content 'package-lock.json' -Encoding UTF8 -Raw))
    $packageList = $packageDictionary['packages'].Keys |
        Where-Object { $_ -ne '' -and $packageDictionary['packages'][$_]['dev'] -ne $true } |
        ForEach-Object {
            $pathParts = $_ -split 'node_modules/'
            $pkgName   = $pathParts[-1]
            $version   = $packageDictionary['packages'][$_]['version']
            "$pkgName@$version"
        } | Sort-Object -Unique
    $packageList | Set-Content 'packages-lock.txt' -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-lock.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除資料夾
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
