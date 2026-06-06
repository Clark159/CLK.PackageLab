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
    foreach ($fileName in 'package.txt') {
        if (-not (Test-Path $fileName)) {
            Write-Host "[ERROR] 找不到 $fileName"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($directoryPath in './.m2', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'settings.xml', 'pom-temp.xml') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
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
    foreach ($mavenSource in $mavenSourceList) {
        $settingsContent.Add('                <repository>')
        $settingsContent.Add("                    <id>$($mavenSource.id)</id>")
        $settingsContent.Add("                    <url>$($mavenSource.url)</url>")
        $settingsContent.Add('                </repository>')
    }
    $settingsContent.Add('            </repositories>')
    $settingsContent.Add('            <pluginRepositories>')
    foreach ($mavenSource in $mavenSourceList) {
        $settingsContent.Add('                <pluginRepository>')
        $settingsContent.Add("                    <id>$($mavenSource.id)</id>")
        $settingsContent.Add("                    <url>$($mavenSource.url)</url>")
        $settingsContent.Add('                </pluginRepository>')
    }
    $settingsContent.Add('            </pluginRepositories>')
    $settingsContent.Add('        </profile>')
    $settingsContent.Add('    </profiles>')
    $settingsContent.Add('    <mirrors>')
    foreach ($mavenSource in $mavenSourceList) {
        if ($mavenSource.url -notmatch '^http://') { continue }
        $settingsContent.Add('        <mirror>')
        $settingsContent.Add("            <id>$($mavenSource.id)</id>")
        $settingsContent.Add("            <mirrorOf>$($mavenSource.id)</mirrorOf>")
        $settingsContent.Add("            <url>$($mavenSource.url)</url>")
        $settingsContent.Add('        </mirror>')
    }
    $settingsContent.Add('    </mirrors>')
    $settingsContent.Add('    <servers>')
    foreach ($mavenSource in $mavenSourceList) {
        if (-not $mavenSource.username -or -not $mavenSource.password) { continue }
        $settingsContent.Add('        <server>')
        $settingsContent.Add("            <id>$($mavenSource.id)</id>")
        $settingsContent.Add("            <username>$($mavenSource.username)</username>")
        $settingsContent.Add("            <password>$($mavenSource.password)</password>")
        $settingsContent.Add('        </server>')
    }
    $settingsContent.Add('    </servers>')
    $settingsContent.Add('    <activeProfiles>')
    $settingsContent.Add('        <activeProfile>default</activeProfile>')
    $settingsContent.Add('    </activeProfiles>')
    $settingsContent.Add('    <localRepository>./.m2</localRepository>')
    $settingsContent.Add('</settings>')
    Set-Content 'settings.xml' -Value $settingsContent -Encoding UTF8

    # 讀取 package.txt
    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object {
        $_.Trim() -ne '' 
    }

    # 產生 pom-temp.xml
    $pomContent = [System.Collections.Generic.List[string]]::new()
    $pomContent.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $pomContent.Add('<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">')
    $pomContent.Add('    <modelVersion>4.0.0</modelVersion>')
    $pomContent.Add('    <groupId>com.example</groupId>')
    $pomContent.Add('    <artifactId>packages</artifactId>')
    $pomContent.Add('    <version>1.0.0</version>')
    $pomContent.Add('    <packaging>pom</packaging>')
    $pomContent.Add('    <dependencies>')
    foreach ($package in $packageList) {
        $packageParts = $package -split ':'
        if ($packageParts.Count -ge 3) {
            $pomContent.Add('        <dependency>')
            $pomContent.Add("            <groupId>$($packageParts[0])</groupId>")
            $pomContent.Add("            <artifactId>$($packageParts[1])</artifactId>")
            $pomContent.Add("            <version>$($packageParts[2])</version>")
            $pomContent.Add('        </dependency>')
        }
    }
    $pomContent.Add('    </dependencies>')
    $pomContent.Add('</project>')
    Set-Content 'pom-temp.xml' -Value $pomContent -Encoding UTF8

    # 下載所有套件
    & mvn dependency:go-offline `
        "-f" "pom-temp.xml" `
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
    foreach ($package in $packageList) {
        $packageParts = $package -split ':'
        if ($packageParts.Count -ge 3) {
            $groupId    = $packageParts[0]
            $artifactId = $packageParts[1]
            $version    = $packageParts[2]
            $packagePath = "./.m2/$($groupId -replace '\.', '/')/$artifactId/$version"
            if (Test-Path $packagePath) {
                Remove-Item -Path $packagePath -Recurse -Force
            }
        }
    }

    # 下載目標套件
    & mvn dependency:resolve `
        "-f" "pom-temp.xml" `
        "-s" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:resolve 執行失敗 (mavenSourceProxy)"
        $exitCode = 1
        break
    }

    # 複製目標套件
    $missingList = @()
    foreach ($package in $packageList) {
        $packageParts = $package -split ':'
        if ($packageParts.Count -ge 3) {
            $groupId    = $packageParts[0]
            $artifactId = $packageParts[1]
            $version    = $packageParts[2]
            $packagePath = "./.m2/$($groupId -replace '\.', '/')/$artifactId/$version"
            if (Test-Path $packagePath) {
                $destinationDirectory = "./packages/$($groupId -replace '\.', '/')/$artifactId"
                New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
                Copy-Item -Path $packagePath -Destination $destinationDirectory -Recurse -Force
            } else {
                $missingList += $package
            }
        }
    }
    Get-ChildItem -Path './packages' -Recurse -Filter '_remote.repositories' | Remove-Item -Force

    if ($missingList.Count -eq 0) {
        $packageList | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] 套件下載完成，取得 $($packageList.Count) 個套件"
        Write-Host "[INFO] ------------------------------------------------------------------------"
    } else {
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
    }

    # 移除資料夾
    foreach ($directoryPath in './.m2') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'settings.xml', 'pom-temp.xml') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
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