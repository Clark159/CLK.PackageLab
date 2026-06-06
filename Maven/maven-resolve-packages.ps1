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
    @{ id = 'central';   url = 'https://repo.maven.apache.org/maven2'  }
    @{ id = 'atlassian'; url = 'https://maven.artifacts.atlassian.com' }
)
$mavenRepository   = @{ id = 'central'; url = 'https://repo.maven.apache.org/maven2' }
do {


    # ===== Require =====
    foreach ($f in 'pom.xml') {
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
    foreach ($f in 'settings.xml', 'packages.txt', 'packages-lock.xml', 'packages-adding.txt', 'packages-missing.txt') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "maven-resolve-packages"
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
    foreach ($source in $mavenSourceList) {
        $settingsContent.Add('                <repository>')
        $settingsContent.Add("                    <id>$($source.id)</id>")
        $settingsContent.Add("                    <url>$($source.url)</url>")
        $settingsContent.Add('                </repository>')
    }
    $settingsContent.Add('            </repositories>')
    $settingsContent.Add('            <pluginRepositories>')
    foreach ($source in $mavenSourceList) {
        $settingsContent.Add('                <pluginRepository>')
        $settingsContent.Add("                    <id>$($source.id)</id>")
        $settingsContent.Add("                    <url>$($source.url)</url>")
        $settingsContent.Add('                </pluginRepository>')
    }
    $settingsContent.Add('            </pluginRepositories>')
    $settingsContent.Add('        </profile>')
    $settingsContent.Add('    </profiles>')
    $settingsContent.Add('    <mirrors>')
    foreach ($source in $mavenSourceList) {
        if ($source.url -notmatch '^http://') { continue }
        $settingsContent.Add('        <mirror>')
        $settingsContent.Add("            <id>$($source.id)</id>")
        $settingsContent.Add("            <mirrorOf>$($source.id)</mirrorOf>")
        $settingsContent.Add("            <url>$($source.url)</url>")
        $settingsContent.Add('        </mirror>')
    }
    $settingsContent.Add('    </mirrors>')
    $settingsContent.Add('    <servers>')
    foreach ($source in $mavenSourceList) {
        if (-not $source.username -or -not $source.password) { continue }
        $settingsContent.Add('        <server>')
        $settingsContent.Add("            <id>$($source.id)</id>")
        $settingsContent.Add("            <username>$($source.username)</username>")
        $settingsContent.Add("            <password>$($source.password)</password>")
        $settingsContent.Add('        </server>')
    }
    $settingsContent.Add('    </servers>')
    $settingsContent.Add('    <activeProfiles>')
    $settingsContent.Add('        <activeProfile>default</activeProfile>')
    $settingsContent.Add('    </activeProfiles>')
    $settingsContent.Add('</settings>')
    Set-Content 'settings.xml' -Value $settingsContent -Encoding UTF8

    # 建立 packages.txt
    & mvn dependency:list `
        "-DoutputFile=packages.txt" `
        "-Dsort=true" `
        "-Dstyle.color=never" `
        "-DappendOutput=false" `
        "-DexcludeTransitive=false" `
        "-s" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:list 執行失敗 (mavenSourceList)"
        $exitCode = 1
        break
    }

    # 整理 packages.txt
    $packagesContent = Get-Content 'packages.txt' -Raw -Encoding UTF8
    $packageList = $packagesContent -split "`n" | Where-Object { $_ -match '^\s+\S+:\S+:\S+:\S+' } |
        ForEach-Object {
            ($_ -replace '\s*-- module.*', '').Trim()
        }
    $packagesContent = $packageList | ForEach-Object {
        $parts = $_ -split ':'
        "$($parts[0]):$($parts[1]):$($parts[3])"
    }
    Set-Content 'packages.txt' -Value $packagesContent -Encoding UTF8
    Write-Host "[INFO] 已建立 packages.txt"

    # 建立 packages-lock.xml
    $bomContent = [System.Collections.Generic.List[string]]::new()
    $bomContent.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $bomContent.Add('<project xmlns="http://maven.apache.org/POM/4.0.0"')
    $bomContent.Add('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    $bomContent.Add('         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">')
    $bomContent.Add("    <modelVersion>4.0.0</modelVersion>")
    $bomContent.Add('')
    $bomContent.Add("    <groupId>$projectGroupId</groupId>")
    $bomContent.Add("    <artifactId>$projectArtifactId-lock</artifactId>")
    $bomContent.Add("    <version>$projectVersion</version>")
    $bomContent.Add('    <packaging>pom</packaging>')
    $bomContent.Add('')
    $bomContent.Add('    <dependencyManagement>')
    $bomContent.Add('        <dependencies>')
    foreach ($package in $packageList) {
        $parts = $package -split ':'
        if ($parts.Count -ge 4) {
            $groupId    = $parts[0]
            $artifactId = $parts[1]
            $type       = $parts[2]
            $version    = $parts[3]
            $scope      = if ($parts.Count -ge 5) { $parts[4].Trim() } else { 'compile' }
            $bomContent.Add('            <dependency>')
            $bomContent.Add("                <groupId>$groupId</groupId>")
            $bomContent.Add("                <artifactId>$artifactId</artifactId>")
            $bomContent.Add("                <version>$version</version>")
            if ($type -ne 'jar') {
                $bomContent.Add("                <type>$type</type>")
            }
            if ($scope -ne 'compile') {
                $bomContent.Add("                <scope>$scope</scope>")
            }
            $bomContent.Add('            </dependency>')
        }
    }
    $bomContent.Add('        </dependencies>')
    $bomContent.Add('    </dependencyManagement>')
    $bomContent.Add('</project>')
    Set-Content 'packages-lock.xml' -Value $bomContent -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-lock.xml"

    # 建立 packages-adding.txt
    $addingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $parts = $package -split ':'
        if ($parts.Count -ge 4) {
            $groupPath  = $parts[0] -replace '\.', '/'
            $artifactId = $parts[1]
            $artifactUrl = "$($mavenRepository.url)/$groupPath/$artifactId/"
            $exists = $false
            try {
                $null = Invoke-WebRequest -Uri $artifactUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                $exists = $true
            } catch {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                    $exists = $false
                } else {
                    $exists = $true
                }
            }
            if (-not $exists) {
                $addingList.Add("$($parts[0]):$($parts[1]):$($parts[3])")
            }
        }
    }
    Set-Content 'packages-adding.txt' -Value $addingList -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-adding.txt"

    # 建立 packages-missing.txt
    $missingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $parts = $package -split ':'
        if ($parts.Count -ge 4) {
            $groupPath  = $parts[0] -replace '\.', '/'
            $artifactId = $parts[1]
            $type       = $parts[2]
            $version    = $parts[3]
            $baseUrl    = "$($mavenRepository.url)/$groupPath/$artifactId/$version/$artifactId-$version"
            $isMissing  = $false

            # 檢查 .pom
            try {
                $null = Invoke-WebRequest -Uri "$baseUrl.pom" -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            } catch {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                    $isMissing = $true
                }
            }

            # 檢查 .jar
            if (-not $isMissing -and $type -eq 'jar') {
                try {
                    $null = Invoke-WebRequest -Uri "$baseUrl.jar" -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                } catch {
                    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                        $isMissing = $true
                    }
                }
            }

            if ($isMissing) {
                $missingList.Add("$($parts[0]):$($parts[1]):$($parts[3])")
            }
        }
    }
    Set-Content 'packages-missing.txt' -Value $missingList -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-missing.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

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
