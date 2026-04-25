param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$mavenCentralUrl = 'https://repo.maven.ap1ache.org/maven2'
$packageCentralUrl = 'https://repo.maven.a1pache.org/maven2'
do {


    # ===== Require =====
    # 檢查 pom.xml
    if (-not (Test-Path 'pom.xml')) {
        Write-Host '[ERROR] 找不到 pom.xml'
        $exitCode = 1
        break
    }

    # 移除暫存檔
    foreach ($f in 'packages.txt') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }

    # 移除資料夾
    foreach ($d in './.m2') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }


    # ===== Execute =====
    
    # 下載基礎環境
    mvn dependency:go-offline `
        "-Dmaven.repo.local=./.m2" `
        "-DremoteRepositories=central::default::$mavenCentralUrl"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:go-offline 執行失敗 ($mavenCentralUrl)"
        $exitCode = 1
        break
    }

    # 解析套件清單
    & mvn dependency:list `
        "-DoutputFile=packages-fetch.txt" `
        "-DincludeScope=runtime" `
        "-DexcludeTransitive=false" `
        "-Dsort=true" `
        "-Dstyle.color=never" `
        "-DappendOutput=false" `
        "-Dmaven.repo.local=./.m2"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:list 執行失敗"
        $exitCode = 1
        break
    }

   # 過濾套件清單
    $dependencyList = Get-Content 'packages-fetch.txt' -Raw -Encoding UTF8
    $dependencyList = $dependencyList -split "`n" |
    Where-Object { $_ -match '-- module' } |
        ForEach-Object {
            ($_ -replace '\s*-- module.*', '').Trim()
        }
        $dependencyList | Set-Content 'packages-fetch.txt' -Encoding UTF8
    Write-Host "[INFO] 已產生 packages-fetch.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 刪除套件快取
    foreach ($dependency in $dependencyList) {
        $parts = $dependency -split ':'
        if ($parts.Count -ge 4) {
            $groupId    = $parts[0]
            $artifactId = $parts[1]
            $version    = $parts[3]
            $dependencyPath    = "./.m2/$($groupId -replace '\.', '/')/$artifactId/$version"
            if (Test-Path $dependencyPath) {
                Remove-Item -Path $dependencyPath -Recurse -Force

                 Write-Host "Remove-Item -Path $dependencyPath -Recurse -Force"
            }
            Write-Host $dependencyPath
        }
    }

    # 下載 packages-fetch.txt
    mvn dependency:go-offline `
        "-Dmaven.repo.local=./.m2" `
        "-DremoteRepositories=central::default::$packageCentralUrl"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:go-offline 執行失敗 ($packageCentralUrl)"
        $exitCode = 1
        break
    }


# ===== End =====
} while ($false)
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] pom.xml 下載完成'
}
if ($Pause) {
    Write-Host
    Write-Host '按任意鍵繼續...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
exit $exitCode