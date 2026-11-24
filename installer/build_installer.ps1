# Builds Felt for Windows and packages it as build\installer\Felt-Setup-<version>.exe
# Usage (from the repo root):  powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Version from pubspec.yaml ("version: 1.2.3+4" -> 1.2.3).
$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
$version = ($versionLine.Matches[0].Groups[1].Value -split '\+')[0]
Write-Host "Building Felt $version"
# The app compares itself against GitHub releases using lib/app/version.dart.
$appVersion = (Select-String -Path lib\app\version.dart -Pattern "appVersion = '([^']+)'").Matches[0].Groups[1].Value
if ($appVersion -ne $version) { throw "lib/app/version.dart says $appVersion but pubspec.yaml says $version; update both." }

# Tools.
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = "$env:USERPROFILE\dev\flutter\bin\flutter.bat" }
$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup' }

# Visual C++ runtime (x64) from the installed Visual Studio / Build Tools.
$vsRoots = @("${env:ProgramFiles(x86)}\Microsoft Visual Studio", "$env:ProgramFiles\Microsoft Visual Studio")
$crt = Get-ChildItem $vsRoots -Recurse -Directory -Filter 'Microsoft.VC14*.CRT' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\Redist\\MSVC\\[^\\]+\\x64\\' -and $_.FullName -notmatch 'onecore|debug' } |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crt) { throw 'Visual C++ redistributable files not found (install the VS C++ build tools).' }
Write-Host "Using VC++ runtime from $($crt.FullName)"

# App icon PNGs (used by the wizard) and the release build.
& $flutter test tool/icon/render_icon_test.dart
if ($LASTEXITCODE -ne 0) { throw 'Icon render failed' }
& $flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

& $iscc "/DAppVersion=$version" "/DCrtDir=$($crt.FullName)" installer\felt.iss
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compile failed' }
Write-Host "Done: build\installer\Felt-Setup-$version.exe"
