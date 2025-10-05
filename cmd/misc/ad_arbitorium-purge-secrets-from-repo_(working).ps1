# Base directory (like %~dp0)
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Exact filenames to delete
$exactNames = @(
    "system.yaml",
    "ceph.conf"
)

# File extensions to delete
$extensions = @(
    ".env",
    ".smbcreds"
)

# Folder keywords to exclude (e.g., skip paths that contain these)
$forbiddenFolders = @(
    "photoprism-x",
)

Write-Host "Scanning: $baseDir"
Write-Host

# Recursively scan all files
Get-ChildItem -Path $baseDir -Recurse -File | ForEach-Object {
    $filePath = $_.FullName
    $fileName = $_.Name
    $fileExt = $_.Extension

    # Check if file path contains any forbidden folder keyword
    $forbidden = $false
    foreach ($keyword in $forbiddenFolders) {
        if ($filePath -like "*\$keyword\*") {
            $forbidden = $true
            break
        }
    }

    if ($forbidden) {
        Write-Host "Deleting: $filePath"
        try {
            Remove-Item -LiteralPath $filePath -Force
        } catch {
            Write-Warning "Failed to delete: $filePath"
        }
    }

    # Check if filename or extension match
    if ($exactNames -contains $fileName -or $extensions -contains $fileExt) {
        Write-Host "Deleting: $filePath"
        try {
            Remove-Item -LiteralPath $filePath -Force
        } catch {
            Write-Warning "Failed to delete: $filePath"
        }
    }
}

Write-Host "`nDone."
pause