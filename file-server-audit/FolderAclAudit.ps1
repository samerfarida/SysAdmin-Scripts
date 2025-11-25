param(
    [Parameter(Mandatory = $true,
               HelpMessage = "Root path to audit (e.g. \\fileserver\share or C:\Data)")]
    [string]$RootPath,

    [Parameter(Mandatory = $false,
               HelpMessage = "Path to output CSV file")]
    [string]$OutputCsvPath = $(Join-Path -Path (Get-Location) -ChildPath ("FolderAclAudit_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))),

    [Parameter(Mandatory = $false,
               HelpMessage = "Path to log file")]
    [string]$LogFilePath = $(Join-Path -Path (Get-Location) -ChildPath ("FolderAclAudit_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date)))
)

# Ensure root path exists
if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-Error "Root path '$RootPath' does not exist or is not reachable."
    exit 1
}

# Start transcript logging
try {
    Start-Transcript -Path $LogFilePath -Append -ErrorAction Stop
} catch {
    Write-Warning "Failed to start transcript logging: $($_.Exception.Message)"
}

Write-Host "Starting FOLDER-ONLY ACL audit (NTFS + Share)..."
Write-Host "Root path     : $RootPath"
Write-Host "Output CSV    : $OutputCsvPath"
Write-Host "Log file      : $LogFilePath"
Write-Host "Start time    : $(Get-Date)"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
}

# Map FileSystemRights to a simpler permission level
function Get-PermissionLevel {
    param(
        [System.Security.AccessControl.FileSystemRights]$Rights
    )

    if ($Rights -band [System.Security.AccessControl.FileSystemRights]::FullControl) {
        return "FullControl"
    }

    if ($Rights -band [System.Security.AccessControl.FileSystemRights]::Modify) {
        return "Modify"
    }

    if ($Rights -band [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -or
        $Rights -band [System.Security.AccessControl.FileSystemRights]::Read) {
        return "Read"
    }

    return "Other"
}

# Get share information (server, share name, path, and ACE summary)
function Get-ShareInfo {
    param(
        [string]$RootPath
    )

    $shareProps = [ordered]@{
        ShareServer        = $null
        ShareName          = $null
        ShareLocalPath     = $null
        ShareAccessSummary = $null
    }

    # UNC path: \\Server\Share\...
    if ($RootPath.StartsWith("\\")) {
        if ($RootPath -match "^\\\\([^\\]+)\\([^\\]+)") {
            $server   = $matches[1]
            $shareName = $matches[2]

            $shareProps.ShareServer = $server
            $shareProps.ShareName   = $shareName

            try {
                $session = New-CimSession -ComputerName $server -ErrorAction Stop

                $share = Get-SmbShare -CimSession $session -Name $shareName -ErrorAction Stop
                $shareProps.ShareLocalPath = $share.Path

                $access = Get-SmbShareAccess -CimSession $session -Name $shareName -ErrorAction Stop
                if ($access) {
                    $summary = $access | ForEach-Object {
                        "$($_.AccountName):$($_.AccessControlType):$($_.AccessRight)"
                    }
                    $shareProps.ShareAccessSummary = ($summary -join "; ")
                }

                Remove-CimSession $session
            } catch {
                Write-Log "Could not retrieve share information for '\\$server\$shareName': $($_.Exception.Message)" "WARN"
            }
        }
    }
    else {
        # Local path: try to find a local share whose path is a prefix of RootPath
        try {
            $shares = Get-SmbShare -ErrorAction SilentlyContinue | Where-Object {
                $_.Path -and ($RootPath -like "$($_.Path)*")
            }

            if ($shares) {
                # Pick the most specific (longest path)
                $share = $shares | Sort-Object Path -Descending | Select-Object -First 1

                $shareProps.ShareServer    = $env:COMPUTERNAME
                $shareProps.ShareName      = $share.Name
                $shareProps.ShareLocalPath = $share.Path

                $access = Get-SmbShareAccess -Name $share.Name -ErrorAction SilentlyContinue
                if ($access) {
                    $summary = $access | ForEach-Object {
                        "$($_.AccountName):$($_.AccessControlType):$($_.AccessRight)"
                    }
                    $shareProps.ShareAccessSummary = ($summary -join "; ")
                }
            }
        } catch {
            Write-Log "Could not retrieve local share information for path '$RootPath': $($_.Exception.Message)" "WARN"
        }
    }

    return [pscustomobject]$shareProps
}

$results = New-Object System.Collections.Generic.List[psobject]
$errors  = New-Object System.Collections.Generic.List[psobject]

# Normalize root path for depth calculations
$normalizedRoot = $RootPath.TrimEnd('\')

# Resolve share information once (same for all folders under this root)
$shareInfo = Get-ShareInfo -RootPath $RootPath
if ($shareInfo.ShareName) {
    Write-Log "Share detected: $($shareInfo.ShareServer)\$($shareInfo.ShareName) (Path: $($shareInfo.ShareLocalPath))"
} else {
    Write-Log "No matching share information could be resolved for root path '$RootPath'." "WARN"
}

# Get list of all FOLDERS, including the root itself
Write-Log "Enumerating folders under '$RootPath'..."

$allFolders = @()

try {
    # Root folder
    $rootItem = Get-Item -LiteralPath $RootPath -ErrorAction Stop
    if (-not $rootItem.PSIsContainer) {
        Write-Error "Root path '$RootPath' is not a folder."
        exit 1
    }
    $allFolders += $rootItem

    # Subfolders only
    $children = Get-ChildItem -LiteralPath $RootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue
    $allFolders += $children
} catch {
    Write-Log "Failed to enumerate folders under '$RootPath': $($_.Exception.Message)" "ERROR"
}

$total = $allFolders.Count
Write-Log "Total folders found: $total"

$index     = 0
$idCounter = 0   # Global row ID

foreach ($folder in $allFolders) {
    $index++
    $percent = [int](($index / [math]::Max($total,1)) * 100)

    Write-Progress -Activity "Auditing folder ACLs" -Status $folder.FullName -PercentComplete $percent

    try {
        $acl = Get-Acl -LiteralPath $folder.FullName -ErrorAction Stop
    } catch {
        $errObj = [pscustomobject]@{
            Path      = $folder.FullName
            Error     = $_.Exception.Message
            TimeStamp = Get-Date
        }
        $errors.Add($errObj) | Out-Null
        Write-Log "Failed to get ACL for '$($folder.FullName)': $($_.Exception.Message)" "ERROR"
        continue
    }

    # Calculate parent folder and depth (relative to root)
    $parentFolder = Split-Path -LiteralPath $folder.FullName -Parent

    $normalizedFolder = $folder.FullName.TrimEnd('\')
    $folderDepth = 0
    if ($normalizedFolder.Length -gt $normalizedRoot.Length -and
        $normalizedFolder.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {

        $relative = $normalizedFolder.Substring($normalizedRoot.Length).TrimStart('\')
        if ($relative) {
            $folderDepth = $relative.Split('\').Count
        }
    }

    # Keep ACE order per folder
    $aceOrder = 0

    foreach ($ace in $acl.Access) {
        $aceOrder++
        $idCounter++

        $permissionLevel = Get-PermissionLevel -Rights $ace.FileSystemRights
        $aceType         = if ($ace.IsInherited) { "Inherited" } else { "Explicit" }

        $obj = [pscustomobject]@{
            ID                = $idCounter
            Path              = $folder.FullName
            ItemType          = "Folder"
            ParentFolder      = $parentFolder
            FolderDepth       = $folderDepth
            ShareServer       = $shareInfo.ShareServer
            ShareName         = $shareInfo.ShareName
            ShareLocalPath    = $shareInfo.ShareLocalPath
            ShareAccessSummary= $shareInfo.ShareAccessSummary
            ACEOrder          = $aceOrder
            ACEType           = $aceType
            Identity          = $ace.IdentityReference.Value
            FileSystemRights  = $ace.FileSystemRights.ToString()
            PermissionLevel   = $permissionLevel
            AccessControlType = $ace.AccessControlType.ToString()   # Allow / Deny
            InheritanceFlags  = $ace.InheritanceFlags.ToString()
            PropagationFlags  = $ace.PropagationFlags.ToString()
            IsInherited       = $ace.IsInherited
            Owner             = $acl.Owner
            LastWriteTime     = $folder.LastWriteTime
            CreationTime      = $folder.CreationTime
        }
        $results.Add($obj) | Out-Null
    }
}

Write-Log "Finished collecting ACLs. Exporting to CSV..."

try {
    $results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
    Write-Log "ACL data exported to '$OutputCsvPath'"
} catch {
    Write-Log "Failed to export ACL data: $($_.Exception.Message)" "ERROR"
}

if ($errors.Count -gt 0) {
    $errorCsvPath = [System.IO.Path]::ChangeExtension($OutputCsvPath, ".errors.csv")
    try {
        $errors | Export-Csv -Path $errorCsvPath -NoTypeInformation -Encoding UTF8
        Write-Log "Encountered $($errors.Count) errors. Details saved to '$errorCsvPath'" "WARN"
    } catch {
        Write-Log "Failed to export error details: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "No ACL errors encountered."
}

Write-Host "End time      : $(Get-Date)"
Write-Host "Audit complete."

try {
    Stop-Transcript | Out-Null
} catch {
    Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
}