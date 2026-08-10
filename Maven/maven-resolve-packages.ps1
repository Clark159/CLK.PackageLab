param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$scriptVersion = '20260806-00'
$exitCode = 0
$projectGroupId    = 'com.example'
$projectArtifactId = 'packages'
$projectVersion    = '1.0.0'
$mavenSourceList   = @(
    @{ id = 'central'; url = 'https://repo.maven.apache.org/maven2/' }
    @{ id = 'atlassian'; url = 'https://maven.artifacts.atlassian.com/' }
)
$mavenRepository   = @{ id = 'central'; url = 'https://repo.maven.apache.org/maven2/' }
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
    foreach ($fileName in 'settings.xml', 'package-lock.xml', 'package-all.txt', 'package-adding.txt', 'package-updating.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }

    # 整併 mavenRepository 至 mavenSourceList
    if (-not ($mavenSourceList | Where-Object { $_.url -eq $mavenRepository.url })) {

        # mavenSourceId
        $suffix = 2
        $mavenSourceId = $mavenRepository.id        
        while ($mavenSourceList | Where-Object { $_.id -eq $mavenSourceId }) {
            $mavenSourceId = "$($mavenRepository.id)$suffix"
            $suffix++
        }

        # mavenSource
        $mavenSource = $mavenRepository.Clone()
        $mavenSource.id = $mavenSourceId
        $mavenSourceList += $mavenSource
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
    $settingsContent.Add('    <localRepository>./.m2</localRepository>')
    $settingsContent.Add('</settings>')
    Set-Content 'settings.xml' -Value $settingsContent -Encoding UTF8

    # 建立 package-all.txt (專案依賴)
    & mvn dependency:list `
        "-DoutputFile=$PSScriptRoot/package-all.txt" `
        "-Dsort=true" `
        "-Dstyle.color=never" `
        "-DappendOutput=true" `
        "-DexcludeTransitive=false" `
        "-s" "settings.xml" `
        "-gs" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:list 執行失敗 (mavenSourceList)"
        $exitCode = 1
        break
    }

    # 建立 package-all.txt (編譯依賴)
    & mvn dependency:resolve-plugins `
        "-DoutputFile=$PSScriptRoot/package-all.txt" `
        "-Dsort=true" `
        "-Dstyle.color=never" `
        "-DappendOutput=true" `
        "-DexcludeTransitive=false" `
        "-s" "settings.xml" `
        "-gs" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:resolve-plugins 執行失敗 (mavenSourceList)"
        $exitCode = 1
        break
    }

    # 建立 package-all.txt (下載依賴)
    $repositoryFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot '.m2') -Recurse -File -Include '*.pom', '*.jar' -ErrorAction SilentlyContinue
    $repositoryList = foreach ($repositoryFile in $repositoryFiles) {
        $relativePath = $repositoryFile.FullName.Substring((Join-Path $PSScriptRoot '.m2').Length).TrimStart('\', '/')
        $pathSegments = $relativePath -split '[\\/]'
        if ($pathSegments.Count -lt 4) { continue }
        $version    = $pathSegments[$pathSegments.Count - 2]
        $artifactId = $pathSegments[$pathSegments.Count - 3]
        $groupId    = ($pathSegments[0..($pathSegments.Count - 4)] -join '.')
        $packaging  = $repositoryFile.Extension.TrimStart('.')
        $namePrefix = "$artifactId-$version"
        if ($repositoryFile.BaseName -eq $namePrefix) {
            "    $($groupId):$($artifactId):$($packaging):$($version):compile"
        } elseif ($repositoryFile.BaseName.StartsWith("$namePrefix-")) {
            $classifier = $repositoryFile.BaseName.Substring($namePrefix.Length + 1)
            "    $($groupId):$($artifactId):$($packaging):$($classifier):$($version):compile"
        } else {
            continue
        }
    }
    Add-Content 'package-all.txt' -Value $repositoryList -Encoding UTF8
    Write-Host
    Write-Host
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 讀取 package-all.txt
    $mavenScopeList = 'compile', 'provided', 'runtime', 'test', 'system', 'import'
    $allList = Get-Content 'package-all.txt' -Encoding UTF8 | Where-Object { $_ -match '^\s+\S+:\S+:\S+:\S+' } | ForEach-Object {
        $packageParts = ($_ -replace '\s*-- module.*', '' -replace '\s*\(optional\)\s*', '').Trim() -split ':'
        if ($packageParts.Count -ge 6) {
            [PSCustomObject]@{
                GroupId    = $packageParts[0]
                ArtifactId = $packageParts[1]
                Packaging  = $packageParts[2]
                Classifier = $packageParts[3]
                Version    = $packageParts[4]
                Scope      = $packageParts[5]
            }
        } elseif ($packageParts.Count -eq 5 -and $packageParts[4] -notin $mavenScopeList) {
            [PSCustomObject]@{
                GroupId    = $packageParts[0]
                ArtifactId = $packageParts[1]
                Packaging  = $packageParts[2]
                Classifier = $packageParts[3]
                Version    = $packageParts[4]
                Scope      = 'compile'
            }
        } else {
            [PSCustomObject]@{
                GroupId    = $packageParts[0]
                ArtifactId = $packageParts[1]
                Packaging  = $packageParts[2]
                Classifier = ''
                Version    = $packageParts[3]
                Scope      = if ($packageParts.Count -ge 5) { $packageParts[4] } else { 'compile' }
            }
        }
    }

    # 整理 package-all.txt (合併重複，移除type為maven-plugin)
    foreach ($package in $allList) {
        if ($package.Packaging -eq 'maven-plugin') {
            $package.Packaging = 'jar'
        }
    }

    # 整理 package-all.txt (合併重複，移除有jar的pom)
    $jarPackageList = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($package in $allList) {
        if ($package.Packaging -eq 'jar') {
            [void]$jarPackageList.Add("$($package.GroupId):$($package.ArtifactId):$($package.Version)")
        }
    }
    $allList = $allList | Where-Object {
        -not ($_.Packaging -eq 'pom' -and $jarPackageList.Contains("$($_.GroupId):$($_.ArtifactId):$($_.Version)"))
    }

    # 整理 package-all.txt (合併重複，保留第一筆)
    $allList = $allList | Group-Object GroupId, ArtifactId, Packaging, Classifier | ForEach-Object {
        $_.Group[0]
    }

    # 整理 package-all.txt (輸出檔案)
    $packageContent = $allList | Sort-Object GroupId, ArtifactId, Packaging, Classifier, Version, Scope | ForEach-Object {
        if ($_.Classifier) {
            "$($_.GroupId):$($_.ArtifactId):$($_.Packaging):$($_.Classifier):$($_.Version):$($_.Scope)"
        } else {
            "$($_.GroupId):$($_.ArtifactId):$($_.Packaging):$($_.Version):$($_.Scope)"
        }
    }
    Set-Content 'package-all.txt' -Value $packageContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package-all.txt"

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
    foreach ($package in $allList) {
        $lockContent.Add('            <dependency>')
        $lockContent.Add("                <groupId>$($package.GroupId)</groupId>")
        $lockContent.Add("                <artifactId>$($package.ArtifactId)</artifactId>")
        $lockContent.Add("                <version>$($package.Version)</version>")
        if ($package.Packaging -ne 'jar') {
            $lockContent.Add("                <type>$($package.Packaging)</type>")
        }
        if ($package.Classifier) {
            $lockContent.Add("                <classifier>$($package.Classifier)</classifier>")
        }
        if ($package.Scope -ne 'compile') {
            $lockContent.Add("                <scope>$($package.Scope)</scope>")
        }
        $lockContent.Add('            </dependency>')
    }
    $lockContent.Add('        </dependencies>')
    $lockContent.Add('    </dependencyManagement>')
    $lockContent.Add('</project>')
    Set-Content 'package-lock.xml' -Value $lockContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package-lock.xml"

    # 建立 package-adding.txt
    $addingList = [System.Collections.Generic.List[object]]::new()
    foreach ($package in $allList) {
        $groupPath  = $package.GroupId -replace '\.', '/'
        $artifactId = $package.ArtifactId
        $packageUrl = "$($mavenRepository.url.TrimEnd('/'))/$groupPath/$artifactId/"
        $isAdding = $true
        try {
            $null = Invoke-WebRequest -Uri $packageUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $isAdding = $false
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $isAdding = $true
            } else {
                $isAdding = $false
            }
        }
        if ($isAdding) {
            $addingList.Add($package)
        }
    }
    $addingContent = $addingList | ForEach-Object {
        if ($_.Classifier) {
            "$($_.GroupId):$($_.ArtifactId):$($_.Packaging):$($_.Classifier):$($_.Version):$($_.Scope)"
        } else {
            "$($_.GroupId):$($_.ArtifactId):$($_.Packaging):$($_.Version):$($_.Scope)"
        }
    }
    Set-Content 'package-adding.txt' -Value $addingContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package-adding.txt"

    # 建立 package-updating.txt 
    $artifactSpecMap = @{
        'pom'         = @{ ext = 'pom'; classifier = ''        }
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
    $updatingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $allList) {
        $groupPath  = $package.GroupId -replace '\.', '/'
        $artifactId = $package.ArtifactId
        $type       = $package.Packaging
        $version    = $package.Version
        $ext        = if ($artifactSpecMap.ContainsKey($type)) { $artifactSpecMap[$type].ext } else { 'jar' }
        $classifier = if ($package.Classifier) { $package.Classifier } elseif ($artifactSpecMap.ContainsKey($type)) { $artifactSpecMap[$type].classifier } else { '' }
        $packageUrl = if ($classifier) { "$($mavenRepository.url.TrimEnd('/'))/$groupPath/$artifactId/$version/$artifactId-$version-$classifier.$ext" } else { "$($mavenRepository.url.TrimEnd('/'))/$groupPath/$artifactId/$version/$artifactId-$version.$ext" }
        $isUpdating = $false
        try {
            $null = Invoke-WebRequest -Uri $packageUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $isUpdating = $true
            }
        }
        $isAdding = $addingList | Where-Object { $_.GroupId -eq $package.GroupId -and $_.ArtifactId -eq $package.ArtifactId }
        if ($isUpdating -and -not $isAdding) {
            $updatingList.Add($(if ($package.Classifier) {
                "$($package.GroupId):$($package.ArtifactId):$($package.Packaging):$($package.Classifier):$($package.Version):$($package.Scope)"
            } else {
                "$($package.GroupId):$($package.ArtifactId):$($package.Packaging):$($package.Version):$($package.Scope)"
            }))
        }
    }
    Set-Content 'package-updating.txt' -Value $updatingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-updating.txt"
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

Write-Host "[VERSION] $scriptVersion"
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] 所有作業已完成'
}
if ($Pause) {
    Write-Host
    Write-Host '按任意鍵繼續...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
exit $exitCode