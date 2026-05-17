param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$mavenSourceList  = @('https://repo.maven.apache.org/maven2', 'https://maven.google.com')
$mavenSourceProxyUrl  = 'https://repo.maven.apache.org/maven2'
do {


    # ===== Require =====
    # 檢查參數
    $ticketNumber = Split-Path -Leaf (Get-Location)
    #if ($ticketNumber -notmatch '^\d{12}-\d{2}$') {
    #    Write-Host "[ERROR] 資料夾名稱必須為需求單號"
    #    $exitCode = 1
    #    break
    #}
    #$mavenSourceProxyUrl = "$mavenSourceProxyUrl/$ticketNumber"

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

    # 移除檔案
    foreach ($f in 'settings.xml') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }  


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "maven-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 settings.xml - mavenSourceList
    $settingsContent = [System.Collections.Generic.List[string]]::new()
    $settingsContent.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $settingsContent.Add('<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"')
    $settingsContent.Add('          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    $settingsContent.Add('          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">')
    $settingsContent.Add('    <profiles>')
    $settingsContent.Add('        <profile>')
    $settingsContent.Add('            <id>default</id>')
    $settingsContent.Add('            <repositories>')
    for ($i = 0; $i -lt $mavenSourceList.Count; $i++) {
        $settingsContent.Add('                <repository>')
        if ($i -eq 0) { $settingsContent.Add('                    <id>central</id>') }
        if ($i -ne 0) { $settingsContent.Add("                    <id>central-$i</id>") }
        $settingsContent.Add("                    <url>$($mavenSourceList[$i])</url>")
        $settingsContent.Add('                </repository>')
    }
    $settingsContent.Add('            </repositories>')
    $settingsContent.Add('            <pluginRepositories>')
    for ($i = 0; $i -lt $mavenSourceList.Count; $i++) {
        $settingsContent.Add('                <pluginRepository>')
        if ($i -eq 0) { $settingsContent.Add('                    <id>central</id>') }
        if ($i -ne 0) { $settingsContent.Add("                    <id>central-$i</id>") }
        $settingsContent.Add("                    <url>$($mavenSourceList[$i])</url>")
        $settingsContent.Add('                </pluginRepository>')
    }
    $settingsContent.Add('            </pluginRepositories>')
    $settingsContent.Add('        </profile>')
    $settingsContent.Add('    </profiles>')
    $settingsContent.Add('    <activeProfiles>')
    $settingsContent.Add('        <activeProfile>default</activeProfile>')
    $settingsContent.Add('    </activeProfiles>')
    $settingsContent.Add('    <localRepository>./.m2</localRepository>')
    $settingsContent.Add('</settings>')
    Set-Content 'settings.xml' -Value $settingsContent -Encoding UTF8

    # 下載所有套件
    mvn dependency:go-offline `
        "-s" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:go-offline 執行失敗 (mavenSourceList)"
        $exitCode = 1
        break
    }

    # 建立 settings.xml - mavenSourceProxyUrl
    $settingsContent = [System.Collections.Generic.List[string]]::new()
    $settingsContent.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $settingsContent.Add('<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"')
    $settingsContent.Add('          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    $settingsContent.Add('          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">')
    $settingsContent.Add('    <profiles>')
    $settingsContent.Add('        <profile>')
    $settingsContent.Add('            <id>default</id>')
    $settingsContent.Add('            <repositories>')
    $settingsContent.Add('                <repository>')
    $settingsContent.Add('                    <id>central</id>')
    $settingsContent.Add("                    <url>$mavenSourceProxyUrl</url>")
    $settingsContent.Add('                </repository>')
    $settingsContent.Add('            </repositories>')
    $settingsContent.Add('            <pluginRepositories>')
    $settingsContent.Add('                <pluginRepository>')
    $settingsContent.Add('                    <id>central</id>')
    $settingsContent.Add("                    <url>$mavenSourceProxyUrl</url>")
    $settingsContent.Add('                </pluginRepository>')
    $settingsContent.Add('            </pluginRepositories>')
    $settingsContent.Add('        </profile>')
    $settingsContent.Add('    </profiles>')
    $settingsContent.Add('    <activeProfiles>')
    $settingsContent.Add('        <activeProfile>default</activeProfile>')
    $settingsContent.Add('    </activeProfiles>')
    $settingsContent.Add('    <localRepository>./.m2</localRepository>')
    $settingsContent.Add('</settings>')
    Set-Content 'settings.xml' -Value $settingsContent -Encoding UTF8

    # 刪除目標套件
    $dependencyList = Get-Content 'packages-lock.txt' -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }
    foreach ($dependency in $dependencyList) {
        $parts = $dependency -split ':'
        if ($parts.Count -ge 3) {
            $groupId    = $parts[0]
            $artifactId = $parts[1]
            $version    = $parts[2]
            $dependencyPath = "./.m2/$($groupId -replace '\.', '/')/$artifactId/$version"
            if (Test-Path $dependencyPath) {
                Remove-Item -Path $dependencyPath -Recurse -Force
            }
        }
    }

    # 下載目標套件
    mvn dependency:resolve `
        "-s" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:resolve 執行失敗 (mavenSourceProxyUrl)"
        $exitCode = 1
        break
    }

    # 比對套件清單
    $missingList = @()
    foreach ($dependency in $dependencyList) {
        $parts = $dependency -split ':'
        if ($parts.Count -ge 3) {
            $groupId    = $parts[0]
            $artifactId = $parts[1]
            $version    = $parts[2]
            $groupPath  = $groupId -replace '\.', '/'
            $dependencyPath    = "./.m2/$groupPath/$artifactId/$version/$artifactId-$version.jar"
            if (-not (Test-Path $dependencyPath)) {
                $missingList += $dependency
            }
        }
    }
    if ($missingList.Count -gt 0) {
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] ------------------------------------------------------------------------"
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

    # 移除檔案
    foreach ($f in 'settings.xml') {
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