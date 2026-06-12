# Builds tungsten-rain_<version>.zip for the mod portal. Run from mod root:
#   pwsh tools/build-zip.ps1
$version = (Get-Content info.json | ConvertFrom-Json).version
$name = "tungsten-rain_$version"
$stage = Join-Path $env:TEMP $name
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory $stage | Out-Null
Copy-Item info.json, data.lua, settings.lua, control.lua, changelog.txt, thumbnail.png $stage
Copy-Item -Recurse locale, graphics $stage
$zip = "..\$name.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path $stage -DestinationPath $zip
Remove-Item -Recurse -Force $stage
Write-Host "Done: $(Resolve-Path $zip)"
