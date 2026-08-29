param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$scriptVersion = '20260829-00'
$exitCode = 0
$nugetSourceList = @(
    @{ id = 'nuget.org'; url = 'https://api.nuget.org/v3/index.json' }
)
$nugetRepository = @{ id = 'nuget.org'; url = 'https://api.nuget.org/v3/index.json' }
do {


    # ===== Require =====
    # 檢查檔案
    $csprojFile = Get-ChildItem -Path . -Filter '*.csproj' -File | Select-Object -First 1
    if (-not $csprojFile) {
        Write-Host "[ERROR] 找不到 .csproj 檔案"
        $exitCode = 1
        break
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($directoryPath in './nuget_caches', './obj', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'nuget.config', 'package-lock.json', 'package-all.txt', 'package-adding.txt', 'package-updating.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }

    # 整併 nugetRepository 至 nugetSourceList
    if (-not ($nugetSourceList | Where-Object { $_.url -eq $nugetRepository.url })) {

        # nugetSourceId
        $suffix = 2
        $nugetSourceId = $nugetRepository.id
        while ($nugetSourceList | Where-Object { $_.id -eq $nugetSourceId }) {
            $nugetSourceId = "$($nugetRepository.id)$suffix"
            $suffix++
        }

        # nugetSource
        $nugetSource = $nugetRepository.Clone()
        $nugetSource.id = $nugetSourceId
        $nugetSourceList += $nugetSource
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "nuget-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 nuget.config (nugetSourceList)
    $nugetConfigContent = [System.Collections.Generic.List[string]]::new()
    $nugetConfigContent.Add('<?xml version="1.0" encoding="utf-8"?>')
    $nugetConfigContent.Add('<configuration>')
    $nugetConfigContent.Add('    <packageSources>')
    $nugetConfigContent.Add('        <clear />')
    foreach ($nugetSource in $nugetSourceList) {
        $nugetConfigContent.Add("        <add key=""$($nugetSource.id)"" value=""$($nugetSource.url)"" />")
    }
    $nugetConfigContent.Add('    </packageSources>')
    $nugetConfigContent.Add('    <packageSourceCredentials>')
    foreach ($nugetSource in $nugetSourceList) {
        if ($nugetSource.token) {
            $nugetConfigContent.Add("        <$($nugetSource.id)>")
            $nugetConfigContent.Add("            <add key=""Username"" value=""PAT"" />")
            $nugetConfigContent.Add("            <add key=""ClearTextPassword"" value=""$($nugetSource.token)"" />")
            $nugetConfigContent.Add("        </$($nugetSource.id)>")
        } elseif ($nugetSource.username -and $nugetSource.password) {
            $nugetConfigContent.Add("        <$($nugetSource.id)>")
            $nugetConfigContent.Add("            <add key=""Username"" value=""$($nugetSource.username)"" />")
            $nugetConfigContent.Add("            <add key=""ClearTextPassword"" value=""$($nugetSource.password)"" />")
            $nugetConfigContent.Add("        </$($nugetSource.id)>")
        }
    }
    $nugetConfigContent.Add('    </packageSourceCredentials>')
    $nugetConfigContent.Add('    <config>')
    $nugetConfigContent.Add('        <add key="PackageSaveMode" value="nuspec;nupkg" />')
    $nugetConfigContent.Add('    </config>')
    $nugetConfigContent.Add('</configuration>')
    Set-Content 'nuget.config' -Value $nugetConfigContent -Encoding UTF8

    # 建立 package-all.txt
    & nuget restore `
        $csprojFile.FullName `
        "-ConfigFile" "nuget.config" `
        "-PackagesDirectory" "./nuget_caches" `
        "-NoHttpCache" `
        "-NonInteractive"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] nuget restore 執行失敗 (nugetSourceList)"
        $exitCode = 1
        break
    }           
    $allList = @(Get-ChildItem -Path './nuget_caches' -Filter '*.nuspec' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        [xml]$nuspecXml = Get-Content $_.FullName -Encoding UTF8
        $versionParts   = $nuspecXml.package.metadata.version.Split('-', 2)
        $versionLabel   = $versionParts[0]
        $versionRelease = $versionParts[1]
        $versionSegments = @($versionLabel.Split('.'))
        if ($versionSegments.Count -lt 3) {
            $versionSegments = $versionSegments + (@('0') * (3 - $versionSegments.Count))
        } elseif ($versionSegments.Count -eq 4 -and $versionSegments[3] -eq '0') {
            $versionSegments = $versionSegments[0..2]
        }
        $versionLabel = $versionSegments -join '.'
        if ($versionRelease) {
            $versionLabel = "$versionLabel-$versionRelease"
        }
        [PSCustomObject]@{
            name    = $nuspecXml.package.metadata.id
            version = $versionLabel
        }
    } | Where-Object { $_.name -and $_.version } | Sort-Object -Property name, version -Unique)
    Set-Content 'package-all.txt' -Value ($allList | ForEach-Object { "$($_.name) $($_.version)" }) -Encoding UTF8
    Write-Host
    Write-Host 
    Write-Host "[INFO] ------------------------------------------------------------------------"
    Write-Host "[INFO] 已建立 package-all.txt"

    # 取得 packageBaseUrl 
    $packageBaseUrl = $null
    $resourceMode   = $null
    try {
        $serviceIndex = Invoke-RestMethod -Uri $nugetRepository.url -Method Get -TimeoutSec 15 -ErrorAction Stop
        if (-not $packageBaseUrl) {
            $packageBaseUrl = ($serviceIndex.resources | Where-Object { $_.'@type' -like 'PackageBaseAddress/*' } | Select-Object -First 1).'@id'
            if ($packageBaseUrl) { $resourceMode = 'flat' }
        }
        if (-not $packageBaseUrl) {
            $packageBaseUrl = ($serviceIndex.resources | Where-Object { $_.'@type' -eq 'RegistrationsBaseUrl' } | Select-Object -First 1).'@id'
            if ($packageBaseUrl) { $resourceMode = 'registration' }
        }
    } catch {
        $packageBaseUrl = $null
    }
    if (-not $packageBaseUrl) {
        Write-Host "[ERROR] 無法解析 nugetRepository 的 PackageBaseAddress 或 RegistrationsBaseUrl"
        $exitCode = 1
        break
    }
    $packageBaseUrl = $packageBaseUrl.TrimEnd('/')

    # 建立 package-adding.txt
    $addingList = [System.Collections.Generic.List[object]]::new()
    foreach ($package in $allList) {
        $packageId  = $package.name.ToLower()
        $packageUrl = "$packageBaseUrl/$packageId/index.json"
        $isAdding = $true
        try {
            $null = Invoke-WebRequest -Uri $packageUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $isAdding = $false
        } catch { }
        if ($isAdding) {
            $addingList.Add($package)
        }
    }
    Set-Content 'package-adding.txt' -Value ($addingList | ForEach-Object { "$($_.name) $($_.version)" }) -Encoding UTF8
    Write-Host "[INFO] 已建立 package-adding.txt"

    # 建立 package-updating.txt 
    $updatingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $allList) {
        $packageId      = $package.name.ToLower()
        $packageVersion = $package.version.ToLower()
        $packageUrl     = $null
        $isUpdating     = $true
        switch ($resourceMode) {
            'flat'         { $packageUrl = "$packageBaseUrl/$packageId/$packageVersion/$packageId.$packageVersion.nupkg" }
            'registration' { $packageUrl = "$packageBaseUrl/$packageId/$packageVersion.json" }
            default {
                Write-Host "[ERROR] 未知的 resourceMode: $resourceMode"
                $exitCode = 1
                break
            }
        }
        try {
            $null = Invoke-WebRequest -Uri $packageUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $isUpdating = $false
        } catch { }
        $isAdding = $addingList | Where-Object { $_.name -eq $package.name }
        if ($isUpdating -and -not $isAdding) {
            $updatingList.Add("$($package.name) $($package.version)")
        }
    }
    Set-Content 'package-updating.txt' -Value $updatingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-updating.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除資料夾
    foreach ($directoryPath in './nuget_caches', './obj') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'nuget.config') {
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
