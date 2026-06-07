param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$nugetSourceList = @(
    @{ id = 'nuget.org'; url = 'https://api.nuget.org/v3/index.json' }
)
$nugetRepository = @{ id = 'nuget.org'; url = 'https://api.nuget.org/v3-flatcontainer' }
do {


    # ===== Require =====
    # 檢查檔案
    foreach ($fileName in 'package.csproj') {
        if (-not (Test-Path $fileName)) {
            Write-Host "[ERROR] 找不到 $fileName"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    # 移除資料夾
    foreach ($directoryPath in './packages', './obj') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'nuget.config', 'package.txt', 'package-lock.json', 'package-adding.txt', 'package-missing.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "nuget-resolve-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    # 建立 nuget.config - nugetSourceList
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
        if ($nugetSource.username -and $nugetSource.password) {
            $nugetConfigContent.Add("        <$($nugetSource.id)>")
            $nugetConfigContent.Add("            <add key=""Username"" value=""$($nugetSource.username)"" />")
            $nugetConfigContent.Add("            <add key=""ClearTextPassword"" value=""$($nugetSource.password)"" />")
            $nugetConfigContent.Add("        </$($nugetSource.id)>")
        }
    }
    $nugetConfigContent.Add('    </packageSourceCredentials>')
    $nugetConfigContent.Add('</configuration>')
    Set-Content 'nuget.config' -Value $nugetConfigContent -Encoding UTF8

    # 建立 package-lock.json
    & dotnet restore `
        "--use-lock-file" `
        "--lock-file-path" "package-lock.json" `
        "--configfile" "nuget.config" `
        "--packages" "packages"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] dotnet restore 執行失敗 (nugetSourceList)"
        $exitCode = 1
        break
    }
    Write-Host
	Write-Host
	Write-Host "[INFO] ------------------------------------------------------------------------"
    Write-Host "[INFO] 已建立 package-lock.json"

    # 讀取 package-lock.json
    $lockJson = Get-Content 'package-lock.json' -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($null -eq $lockJson) {
        Write-Host "[ERROR] package-lock.json 讀取失敗"
        $exitCode = 1
        break
    }

    # 建立 package.txt
    $packageMap = @{}
    foreach ($frameworkProperty in $lockJson.dependencies.PSObject.Properties) {
        foreach ($packageProperty in $frameworkProperty.Value.PSObject.Properties) {
            $name    = $packageProperty.Name
            $version = $packageProperty.Value.resolved
            if ($name -and $version) {
                $nameVersion = "$name/$version"
                if (-not $packageMap.ContainsKey($nameVersion)) {
                    $packageMap[$nameVersion] = @{
                        name    = $name
                        version = $version
                    }
                }
            }
        }
    }
    $packageList    = @($packageMap.Values | Sort-Object { $_.name })
    $packageContent = $packageList | ForEach-Object { "$($_.name)/$($_.version)" }
    Set-Content 'package.txt' -Value $packageContent -Encoding UTF8
    Write-Host "[INFO] 已建立 package.txt"

    # 建立 package-adding.txt
    $addingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $packageIdLower = $package.name.ToLower()
        $packageUrl     = "$($nugetRepository.url)/$packageIdLower/index.json"
        $exists         = $false
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
            $addingList.Add("$($package.name)/$($package.version)")
        }
    }
    Set-Content 'package-adding.txt' -Value $addingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-adding.txt"

    # 建立 package-missing.txt
    $missingList = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packageList) {
        $packageIdLower      = $package.name.ToLower()
        $packageVersionLower = $package.version.ToLower()
        $baseUrl             = "$($nugetRepository.url)/$packageIdLower/$packageVersionLower"
        $isMissing           = $false

        # 檢查 nuspec
        try {
            $null = Invoke-WebRequest -Uri "$baseUrl/$packageIdLower.$packageVersionLower.nuspec" -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                $isMissing = $true
            }
        }

        # 檢查 nupkg
        if (-not $isMissing) {
            try {
                $null = Invoke-WebRequest -Uri "$baseUrl/$packageIdLower.$packageVersionLower.nupkg" -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            } catch {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
                    $isMissing = $true
                }
            }
        }

        if ($isMissing) {
            $missingList.Add("$($package.name)/$($package.version)")
        }
    }
    Set-Content 'package-missing.txt' -Value $missingList -Encoding UTF8
    Write-Host "[INFO] 已建立 package-missing.txt"
    Write-Host "[INFO] ------------------------------------------------------------------------"

    # 移除資料夾
    foreach ($directoryPath in './packages', './obj') {
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
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] 所有作業已完成'
}
if ($Pause) {
    Write-Host
    Write-Host '按任意鍵繼續...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
exit $exitCode
