param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$npmRegistryUrl = 'https://registry.npmjs.org'
$platformList = @(
    @{ platform = 'linux'; arch = 'x64' },
    @{ platform = 'win32'; arch = 'x64' }
)
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

    # 建立 package.json
    $packageList = @(Get-Content 'packages.txt' -Encoding UTF8 | Where-Object { $_ -match '\S' })
    $packageJsonContent = [System.Collections.Generic.List[string]]::new()
    $packageJsonContent.Add('{')
    $packageJsonContent.Add('    "name": "packages",')
    $packageJsonContent.Add('    "version": "1.0.0",')
    $packageJsonContent.Add('    "private": true,')
    $packageJsonContent.Add('    "dependencies": {')
    for ($i = 0; $i -lt $packageList.Count; $i++) {
        $parts = $packageList[$i] -split ':'
        $packageName    = $parts[0]
        $packageVersion = $parts[1]
        $comma = if ($i -lt $packageList.Count - 1) { ',' } else { '' }
        $packageJsonContent.Add("    `"$packageName`": `"$packageVersion`"$comma")
    }
    $packageJsonContent.Add('    }')
    $packageJsonContent.Add('}')
    Set-Content 'package.json' -Value $packageJsonContent -Encoding UTF8
   

   


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
