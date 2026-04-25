Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
do {


    # ===== Require =====
    # 檢查 pom.xml
    if (-not (Test-Path 'pom.xml')) {
        Write-Host '[ERROR] 找不到 pom.xml'
        $exitCode = 1
        break
    }

    # 清理暫存檔
    foreach ($f in 'packages-lock.txt', 'packages-lock.xml') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }


    # ===== Execute =====
    Write-Host "========================================"
    Write-Host "套件專案: pom.xml"
    Write-Host "========================================"
    Write-Host

    # 解析套件清單
    & mvn dependency:list `
        "-DoutputFile=packages-lock.txt" `
        "-DincludeScope=runtime" `
        "-DexcludeTransitive=false" `
        "-Dsort=true" `
        "-Dstyle.color=never" `
        "-DappendOutput=false"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:list 執行失敗"
        $exitCode = 1
        break
    }

    # 過濾套件清單
    $packagesLockString = Get-Content 'packages-lock.txt' -Raw -Encoding UTF8
    $packagesLockString = $packagesLockString -split "`n" |
    Where-Object { $_ -match '-- module' } |
    ForEach-Object {
        ($_ -replace '\s*-- module.*', '').Trim()
    }
    $packagesLockString | Set-Content 'packages-lock.txt' -Encoding UTF8

    # 讀取專案參數
    $PROJECT_MODELVERSION = ((& mvn help:evaluate '-Dexpression=project.modelVersion' -q '-DforceStdout') | Where-Object { $_ } | Select-Object -Last 1).Trim()
    $PROJECT_GROUPID      = ((& mvn help:evaluate '-Dexpression=project.groupId'      -q '-DforceStdout') | Where-Object { $_ } | Select-Object -Last 1).Trim()
    $PROJECT_ARTIFACTID   = ((& mvn help:evaluate '-Dexpression=project.artifactId'   -q '-DforceStdout') | Where-Object { $_ } | Select-Object -Last 1).Trim()
    $PROJECT_VERSION      = ((& mvn help:evaluate '-Dexpression=project.version'      -q '-DforceStdout') | Where-Object { $_ } | Select-Object -Last 1).Trim()    
    Write-Host "[INFO] modelVersion: $PROJECT_MODELVERSION"
    Write-Host "[INFO] groupId: $PROJECT_GROUPID"
    Write-Host "[INFO] artifactId: $PROJECT_ARTIFACTID"
    Write-Host "[INFO] version: $PROJECT_VERSION"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    
# ===== End =====
} while ($false)
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] pom.xml 處理完成'
}
Write-Host
exit $exitCode