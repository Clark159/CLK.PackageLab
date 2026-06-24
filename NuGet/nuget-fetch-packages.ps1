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
$nugetRepository = @{ id = 'nuget.org'; url = 'https://api.nuget.org/v3/index.json' }
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
        $nugetRepository.url = $nugetRepository.url -replace '(?<=/)(index\.json)$', "$folderName/`$1"
    }

    # 移除資料夾
    foreach ($directoryPath in './nuget_caches', './obj', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'nuget.config', 'package.csproj', 'package-lock.json', 'package-adding.txt', 'package-missing.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "nuget-fetch-packages"
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
    $nugetConfigContent.Add('</configuration>')
    Set-Content 'nuget.config' -Value $nugetConfigContent -Encoding UTF8

    # 讀取 package.txt
    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object {
        $_.Trim() -ne ''
    }

    # 產生 package.csproj
    $csprojContent = [System.Collections.Generic.List[string]]::new()
    $csprojContent.Add('<Project Sdk="Microsoft.NET.Sdk">')
    $csprojContent.Add('    <PropertyGroup>')
    $csprojContent.Add('        <TargetFramework>net8.0</TargetFramework>')
    $csprojContent.Add('    </PropertyGroup>')
    $csprojContent.Add('    <ItemGroup>')
    foreach ($package in $packageList) {
        $packageParts = $package -split '/'
        if ($packageParts.Count -ge 2) {
            $csprojContent.Add("        <PackageReference Include=""$($packageParts[0])"" Version=""$($packageParts[1])"" />")
        }
    }
    $csprojContent.Add('    </ItemGroup>')
    $csprojContent.Add('</Project>')
    Set-Content 'package.csproj' -Value $csprojContent -Encoding UTF8

    # 下載所有套件
    & dotnet restore `
        "package.csproj" `
        "--configfile" "nuget.config" `
        "--packages" "./nuget_caches"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] dotnet restore 執行失敗 (nugetSourceList)"
        $exitCode = 1
        break
    }

    # 建立 nuget.config - nugetRepository
    $nugetConfigContent = [System.Collections.Generic.List[string]]::new()
    $nugetConfigContent.Add('<?xml version="1.0" encoding="utf-8"?>')
    $nugetConfigContent.Add('<configuration>')
    $nugetConfigContent.Add('    <packageSources>')
    $nugetConfigContent.Add('        <clear />')
    $nugetConfigContent.Add("        <add key=""$($nugetRepository.id)"" value=""$($nugetRepository.url)"" />")
    $nugetConfigContent.Add('    </packageSources>')
    $nugetConfigContent.Add('    <packageSourceCredentials>')
    if ($nugetRepository.token) {
        $nugetConfigContent.Add("        <$($nugetRepository.id)>")
        $nugetConfigContent.Add("            <add key=""Username"" value=""PAT"" />")
        $nugetConfigContent.Add("            <add key=""ClearTextPassword"" value=""$($nugetRepository.token)"" />")
        $nugetConfigContent.Add("        </$($nugetRepository.id)>")
    } elseif ($nugetRepository.username -and $nugetRepository.password) {
        $nugetConfigContent.Add("        <$($nugetRepository.id)>")
        $nugetConfigContent.Add("            <add key=""Username"" value=""$($nugetRepository.username)"" />")
        $nugetConfigContent.Add("            <add key=""ClearTextPassword"" value=""$($nugetRepository.password)"" />")
        $nugetConfigContent.Add("        </$($nugetRepository.id)>")
    }
    $nugetConfigContent.Add('    </packageSourceCredentials>')
    $nugetConfigContent.Add('</configuration>')
    Set-Content 'nuget.config' -Value $nugetConfigContent -Encoding UTF8

    # 刪除目標套件
    foreach ($package in $packageList) {
        $packageParts = $package -split '/'
        if ($packageParts.Count -ge 2) {
            $packageIdLower = $packageParts[0].ToLower()
            $packageVersion = $packageParts[1]
            $packagePath    = "./nuget_caches/$packageIdLower/$packageVersion"
            if (Test-Path $packagePath) {
                Remove-Item -Path $packagePath -Recurse -Force
            }
        }
    }

    # 下載目標套件
    & dotnet restore `
        "package.csproj" `
        "--configfile" "nuget.config" `
        "--packages" "./nuget_caches" `
        "--force"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] dotnet restore 執行失敗 (nugetRepository)"
        $exitCode = 1
        break
    }

    # 複製目標套件
    $missingList = @()
    foreach ($package in $packageList) {
        $packageParts = $package -split '/'
        if ($packageParts.Count -ge 2) {
            $packageIdLower = $packageParts[0].ToLower()
            $packageVersion = $packageParts[1]
            $packagePath    = "./nuget_caches/$packageIdLower/$packageVersion"
            if (Test-Path $packagePath) {
                $destinationDirectory = "./packages/$packageIdLower"
                New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
                Copy-Item -Path $packagePath -Destination $destinationDirectory -Recurse -Force
            } else {
                $missingList += $package
            }
        }
    }

    # 顯示下載結果
    if ($missingList.Count -eq 0) {
        Write-Host
        Write-Host
        Write-Host "[INFO] ------------------------------------------------------------------------"
        $packageList | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] 套件下載完成，取得 $($packageList.Count) 個套件"
        Write-Host "[INFO] ------------------------------------------------------------------------"
    } else {
        Write-Host
        Write-Host
        Write-Host "[INFO] ------------------------------------------------------------------------"
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] 套件下載失敗，缺少 $($missingList.Count) 個套件"
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
    }

    # 移除資料夾
    foreach ($directoryPath in './nuget_caches', './obj') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    # 移除檔案
    foreach ($fileName in 'nuget.config', 'package.csproj', 'package-lock.json') {
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
