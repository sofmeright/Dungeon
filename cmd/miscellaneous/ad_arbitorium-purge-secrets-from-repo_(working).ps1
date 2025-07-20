# Set the base directory to the location of this script
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# List of exact filenames to match
$exactNames = @(
    "system.yaml",
    "ceph.conf"
)

# List of extensions to match (including the dot)
$extensions = @(
    ".env",
    ".smbcreds"
)

# Recursively search all files
Get-ChildItem -Path $baseDir -Recurse -File | ForEach-Object {
    $name = $_.Name
    $ext  = $_.Extension

    if ($exactNames -contains $name -or $extensions -contains $ext) {
        Write-Host "Deleting: $($_.FullName)"
        try {
            Remove-Item -LiteralPath $_.FullName -Force
        } catch {
            Write-Warning "Failed to delete: $($_.FullName)"
        }
    }
}

Write-Host "`nDone."
Pause