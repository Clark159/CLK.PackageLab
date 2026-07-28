param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$projectGroupId    = 'com.example'
$projectArtifactId = 'packages'
$projectVersion    = '1.0.0'
$mavenSourceList   = @(
    @{ id = 'central'; url = 'https://repo.maven.apache.org/maven2/'; username = ''; token = '' }
    @{ id = 'atlassian'; url = 'https://maven.artifacts.atlassian.com/'; username = ''; token = '' }
)
$mavenRepository   = @{ id = 'central'; url = 'https://repo.maven.apache.org/maven2/'; username = ''; token = '' }

# 依 mvn dependency:list 慣例組座標字串：無 classifier 為 5 欄，有 classifier 才補上該欄 (不輸出 ::)
function Format-PackageCoordinate {
    param($Package)
    if ($Package.Classifier) {
        "$($Package.GroupId):$($Package.ArtifactId):$($Package.Packaging):$($Package.Classifier):$($Package.Version):$($Package.Scope)"
    } else {
        "$($Package.GroupId):$($Package.ArtifactId):$($Package.Packaging):$($Package.Version):$($Package.Scope)"
    }
}
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

    # 檢查資料夾
    $folderName = Split-Path $PSScriptRoot -Leaf
    if ($folderName -match '^\d{12}-\d{2}$') {
        $mavenRepository.url = "$($mavenRepository.url.TrimEnd('/'))/$folderName-AP/"
    }

    # 移除資料夾
    foreach ($directoryPath in './.m2', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'settings.xml', 'pom.xml', 'package-lock.xml', 'package-adding.txt', 'package-updating.txt') {
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
        if ($mavenSource.username -and $mavenSource.token) {
            $settingsContent.Add('        <server>')
            $settingsContent.Add("            <id>$($mavenSource.id)</id>")
            $settingsContent.Add("            <username>$($mavenSource.username)</username>")
            $settingsContent.Add("            <password>$($mavenSource.token)</password>")
            $settingsContent.Add('        </server>')
        }
    }
    $settingsContent.Add('    </servers>')
    $settingsContent.Add('    <activeProfiles>')
    $settingsContent.Add('        <activeProfile>default</activeProfile>')
    $settingsContent.Add('    </activeProfiles>')
    $settingsContent.Add('    <localRepository>./.m2</localRepository>')
    $settingsContent.Add('</settings>')
    Set-Content 'settings.xml' -Value $settingsContent -Encoding UTF8

    # 讀取 package.txt (groupId:artifactId:version 或 groupId:artifactId:packaging:version:scope 或 groupId:artifactId:packaging:classifier:version:scope)
    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object {
        $_.Trim() -ne ''
    } | ForEach-Object {
        $packageParts = $_.Trim() -split ':'
        if ($packageParts.Count -ge 6) {
            [PSCustomObject]@{
                GroupId    = $packageParts[0]
                ArtifactId = $packageParts[1]
                Packaging  = $packageParts[2]
                Classifier = $packageParts[3]
                Version    = $packageParts[4]
                Scope      = $packageParts[5]
            }
        } elseif ($packageParts.Count -eq 5) {
            [PSCustomObject]@{
                GroupId    = $packageParts[0]
                ArtifactId = $packageParts[1]
                Packaging  = $packageParts[2]
                Classifier = ''
                Version    = $packageParts[3]
                Scope      = $packageParts[4]
            }
        } else {
            [PSCustomObject]@{
                GroupId    = $packageParts[0]
                ArtifactId = $packageParts[1]
                Packaging  = 'jar'
                Classifier = ''
                Version    = $packageParts[2]
                Scope      = 'compile'
            }
        }
    }

    # 產生 pom.xml
    $pomContent = [System.Collections.Generic.List[string]]::new()
    $pomContent.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $pomContent.Add('<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">')
    $pomContent.Add('    <modelVersion>4.0.0</modelVersion>')
    $pomContent.Add("    <groupId>$projectGroupId</groupId>")
    $pomContent.Add("    <artifactId>$projectArtifactId</artifactId>")
    $pomContent.Add("    <version>$projectVersion</version>")
    $pomContent.Add('    <packaging>pom</packaging>')
    $pomContent.Add('    <dependencies>')
    foreach ($package in $packageList) {
        $pomContent.Add('        <dependency>')
        $pomContent.Add("            <groupId>$($package.GroupId)</groupId>")
        $pomContent.Add("            <artifactId>$($package.ArtifactId)</artifactId>")
        $pomContent.Add("            <version>$($package.Version)</version>")
        if ($package.Packaging -ne 'jar') {
            $pomContent.Add("            <type>$($package.Packaging)</type>")
        }
        if ($package.Classifier) {
            $pomContent.Add("            <classifier>$($package.Classifier)</classifier>")
        }
        if ($package.Scope -ne 'compile') {
            $pomContent.Add("            <scope>$($package.Scope)</scope>")
        }
        $pomContent.Add('        </dependency>')
    }
    $pomContent.Add('    </dependencies>')
    $pomContent.Add('</project>')
    Set-Content 'pom.xml' -Value $pomContent -Encoding UTF8

    # 下載所有套件
    & mvn dependency:go-offline `
        "-f" "pom.xml" `
        "-s" "settings.xml" `
        "-gs" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:go-offline 執行失敗 (mavenSourceList)"
        $exitCode = 1
        break
    }

    # 建立 settings.xml - mavenRepository
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
    $settingsContent.Add("                    <id>$($mavenRepository.id)</id>")
    $settingsContent.Add("                    <url>$($mavenRepository.url)</url>")
    $settingsContent.Add('                </repository>')
    $settingsContent.Add('            </repositories>')
    $settingsContent.Add('            <pluginRepositories>')
    $settingsContent.Add('                <pluginRepository>')
    $settingsContent.Add("                    <id>$($mavenRepository.id)</id>")
    $settingsContent.Add("                    <url>$($mavenRepository.url)</url>")
    $settingsContent.Add('                </pluginRepository>')
    $settingsContent.Add('            </pluginRepositories>')
    $settingsContent.Add('        </profile>')
    $settingsContent.Add('    </profiles>')
    $settingsContent.Add('    <mirrors>')
    if ($mavenRepository.url -match '^http://') {
        $settingsContent.Add('        <mirror>')
        $settingsContent.Add("            <id>$($mavenRepository.id)</id>")
        $settingsContent.Add("            <mirrorOf>$($mavenRepository.id)</mirrorOf>")
        $settingsContent.Add("            <url>$($mavenRepository.url)</url>")
        $settingsContent.Add('        </mirror>')
    }
    $settingsContent.Add('    </mirrors>')
    $settingsContent.Add('    <servers>')
    if ($mavenRepository.username -and $mavenRepository.token) {
        $settingsContent.Add('        <server>')
        $settingsContent.Add("            <id>$($mavenRepository.id)</id>")
        $settingsContent.Add("            <username>$($mavenRepository.username)</username>")
        $settingsContent.Add("            <password>$($mavenRepository.token)</password>")
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
        $packagePath = "./.m2/$($package.GroupId -replace '\.', '/')/$($package.ArtifactId)/$($package.Version)"
        if (Test-Path $packagePath) {
            Remove-Item -Path $packagePath -Recurse -Force
        }
    }

    # 下載目標套件
    & mvn dependency:resolve `
        "-f" "pom.xml" `
        "-s" "settings.xml" `
        "-gs" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:resolve 執行失敗 (mavenRepository)"
        $exitCode = 1
        break
    }

    # 複製目標套件
    $missingList = @()
    foreach ($package in $packageList) {
        $packagePath = "./.m2/$($package.GroupId -replace '\.', '/')/$($package.ArtifactId)/$($package.Version)"
        if (Test-Path $packagePath) {
            $destinationDirectory = "./packages/$($package.GroupId -replace '\.', '/')/$($package.ArtifactId)"
            New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
            Copy-Item -Path $packagePath -Destination $destinationDirectory -Recurse -Force
        } else {
            $missingList += $package
        }
    }
    Get-ChildItem -Path './packages' -Recurse -Filter '_remote.repositories' | Remove-Item -Force

    # 顯示下載結果
    if ($missingList.Count -eq 0) {
        Write-Host
        Write-Host
        Write-Host "[INFO] ------------------------------------------------------------------------"
        $packageList | ForEach-Object { Write-Host "[INFO] $(Format-PackageCoordinate $_)" }
        Write-Host "[INFO] 套件下載完成，取得 $($packageList.Count) 個套件"
        Write-Host "[INFO] ------------------------------------------------------------------------"
    } else {
        Write-Host
        Write-Host
        Write-Host "[INFO] ------------------------------------------------------------------------"
        $missingList | ForEach-Object { Write-Host "[ERROR] $(Format-PackageCoordinate $_)" }
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
    foreach ($fileName in 'settings.xml', 'pom.xml') {
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