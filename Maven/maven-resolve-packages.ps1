param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$projectGroupId      = 'com.example'
$projectArtifactId   = 'packages'
$projectVersion      = '1.0.0'
$mavenCentralUrl = 'https://repo.maven.apache.org/maven2'
$xmlWriterSettings = [System.Xml.XmlWriterSettings]@{ Indent = $true; Encoding = [System.Text.UTF8Encoding]::new($false); IndentChars = '    '; }
do {


    # ===== Require =====    
    # 檢查檔案
    foreach ($f in 'packages.txt') {
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
    foreach ($f in 'pom.xml', 'settings.xml', 'packages-lock.txt', 'packages-lock.xml') {
        if (Test-Path $f) {
            Remove-Item $f -Force
        }
    }    


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "maven-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 pom.xml
    $packageList = Get-Content 'packages.txt' -Encoding UTF8 | Where-Object { $_ -match '\S' }
    $pomContent = [System.Collections.Generic.List[string]]::new()
    $pomContent.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $pomContent.Add('<project xmlns="http://maven.apache.org/POM/4.0.0"')
    $pomContent.Add('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    $pomContent.Add('         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">')
    $pomContent.Add("    <modelVersion>4.0.0</modelVersion>")
    $pomContent.Add('')
    $pomContent.Add("    <groupId>$projectGroupId</groupId>")
    $pomContent.Add("    <artifactId>$projectArtifactId</artifactId>")
    $pomContent.Add("    <version>$projectVersion</version>")
    $pomContent.Add('    <packaging>pom</packaging>')
    $pomContent.Add('')
    $pomContent.Add('    <dependencies>')
    foreach ($package in $packageList) {
        $parts = $package -split ':'
        if ($parts.Count -ge 3) {
            $packageGroupId    = $parts[0]
            $packageArtifactId = $parts[1]
            $packageVersion    = $parts[2]
            $pomContent.Add('        <dependency>')
            $pomContent.Add("            <groupId>$packageGroupId</groupId>")
            $pomContent.Add("            <artifactId>$packageArtifactId</artifactId>")
            $pomContent.Add("            <version>$packageVersion</version>")
            $pomContent.Add('        </dependency>')
        }
    }
    $pomContent.Add('    </dependencies>')
    $pomContent.Add('</project>')
    $pomContent | Set-Content 'pom.xml' -Encoding UTF8

    # 建立 settings.xml
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
    $settingsContent.Add('                    <id>default</id>')
    $settingsContent.Add("                    <url>$mavenCentralUrl</url>")
    $settingsContent.Add('                    <releases><enabled>true</enabled></releases>')
    $settingsContent.Add('                    <snapshots><enabled>false</enabled></snapshots>')
    $settingsContent.Add('                </repository>')
    $settingsContent.Add('                <repository>')
    $settingsContent.Add('                    <id>central</id>')
    $settingsContent.Add('                    <url>https://repo.maven.apache.org/maven2</url>')
    $settingsContent.Add('                    <releases><enabled>false</enabled></releases>')
    $settingsContent.Add('                    <snapshots><enabled>false</enabled></snapshots>')
    $settingsContent.Add('                </repository>')
    $settingsContent.Add('            </repositories>')
    $settingsContent.Add('        </profile>')
    $settingsContent.Add('    </profiles>')
    $settingsContent.Add('    <activeProfiles>')
    $settingsContent.Add('        <activeProfile>default</activeProfile>')
    $settingsContent.Add('    </activeProfiles>')
    $settingsContent.Add('    <localRepository>./.m2</localRepository>')
    $settingsContent.Add('</settings>')
    $settingsContent | Set-Content 'settings.xml' -Encoding UTF8

    # 解析套件清單
    & mvn dependency:list `
        "-DoutputFile=packages-lock.txt" `
        "-Dsort=true" `
        "-Dstyle.color=never" `
        "-DappendOutput=false" `
        "-DincludeScope=runtime" `
        "-DexcludeTransitive=false" `
        "-s" "settings.xml"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:list 執行失敗"
        $exitCode = 1
        break
    }
    Write-Host "[INFO] 已建立 pom.xml" # 為了排版好看，改放這邊。

    # 過濾套件清單
    $dependencyList = Get-Content 'packages-lock.txt' -Raw -Encoding UTF8
    $dependencyList = $dependencyList -split "`n" |
    Where-Object { $_ -match '^\s+\S+:\S+:\S+:\S+' } |
        ForEach-Object {
            ($_ -replace '\s*-- module.*', '').Trim()
        }
    $dependencyList | ForEach-Object {
        $p = $_ -split ':'
        "$($p[0]):$($p[1]):$($p[3])"
    } | Set-Content 'packages-lock.txt' -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-lock.txt"

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
    foreach ($dependency in $dependencyList) {
        $parts = $dependency -split ':'
        if ($parts.Count -ge 4) {
            $dependencyGroupId    = $parts[0]
            $dependencyArtifactId = $parts[1]
            $dependencyType       = $parts[2]
            $dependencyVersion    = $parts[3]
            $dependencyScope      = if ($parts.Count -ge 5) { $parts[4].Trim() } else { 'compile' }
            $bomContent.Add('            <dependency>')
            $bomContent.Add("                <groupId>$dependencyGroupId</groupId>")
            $bomContent.Add("                <artifactId>$dependencyArtifactId</artifactId>")
            $bomContent.Add("                <version>$dependencyVersion</version>")
            if ($dependencyType -ne 'jar') {
                $bomContent.Add("                <type>$dependencyType</type>")
            }
            if ($dependencyScope -ne 'compile') {
                $bomContent.Add("                <scope>$dependencyScope</scope>")
            }
            $bomContent.Add('            </dependency>')
        }
    }
    $bomContent.Add('        </dependencies>')
    $bomContent.Add('    </dependencyManagement>')
    $bomContent.Add('</project>')
    $bomContent | Set-Content 'packages-lock.xml' -Encoding UTF8
    Write-Host "[INFO] 已建立 packages-lock.xml"

    # 掛載 packages-lock.xml 為 pom.xml 的 <parent>
    $pomDocument = [System.Xml.XmlDocument]::new()
    $pomDocument.Load((Resolve-Path 'pom.xml').Path)
    $pomNamespace = $pomDocument.DocumentElement.NamespaceURI
    $pomParentNode = $pomDocument.CreateElement('parent', $pomNamespace)
    $childNode = $pomDocument.CreateElement('groupId',      $pomNamespace); $childNode.InnerText = $projectGroupId;           $pomParentNode.AppendChild($childNode) | Out-Null
    $childNode = $pomDocument.CreateElement('artifactId',   $pomNamespace); $childNode.InnerText = "$projectArtifactId-lock"; $pomParentNode.AppendChild($childNode) | Out-Null
    $childNode = $pomDocument.CreateElement('version',      $pomNamespace); $childNode.InnerText = $projectVersion;           $pomParentNode.AppendChild($childNode) | Out-Null
    $childNode = $pomDocument.CreateElement('relativePath', $pomNamespace); $childNode.InnerText = 'packages-lock.xml';       $pomParentNode.AppendChild($childNode) | Out-Null
    $pomDocument.DocumentElement.InsertAfter($pomParentNode, $pomDocument.GetElementsByTagName('modelVersion', $pomNamespace)[0]) | Out-Null
    $pomDocumentWriter = [System.Xml.XmlWriter]::Create((Resolve-Path 'pom.xml').Path, $xmlWriterSettings); 
    $pomDocument.Save($pomDocumentWriter); 
    $pomDocumentWriter.Dispose() 
    Write-Host "[INFO] 已掛載 packages-lock.xml 為 pom.xml 的 <parent>"
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