Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$xmlWriterSettings = [System.Xml.XmlWriterSettings]@{ Indent = $true; Encoding = [System.Text.UTF8Encoding]::new($false); IndentChars = '    '; }
do {


    # ===== Require =====
    # 檢查 pom.xml
    if (-not (Test-Path 'pom.xml')) {
        Write-Host '[ERROR] 找不到 pom.xml'
        $exitCode = 1
        break
    }

    # 移除 pom.xml 的 <parent>
    $pomDocument = [System.Xml.XmlDocument]::new()
    $pomDocument.Load((Resolve-Path 'pom.xml').Path)
    $oldParentNode = $pomDocument.DocumentElement.ChildNodes | Where-Object { $_.LocalName -eq 'parent' } | Select-Object -First 1
    if ($oldParentNode) {
        $pomDocument.DocumentElement.RemoveChild($oldParentNode) | Out-Null        
        $pomDocumentWriter = [System.Xml.XmlWriter]::Create((Resolve-Path 'pom.xml').Path, $xmlWriterSettings); 
        $pomDocument.Save($pomDocumentWriter); 
        $pomDocumentWriter.Dispose()
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

    # 過濾套件清單
    $dependencyList = Get-Content 'packages-lock.txt' -Raw -Encoding UTF8
    $dependencyList = $dependencyList -split "`n" |
    Where-Object { $_ -match '-- module' } |
        ForEach-Object {
            ($_ -replace '\s*-- module.*', '').Trim()
        }
        $dependencyList | Set-Content 'packages-lock.txt' -Encoding UTF8
    Write-Host "[INFO] 已產生 packages-lock.txt"

    # 產生 packages-lock.xml
    $bomContent = [System.Collections.Generic.List[string]]::new()
    $bomContent.Add('<?xml version="1.0" encoding="UTF-8"?>')
    $bomContent.Add('<project xmlns="http://maven.apache.org/POM/4.0.0"')
    $bomContent.Add('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    $bomContent.Add('         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">')
    $bomContent.Add('')
    $bomContent.Add("    <modelVersion>$PROJECT_MODELVERSION</modelVersion>")
    $bomContent.Add("    <groupId>$PROJECT_GROUPID</groupId>")
    $bomContent.Add("    <artifactId>$PROJECT_ARTIFACTID-lock</artifactId>")
    $bomContent.Add("    <version>$PROJECT_VERSION</version>")
    $bomContent.Add('    <packaging>pom</packaging>')
    $bomContent.Add('')
    $bomContent.Add('    <dependencyManagement>')
    $bomContent.Add('        <dependencies>')
    foreach ($dependency in $dependencyList) {
        $parts = $dependency -split ':'
        if ($parts.Count -ge 4) {
            $depGroupId    = $parts[0]
            $depArtifactId = $parts[1]
            $depType       = $parts[2]
            $depVersion    = $parts[3]
            $depScope      = if ($parts.Count -ge 5) { $parts[4].Trim() } else { 'compile' }
            $bomContent.Add('            <dependency>')
            $bomContent.Add("                <groupId>$depGroupId</groupId>")
            $bomContent.Add("                <artifactId>$depArtifactId</artifactId>")
            $bomContent.Add("                <version>$depVersion</version>")
            if ($depType -ne 'jar') { 
                $bomContent.Add("                <type>$depType</type>") 
            }
            if ($depScope -ne 'compile') { 
                $bomContent.Add("                <scope>$depScope</scope>") 
            }
            $bomContent.Add('            </dependency>')
        }
    }
    $bomContent.Add('        </dependencies>')
    $bomContent.Add('    </dependencyManagement>')
    $bomContent.Add('</project>')
    $bomContent | Set-Content 'packages-lock.xml' -Encoding UTF8
    Write-Host "[INFO] 已產生 packages-lock.xml"

    # 掛載 packages-lock.xml 為 pom.xml 的 <parent>
    $pomNamespace = $pomDocument.DocumentElement.NamespaceURI
    $pomParentNode = $pomDocument.CreateElement('parent', $pomNamespace)
    $childNode = $pomDocument.CreateElement('groupId',      $pomNamespace); $childNode.InnerText = $PROJECT_GROUPID;           $pomParentNode.AppendChild($childNode) | Out-Null
    $childNode = $pomDocument.CreateElement('artifactId',   $pomNamespace); $childNode.InnerText = "$PROJECT_ARTIFACTID-lock"; $pomParentNode.AppendChild($childNode) | Out-Null
    $childNode = $pomDocument.CreateElement('version',      $pomNamespace); $childNode.InnerText = $PROJECT_VERSION;           $pomParentNode.AppendChild($childNode) | Out-Null
    $childNode = $pomDocument.CreateElement('relativePath', $pomNamespace); $childNode.InnerText = 'packages-lock.xml';        $pomParentNode.AppendChild($childNode) | Out-Null
    $pomDocument.DocumentElement.AppendChild($pomParentNode) | Out-Null    
    $pomDocumentWriter = [System.Xml.XmlWriter]::Create((Resolve-Path 'pom.xml').Path, $xmlWriterSettings); 
    $pomDocument.Save($pomDocumentWriter); 
    $pomDocumentWriter.Dispose() 
    Write-Host "[INFO] 已掛載 packages-lock.xml 為 pom.xml 的 <parent>"
    Write-Host "[INFO] ------------------------------------------------------------------------"


# ===== End =====
} while ($false)
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] pom.xml 處理完成'
}
Write-Host
exit $exitCode