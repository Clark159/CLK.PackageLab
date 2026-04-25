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
    
    # 檢查檔案
    foreach ($f in 'pom.xml', 'packages-lock.txt', 'packages-lock.xml') {
        if (-not (Test-Path $f)) {
            Write-Host "[ERROR] 找不到 $f"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($d in './.m2', './packages') {
        if (Test-Path $d) {
            Remove-Item -Path $d -Recurse -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "maven-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 下載基礎環境
    mvn dependency:go-offline `
        "-Dmaven.repo.local=./.m2" `
        "-DremoteRepositories=central::default::$mavenCentralUrl"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:go-offline 執行失敗 ($mavenCentralUrl)"
        $exitCode = 1
        break
    }

    # 刪除套件快取
    $dependencyList = Get-Content 'packages-lock.txt' -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }
    foreach ($dependency in $dependencyList) {
        $parts = $dependency -split ':'
        if ($parts.Count -ge 4) {
            $groupId    = $parts[0]
            $artifactId = $parts[1]
            $version    = $parts[3]
            $dependencyPath = "./.m2/$($groupId -replace '\.', '/')/$artifactId/$version"
            if (Test-Path $dependencyPath) {
                Remove-Item -Path $dependencyPath -Recurse -Force
            }
        }
    }

    # 下載套件清單
    mvn dependency:copy-dependencies `
        "-DoutputDirectory=./packages" `
        "-Dmaven.repo.local=./.m2" `
        "-DincludeScope=runtime" `
        "-DremoteRepositories=central::default::$packageCentralUrl"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:copy-dependencies 執行失敗 ($packageCentralUrl)"
        $exitCode = 1
        break
    }

    # 比對套件清單
    $missingList = @()
    foreach ($dependency in $dependencyList) {
        $parts = $dependency -split ':'
        if ($parts.Count -lt 4) { continue }
        $artifactId = $parts[1]
        $packaging  = $parts[2]
        $version    = $parts[3]
        $fileName   = "$artifactId-$version.$packaging"
        if (-not (Test-Path "./packages/$fileName")) {
            $missingList += $dependency
        }
    }    
    if ($missingList.Count -gt 0) {
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
        break
    } else {
        Write-Host "[INFO] 套件下載完成，取得 $($dependencyList.Count) 個套件"
        $dependencyList | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] ------------------------------------------------------------------------"
    }    

    # 移除資料夾
    foreach ($d in './.m2') {
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