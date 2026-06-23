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
    # 檢查檔案
    foreach ($fileName in 'pom.xml') {
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
    foreach ($fileName in 'settings.xml', 'package.txt', 'package-lock.xml', 'package-adding.txt', 'package-missing.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
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
        if ($mavenSource.token) {
            $settingsContent.Add('        <server>')
            $settingsContent.Add("            <id>$($mavenSource.id)</id>")
            if ($mavenSource.username) {
                $settingsContent.Add("            <username>$($mavenSource.username)</username>")
            }
            $settingsContent.Add("            <password>$($mavenSource.token)</password>")
            $settingsContent.Add('        </server>')
        } elseif ($mavenSource.username -and $mavenSource.password) {
            $settingsContent.Add('        <server>')
            $settingsContent.Add("            <id>$($mavenSource.id)</id>")
            $settingsContent.Add("            <username>$($mavenSource.username)</username>")
            $settingsContent.Add("            <password>$($mavenSource.password)</password>")
            $settingsContent.Add('        </server>')
        }
    }
    $settingsContent.Add('    </servers>')
    $settingsContent.Add('    <activeProfiles>')
    $settingsContent.Add('        <activeProfile>default</activeProfile>')
    $settingsContent.Add('    </activeProfiles>')
    $settingsContent.Add('</settings>')
    Set-Content 'settings.xml' -Value $settingsContent -Encoding UTF8

    # 建立 package.txt
    & mvn dependency:list `
        "-DoutputFile=package.txt" `
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
    
    # 讀取 package.txt
    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object { $_ -match '^\s+\S+:\S+:\S+:\S+' } | ForEach-Object {
        ($_ -replace '\s*-- module.*', '').Trim()
    }

    # 整理 package.txt
    $packageContent = $packageList | ForEach-Object {
        $packageParts = $_ -split ':'
        "$($packageParts[0]):$($packageParts[1]):$($packageParts[3])"
    }
    Set-Content 'package.txt' -Value $packageContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package.txt"

    # 建立 package-lock.xml
    $lockContent = [System.Collections.Generic.List[string]]::new()
    $lockContent.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $lockContent.Add('<project xmlns="http://maven.apache.org/POM/4.0.0"')
    $lockContent.Add('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    $lockContent.Add('         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">')
    $lockContent.Add("    <modelVersion>4.0.0</modelVersion>")
    $lockContent.Add('')
    $lockContent.Add("    <groupId>$projectGroupId</groupId>")
    $lockContent.Add("    <artifactId>$projectArtifactId-lock</artifactId>")
    $lockContent.Add("    <version>$projectVersion</version>")
    $lockContent.Add('    <packaging>pom</packaging>')
    $lockContent.Add('')
    $lockContent.Add('    <dependencyManagement>')
    $lockContent.Add('        <dependencies>')
    foreach ($package in $packageList) {
        $packageParts = $package -split ':'
        if ($packageParts.Count -ge 4) {
            $groupId    = $packageParts[0]
            $artifactId = $packageParts[1]
            $type       = $packageParts[2]
            $version    = $packageParts[3]
            $scope      = if ($packageParts.Count -ge 5) { $packageParts[4].Trim() } else { 'compile' }
            $lockContent.Add('            <dependency>')
            $lockContent.Add("                <groupId>$groupId</groupId>")
            $lockContent.Add("                <artifactId>$artifactId</artifactId>")
            $lockContent.Add("                <version>$version</version>")
            if ($type -ne 'jar') {
                $lockContent.Add("                <type>$type</type>")
            }
            if ($scope -ne 'compile') {
                $lockContent.Add("                <scope>$scope</scope>")
            }
            $lockContent.Add('            </dependency>')
        }
    }
    $lockContent.Add('        </dependencies>')
    $lockContent.Add('    </dependencyManagement>')
    $lockContent.Add('</project>')
    Set-Content 'package-lock.xml' -Value $lockContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package-lock.xml"

    # 建立 package-adding.txt
    $addingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $packageParts = $package -split ':'
        if ($packageParts.Count -ge 4) {
            $groupPath  = $packageParts[0] -replace '\.', '/'
            $artifactId = $packageParts[1]
            $packageUrl = "$($mavenRepository.url)/$groupPath/$artifactId/"
            $exists = $false
            try {
                $null = Invoke-WebRequest -Uri $packageUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                $exists = $true
            } catch {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                    $exists = $false
                } else {
                    $exists = $true
                }
            }
            if (-not $exists) {
                $addingList.Add("$($packageParts[0]):$($packageParts[1]):$($packageParts[3])")
            }
        }
    }
    Set-Content 'package-adding.txt' -Value $addingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-adding.txt"

    # 建立 package-missing.txt
    $artifactSpecMap = @{
        'jar'         = @{ ext = 'jar'; classifier = ''        }
        'war'         = @{ ext = 'war'; classifier = ''        }
        'ear'         = @{ ext = 'ear'; classifier = ''        }
        'aar'         = @{ ext = 'aar'; classifier = ''        }
        'rar'         = @{ ext = 'rar'; classifier = ''        }
        'zip'         = @{ ext = 'zip'; classifier = ''        }
        'bundle'      = @{ ext = 'jar'; classifier = ''        }
        'ejb'         = @{ ext = 'jar'; classifier = ''        }
        'hk2-jar'     = @{ ext = 'jar'; classifier = ''        }
        'ejb-client'  = @{ ext = 'jar'; classifier = 'client'  }
        'test-jar'    = @{ ext = 'jar'; classifier = 'tests'   }
        'java-source' = @{ ext = 'jar'; classifier = 'sources' }
        'javadoc'     = @{ ext = 'jar'; classifier = 'javadoc' }
    }
    $missingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $packageParts = $package -split ':'
        if ($packageParts.Count -ge 4) {
            $groupPath  = $packageParts[0] -replace '\.', '/'
            $artifactId = $packageParts[1]
            $type       = $packageParts[2]
            $version    = $packageParts[3]
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

            # 檢查 artifact
            if (-not $isMissing -and $artifactSpecMap.ContainsKey($type)) {
                $spec        = $artifactSpecMap[$type]
                $packageUrl = if ($spec.classifier) { "$baseUrl-$($spec.classifier).$($spec.ext)" } else { "$baseUrl.$($spec.ext)" }
                try {
                    $null = Invoke-WebRequest -Uri $packageUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                } catch {
                    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                        $isMissing = $true
                    }
                }
            }

            if ($isMissing) {
                $missingList.Add("$($packageParts[0]):$($packageParts[1]):$($packageParts[3])")
            }
        }
    }
    Set-Content 'package-missing.txt' -Value $missingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-missing.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除資料夾
    foreach ($directoryPath in './.m2') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'settings.xml') {
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
