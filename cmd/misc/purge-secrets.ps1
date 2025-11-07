# Base directory (like %~dp0)
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# === Delete these specific filenames ===
$exactNames = @(
    "system.yaml",
    "ceph.conf"
)

# === Delete files with these extensions ===
$extensions = @(
    ".env",
    ".smbcreds"
)

# === Delete entire folders if their name contains any of these keywords ===
$badFolderNames = @(
    "photoprism-x",
    "plex-ms-x"
)

Write-Host "Scanning in: $baseDir"
Write-Host

# --- Step 1: Delete matching files (by name or extension) ---
Get-ChildItem -Path $baseDir -Recurse -File | ForEach-Object {
    $file = $_
    if ($exactNames -contains $file.Name -or $extensions -contains $file.Extension) {
        Write-Host "Deleting file: $($file.FullName)"
        try {
            Remove-Item -LiteralPath $file.FullName -Force
        } catch {
            Write-Warning "Failed to delete file: $($file.FullName)"
        }
    }
}

# --- Step 2: Delete folders if name contains a bad keyword ---
Get-ChildItem -Path $baseDir -Recurse -Directory | Sort-Object -Property FullName -Descending | ForEach-Object {
    $folder = $_
    foreach ($badName in $badFolderNames) {
        if ($folder.Name -like "*$badName*") {
            Write-Host "Deleting folder: $($folder.FullName)"
            try {
                Remove-Item -LiteralPath $folder.FullName -Recurse -Force
            } catch {
                Write-Warning "Failed to delete folder: $($folder.FullName)"
            }
            break
        }
    }
}

Write-Host "`nDone."
pause