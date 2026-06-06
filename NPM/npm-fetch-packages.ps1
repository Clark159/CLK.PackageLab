param(
    [switch]$Pause
)
Set-Location -Path $PSScriptRoot
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Variables =====
$exitCode = 0
$npmSourceList = @(
    @{ id = 'npmjs'; url = 'https://registry.npmjs.org' }
)
$npmRegistry = @{ id = 'npmjs'; url = 'https://registry.npmjs.org' }
do {


    # ===== Require =====
    foreach ($fileName in 'package.txt') {
        if (-not (Test-Path $fileName)) {
            Write-Host "[ERROR] Not found: $fileName"
            $exitCode = 1
            break
        }
    }
    if ($exitCode -ne 0) { break }

    foreach ($directoryPath in './node_modules', './packages') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    foreach ($fileName in '.npmrc', 'package.json', 'package-lock.json', 'package-adding.txt', 'package-missing.txt') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }


    # ===== Execute =====
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "npm-fetch-packages"
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host

    $packageList = Get-Content 'package.txt' -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }

    $depsStr = ($packageList | ForEach-Object {
        if ($_ -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            "    `"$($Matches[1])`": `"$($Matches[2])`""
        }
    }) -join ",`n"
    $packageJsonStr = "{`n  `"name`": `"fetch-packages`",`n  `"version`": `"1.0.0`",`n  `"dependencies`": {`n$depsStr`n  }`n}"
    Set-Content './package.json' -Value $packageJsonStr -Encoding UTF8

    # .npmrc - npmSourceList
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmSourceList[0].url)")
    foreach ($npmSource in $npmSourceList) {
        if ($npmSource.scope) {
            $npmrcContent.Add("$($npmSource.scope):registry=$($npmSource.url)")
        }
        if ($npmSource.username -and $npmSource.password) {
            $authUrl = $npmSource.url -replace '^https?:', ''
            $token   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($npmSource.username):$($npmSource.password)"))
            $npmrcContent.Add("$authUrl/:_auth=$token")
        }
    }
    Set-Content './.npmrc' -Value $npmrcContent -Encoding UTF8

    & npm install --ignore-scripts --no-audit
    $installExitCode = $LASTEXITCODE
    if ($installExitCode -ne 0) {
        Write-Host "[ERROR] npm install failed (npmSourceList)"
        $exitCode = 1
        break
    }

    # .npmrc - npmRegistry
    $npmrcContent = [System.Collections.Generic.List[string]]::new()
    $npmrcContent.Add("registry=$($npmRegistry.url)")
    if ($npmRegistry.scope) {
        $npmrcContent.Add("$($npmRegistry.scope):registry=$($npmRegistry.url)")
    }
    if ($npmRegistry.username -and $npmRegistry.password) {
        $authUrl = $npmRegistry.url -replace '^https?:', ''
        $token   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($npmRegistry.username):$($npmRegistry.password)"))
        $npmrcContent.Add("$authUrl/:_auth=$token")
    }
    Set-Content './.npmrc' -Value $npmrcContent -Encoding UTF8

    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            $name = $Matches[1]
            $packagePath = "./node_modules/$name"
            if (Test-Path $packagePath) {
                Remove-Item -Path $packagePath -Recurse -Force
            }
        }
    }

    if (Test-Path './package-lock.json') {
        Remove-Item './package-lock.json' -Force
    }

    & npm install --ignore-scripts --no-audit
    $installExitCode = $LASTEXITCODE
    if ($installExitCode -ne 0) {
        Write-Host "[ERROR] npm install failed (npmRegistry)"
        $exitCode = 1
        break
    }

    $missingList = @()
    foreach ($package in $packageList) {
        if ($package -match '^(@[^@]+/[^@]+|[^@]+)@(.+)$') {
            $name    = $Matches[1]
            $version = $Matches[2]
            $packagePath = "./node_modules/$name"
            if (Test-Path $packagePath) {
                if ($name -match '^(@[^/]+)/') {
                    $destinationDirectory = "./packages/$($Matches[1])"
                } else {
                    $destinationDirectory = './packages'
                }
                New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
                Copy-Item -Path $packagePath -Destination $destinationDirectory -Recurse -Force
            } else {
                $missingList += $package
            }
        }
    }

    if ($missingList.Count -eq 0) {
        $packageList | ForEach-Object { Write-Host "[INFO] $_" }
        Write-Host "[INFO] Done: $($packageList.Count) packages"
        Write-Host "[INFO] ------------------------------------------------------------------------"
    } else {
        $missingList | ForEach-Object { Write-Host "[ERROR] $_" }
        Write-Host "[ERROR] Failed: missing $($missingList.Count) packages"
        Write-Host "[ERROR] ------------------------------------------------------------------------"
        $exitCode = 1
    }

    foreach ($directoryPath in './node_modules') {
        if (Test-Path $directoryPath) {
            Remove-Item -Path $directoryPath -Recurse -Force
        }
    }

    foreach ($fileName in '.npmrc', 'package.json', 'package-lock.json') {
        if (Test-Path $fileName) {
            Remove-Item $fileName -Force
        }
    }


# ===== End =====
} while ($false)
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] All done'
}
if ($Pause) {
    Write-Host
    Write-Host 'Press any key to continue...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
exit $exitCode
