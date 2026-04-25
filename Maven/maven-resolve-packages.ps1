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

    # 產生 BOM XML
    $bomLines = [System.Collections.Generic.List[string]]::new()
    $bomLines.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $bomLines.Add('<project xmlns="http://maven.apache.org/POM/4.0.0"')
    $bomLines.Add('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    $bomLines.Add('         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">')
    $bomLines.Add('')
    $bomLines.Add("    <modelVersion>$PROJECT_MODELVERSION</modelVersion>")
    $bomLines.Add("    <groupId>$PROJECT_GROUPID</groupId>")
    $bomLines.Add("    <artifactId>$PROJECT_ARTIFACTID</artifactId>")
    $bomLines.Add("    <version>$PROJECT_VERSION</version>")
    $bomLines.Add('    <packaging>pom</packaging>')
    $bomLines.Add('')

    $bomLines.Add('    <dependencyManagement>')
    $bomLines.Add('        <dependencies>')
    foreach ($depLine in $packagesLockString) {
        $parts = $depLine -split ':'
        if ($parts.Count -ge 4) {
            $depGroupId    = $parts[0]
            $depArtifactId = $parts[1]
            $depType       = $parts[2]
            $depVersion    = $parts[3]
            $depScope      = if ($parts.Count -ge 5) { $parts[4].Trim() } else { 'compile' }
            $bomLines.Add('            <dependency>')
            $bomLines.Add("                <groupId>$depGroupId</groupId>")
            $bomLines.Add("                <artifactId>$depArtifactId</artifactId>")
            $bomLines.Add("                <version>$depVersion</version>")
            if ($depType -ne 'jar') { 
                $bomLines.Add("                <type>$depType</type>") 
            }
            if ($depScope -ne 'compile') { 
                $bomLines.Add("                <scope>$depScope</scope>") 
            }
            $bomLines.Add('            </dependency>')
        }
    }
    $bomLines.Add('        </dependencies>')
    $bomLines.Add('    </dependencyManagement>')

    $bomLines.Add('</project>')
    $bomLines | Set-Content 'packages-lock.xml' -Encoding UTF8
    Write-Host "[INFO] 已產生 packages-lock.xml"
    Write-Host "[INFO] ------------------------------------------------------------------------"


# ===== End =====
} while ($false)
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] pom.xml 處理完成'
}
Write-Host
exit $exitCode