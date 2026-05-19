param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$mavenSourceList  = @(
    @{ id = 'central';   url = 'https://repo.maven.apache.org/maven2'  }
    @{ id = 'atlassian'; url = 'https://maven.artifacts.atlassian.com' }
)
$mavenSourceProxy = @{ id = 'central'; url = 'https://repo.maven.apache.org/maven2' }
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
    foreach ($src in $mavenSourceList) {
        $settingsContent.Add('                <repository>')
        $settingsContent.Add("                    <id>$($src.id)</id>")
        $settingsContent.Add("                    <url>$($src.url)</url>")
        $settingsContent.Add('                </repository>')
    }
    $settingsContent.Add('            </repositories>')
    $settingsContent.Add('            <pluginRepositories>')
    foreach ($src in $mavenSourceList) {
        $settingsContent.Add('                <pluginRepository>')
        $settingsContent.Add("                    <id>$($src.id)</id>")
        $settingsContent.Add("                    <url>$($src.url)</url>")
        $settingsContent.Add('                </pluginRepository>')
    }
    $settingsContent.Add('            </pluginRepositories>')
    $settingsContent.Add('        </profile>')
    $settingsContent.Add('    </profiles>')
    $settingsContent.Add('    <mirrors>')
    foreach ($src in $mavenSourceList) {
        if ($src.url -notmatch '^http://') { continue }
        $settingsContent.Add('        <mirror>')
        $settingsContent.Add("            <id>$($src.id)</id>")
        $settingsContent.Add("            <mirrorOf>$($src.id)</mirrorOf>")
        $settingsContent.Add("            <url>$($src.url)</url>")
        $settingsContent.Add('        </mirror>')
    }
    $settingsContent.Add('    </mirrors>')
    $settingsContent.Add('    <servers>')
    foreach ($src in $mavenSourceList) {
        if (-not $src.username -or -not $src.password) { continue }
        $settingsContent.Add('        <server>')
        $settingsContent.Add("            <id>$($src.id)</id>")
        $settingsContent.Add("            <username>$($src.username)</username>")
        $settingsContent.Add("            <password>$($src.password)</password>")
        $settingsContent.Add('        </server>')
    }
    $settingsContent.Add('    </servers>')
    $settingsContent.Add('    <activeProfiles>')
    $settingsContent.Add('        <activeProfile>default</activeProfile>')
    $settingsContent.Add('    </activeProfiles>')
    $settingsContent.Add('    <localRepository>./.m2</localRepository>')
    $settingsContent.Add('</settings>')
    Set-Content 'settings.xml' -Value $settingsContent -Encoding UTF8

    # 下載所有套件
    & mvn dependency:go-offline `
        "-s" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:go-offline 執行失敗 (mavenSourceList)"
        $exitCode = 1
        break
    }

    # 建立 settings.xml - mavenSourceProxy
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
    $settingsContent.Add("                    <id>$($mavenSourceProxy.id)</id>")
    $settingsContent.Add("                    <url>$($mavenSourceProxy.url)</url>")
    $settingsContent.Add('                </repository>')
    $settingsContent.Add('            </repositories>')
    $settingsContent.Add('            <pluginRepositories>')
    $settingsContent.Add('                <pluginRepository>')
    $settingsContent.Add("                    <id>$($mavenSourceProxy.id)</id>")
    $settingsContent.Add("                    <url>$($mavenSourceProxy.url)</url>")
    $settingsContent.Add('                </pluginRepository>')
    $settingsContent.Add('            </pluginRepositories>')
    $settingsContent.Add('        </profile>')
    $settingsContent.Add('    </profiles>')
    $settingsContent.Add('    <mirrors>')
    if ($mavenSourceProxy.url -match '^http://') {
        $settingsContent.Add('        <mirror>')
        $settingsContent.Add("            <id>$($mavenSourceProxy.id)</id>")
        $settingsContent.Add("            <mirrorOf>$($mavenSourceProxy.id)</mirrorOf>")
        $settingsContent.Add("            <url>$($mavenSourceProxy.url)</url>")
        $settingsContent.Add('        </mirror>')
    }
    $settingsContent.Add('    </mirrors>')
    $settingsContent.Add('    <servers>')
    if ($mavenSourceProxy.username -and $mavenSourceProxy.password) {
        $settingsContent.Add('        <server>')
        $settingsContent.Add("            <id>$($mavenSourceProxy.id)</id>")
        $settingsContent.Add("            <username>$($mavenSourceProxy.username)</username>")
        $settingsContent.Add("            <password>$($mavenSourceProxy.password)</password>")
        $settingsContent.Add('        </server>')
    }
    $settingsContent.Add('    </servers>')
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
    & mvn dependency:resolve `
        "-s" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:resolve 執行失敗 (mavenSourceProxy)"
        $exitCode = 1
        break
    }

    # 複製目標套件
    $missingList = @()
    foreach ($dependency in $dependencyList) {
        $parts = $dependency -split ':'
        if ($parts.Count -ge 3) {
            $groupId    = $parts[0]
            $artifactId = $parts[1]
            $version    = $parts[2]
            $dependencyPath = "./.m2/$($groupId -replace '\.', '/')/$artifactId/$version"
            if (Test-Path $dependencyPath) {
                $destinationDirectory = "./packages/$($groupId -replace '\.', '/')/$artifactId"
                New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
                Copy-Item -Path $dependencyPath -Destination $destinationDirectory -Recurse -Force
            } else {
                $missingList += $dependency
            }
        }
    }
    if ($missingList.Count -eq 0) {
        $dependencyList | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] 套件下載完成，取得 $($dependencyList.Count) 個套件"
        Write-Host "[INFO] ------------------------------------------------------------------------"
    } else {
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
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