[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$exitCode = 0
do {
    # TODO: 在這裡加入主要邏輯

    break
} while ($false)

exit $exitCode


# 檢查 pom.xml
    if (-not (Test-Path "pom.xml")) {
        Write-Host "[ERROR] 找不到 pom.xml"
        $exitCode = 1
        break
    }

    # 清理暫存檔
    foreach ($f in "dependency.list.tmp", "dependency.list.txt", "packages-lock.xml") {
        if (Test-Path $f) { Remove-Item $f -Force }
    }

    # 移除 <parent>
    $xmlDoc = [System.Xml.XmlDocument]::new()
    $xmlDoc.PreserveWhitespace = $true
    $xmlDoc.Load("$PSScriptRoot\pom.xml")
    $mvnNs = $xmlDoc.DocumentElement.NamespaceURI
    $parentNode = $xmlDoc.DocumentElement['parent']
    if ($parentNode) {
        [void]$parentNode.ParentNode.RemoveChild($parentNode)
        [System.IO.File]::WriteAllText(
            "$PSScriptRoot\pom.xml",
            $xmlDoc.OuterXml,
            [System.Text.UTF8Encoding]::new($false)
        )
    }

    # ===== 執行區 =====
    Write-Host "========================================"
    Write-Host "套件專案: pom.xml"
    Write-Host "========================================"
    Write-Host ""

    # 解析套件清單
    & mvn dependency:list `
        "-DoutputFile=dependency.list.tmp" `
        "-DincludeScope=compile" `
        "-Dstyle.color=never"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] mvn dependency:list 執行失敗"
        $exitCode = 1
        break
    }

    # 過濾套件清單
    $filtered = Get-Content "dependency.list.tmp" -Encoding UTF8 |
        Where-Object { $_ -match ' -- module ' } |
        ForEach-Object { ($_ -replace ' -- module .*$', '').Trim() }

    [System.IO.File]::WriteAllLines(
        "$PSScriptRoot\dependency.list.txt",
        $filtered,
        [System.Text.UTF8Encoding]::new($false)
    )

    # 讀取專案參數
    $PROJECT_MODELVERSION = (& mvn help:evaluate '-Dexpression=project.modelVersion' -q '-DforceStdout') | Where-Object { $_ } | Select-Object -Last 1
    $PROJECT_GROUPID      = (& mvn help:evaluate '-Dexpression=project.groupId'      -q '-DforceStdout') | Where-Object { $_ } | Select-Object -Last 1
    $PROJECT_ARTIFACTID   = (& mvn help:evaluate '-Dexpression=project.artifactId'   -q '-DforceStdout') | Where-Object { $_ } | Select-Object -Last 1
    $PROJECT_VERSION      = (& mvn help:evaluate '-Dexpression=project.version'      -q '-DforceStdout') | Where-Object { $_ } | Select-Object -Last 1

    Write-Host "[INFO] groupId: $PROJECT_GROUPID"
    Write-Host "[INFO] artifactId: $PROJECT_ARTIFACTID"
    Write-Host "[INFO] version: $PROJECT_VERSION"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 產生 packages-lock.xml（格式：BOM POM，以 dependencyManagement 固定所有版本）
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<project xmlns="http://maven.apache.org/POM/4.0.0"')
    [void]$sb.AppendLine('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
    [void]$sb.AppendLine('         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("    <groupId>$PROJECT_GROUPID</groupId>")
    [void]$sb.AppendLine("    <artifactId>${PROJECT_ARTIFACTID}-lock</artifactId>")
    [void]$sb.AppendLine("    <version>$PROJECT_VERSION</version>")
    [void]$sb.AppendLine("    <modelVersion>$PROJECT_MODELVERSION</modelVersion>")
    [void]$sb.AppendLine("    <packaging>pom</packaging>")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('    <dependencyManagement>')
    [void]$sb.AppendLine('        <dependencies>')

    Get-Content "dependency.list.txt" -Encoding UTF8 |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
            # 格式：groupId:artifactId:type:version:scope
            $parts = $_ -split ':'
            if ($parts.Count -ge 4) {
                [void]$sb.AppendLine('            <dependency>')
                [void]$sb.AppendLine("                <groupId>$($parts[0])</groupId>")
                [void]$sb.AppendLine("                <artifactId>$($parts[1])</artifactId>")
                [void]$sb.AppendLine("                <version>$($parts[3])</version>")
                [void]$sb.AppendLine('            </dependency>')
                [void]$sb.AppendLine('')
            }
        }

    [void]$sb.AppendLine('        </dependencies>')
    [void]$sb.AppendLine('    </dependencyManagement>')
    [void]$sb.AppendLine('')
    [void]$sb.Append('</project>')

    [System.IO.File]::WriteAllText(
        "$PSScriptRoot\packages-lock.xml",
        $sb.ToString(),
        [System.Text.UTF8Encoding]::new($false)
    )

    # 更新 pom.xml：還原標記，並以 XML 加入 <parent> 指向 packages-lock.xml
    $pomContent = Get-Content "$PSScriptRoot\pom.xml" -Raw -Encoding UTF8
    $pomContent = $pomContent -replace '<!--\s*packages-lock-start', '<!-- packages-lock-start -->'
    $pomContent = $pomContent -replace 'packages-lock-end\s*-->', '<!-- packages-lock-end -->'

    $pomXml = [System.Xml.XmlDocument]::new()
    $pomXml.PreserveWhitespace = $true
    $pomXml.LoadXml($pomContent)

    $parentElem = $pomXml.CreateElement('parent', $mvnNs)
    $parentFields = [ordered]@{
        groupId      = $PROJECT_GROUPID
        artifactId   = "${PROJECT_ARTIFACTID}-lock"
        version      = $PROJECT_VERSION
        relativePath = './packages-lock.xml'
    }
    $parentFields.GetEnumerator() | ForEach-Object {
        [void]$parentElem.AppendChild($pomXml.CreateTextNode("`n        "))
        $child = $pomXml.CreateElement($_.Key, $mvnNs)
        $child.InnerText = $_.Value
        [void]$parentElem.AppendChild($child)
    }
    [void]$parentElem.AppendChild($pomXml.CreateTextNode("`n    "))

    $refNode = $pomXml.DocumentElement.ChildNodes |
        Where-Object { $_ -is [System.Xml.XmlElement] } |
        Select-Object -First 1
    [void]$pomXml.DocumentElement.InsertBefore($parentElem, $refNode)
    [void]$pomXml.DocumentElement.InsertBefore($pomXml.CreateTextNode("`n    "), $refNode)

    [System.IO.File]::WriteAllText(
        "$PSScriptRoot\pom.xml",
        $pomXml.OuterXml,
        [System.Text.UTF8Encoding]::new($false)
    )
