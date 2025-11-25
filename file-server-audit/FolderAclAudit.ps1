param(
    [Parameter(Mandatory = $false,
               HelpMessage = "Root path to audit (e.g. \\fileserver\\share or C:\\Data)")]
    [string]$RootPath,

    [Parameter(Mandatory = $false,
               HelpMessage = "Path to output CSV file")]
    [string]$OutputCsvPath = $(Join-Path -Path (Get-Location) -ChildPath ("FolderAclAudit_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))),

    [Parameter(Mandatory = $false,
               HelpMessage = "Path to log file")]
    [string]$LogFilePath = $(Join-Path -Path (Get-Location) -ChildPath ("FolderAclAudit_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))),

    [Parameter(Mandatory = $false,
               HelpMessage = "Max depth: 0=root only, 1=root+children, 2=root+children+grandchildren, etc. Leave empty or omit for unlimited.")]
    [string]$MaxDepth = ""
)

# --- Interactive prompts for required parameters if not provided ---

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    Write-Host ""
    Write-Host "=== Folder ACL Audit Script ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Please provide the required information:" -ForegroundColor Yellow
    Write-Host ""
    $RootPath = Read-Host "Enter root path to audit (e.g. \\fileserver\share or C:\Data)"
    
    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        Write-Error "Root path is required. Script cannot continue without a valid path."
        exit 1
    }
    
    Write-Host "Root path set to: $RootPath" -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($MaxDepth)) {
    Write-Host ""
    Write-Host "Max Depth Options:" -ForegroundColor Yellow
    Write-Host "  - Press ENTER or leave empty for unlimited depth (scans all subfolders)" -ForegroundColor Gray
    Write-Host "  - Enter '0' to scan root folder only" -ForegroundColor Gray
    Write-Host "  - Enter '1' to scan root + first level children" -ForegroundColor Gray
    Write-Host "  - Enter '2' to scan root + children + grandchildren" -ForegroundColor Gray
    Write-Host "  - Enter any positive number for specific depth limit" -ForegroundColor Gray
    Write-Host ""
    $MaxDepth = Read-Host "Enter Max Depth (or press ENTER for unlimited)"
    
    if ([string]::IsNullOrWhiteSpace($MaxDepth)) {
        Write-Host "Max depth set to: Unlimited (all subfolders)" -ForegroundColor Green
    } else {
        Write-Host "Max depth set to: $MaxDepth" -ForegroundColor Green
    }
    Write-Host ""
}

# --- Normalize & validate MaxDepth ---

[int]$MaxDepthInt = [int]::MaxValue

if ([string]::IsNullOrWhiteSpace($MaxDepth)) {
    # User hit ENTER -> unlimited depth
    $MaxDepthInt = [int]::MaxValue
} else {
    $parsed = 0
    if (-not [int]::TryParse($MaxDepth, [ref]$parsed)) {
        Write-Error "MaxDepth must be a valid non-negative integer."
        exit 1
    }

    if ($parsed -lt 0) {
        Write-Warning "MaxDepth cannot be negative. Using 0 (root only)."
        $MaxDepthInt = 0
    } else {
        $MaxDepthInt = $parsed
    }
}

# --- Core script starts here ---

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

$maxDepthDisplay = if ($MaxDepthInt -eq [int]::MaxValue) { "Unlimited" } else { $MaxDepthInt }

Write-Host "Starting FOLDER-ONLY ACL audit (NTFS + Share)..."
Write-Host "Root path     : $RootPath"
Write-Host "Max depth     : $maxDepthDisplay"
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
            $server    = $matches[1]
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

# Global counters & CSV state
$idCounter = 0
$script:CsvInitialized = $false

# Helper: write one ACE row to CSV (streaming, header once)
function Write-AceRow {
    param(
        [pscustomobject]$Row,
        [string]$CsvPath
    )

    if (-not $script:CsvInitialized) {
        $Row | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        $script:CsvInitialized = $true
    } else {
        $Row | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 -Append
    }
}

# Helper: compute depth for a folder relative to root
function Get-FolderDepth {
    param(
        [string]$FolderPath,
        [string]$RootPath
    )

    $normalizedFolder = $FolderPath.TrimEnd('\')
    $normalizedRoot   = $RootPath.TrimEnd('\')

    $folderDepth = 0
    if ($normalizedFolder.Length -gt $normalizedRoot.Length -and
        $normalizedFolder.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {

        $relative = $normalizedFolder.Substring($normalizedRoot.Length).TrimStart('\')
        if ($relative) {
            $folderDepth = $relative.Split('\').Count
        }
    }

    return $folderDepth
}

# Helper: process a single folder (get ACL, emit rows)
function Process-Folder {
    param(
        [System.IO.DirectoryInfo]$Folder,
        [int]$Depth,
        [pscustomobject]$ShareInfo,
        [string]$CsvPath,
        [ref]$IdCounterRef,
        [System.Collections.Generic.List[psobject]]$ErrorsList
    )

    Write-Progress -Activity "Auditing folder ACLs" -Status $Folder.FullName

    try {
        $acl = Get-Acl -LiteralPath $Folder.FullName -ErrorAction Stop
    } catch {
        $errObj = [pscustomobject]@{
            Path      = $Folder.FullName
            Error     = $_.Exception.Message
            TimeStamp = Get-Date
        }
        $ErrorsList.Add($errObj) | Out-Null
        Write-Log "Failed to get ACL for '$($Folder.FullName)': $($_.Exception.Message)" "ERROR"
        return
    }

    # Use -Path instead of -LiteralPath for PowerShell 5.1 compatibility
    # -LiteralPath was added in PowerShell 6.0, but many users are on Windows PowerShell 5.1
    $parentFolder = Split-Path -Path $Folder.FullName -Parent
    $aceOrder = 0

    foreach ($ace in $acl.Access) {
        $aceOrder++
        $IdCounterRef.Value++

        $permissionLevel = Get-PermissionLevel -Rights $ace.FileSystemRights
        $aceType         = if ($ace.IsInherited) { "Inherited" } else { "Explicit" }

        $row = [pscustomobject]@{
            ID                 = $IdCounterRef.Value
            Path               = $Folder.FullName
            ItemType           = "Folder"
            ParentFolder       = $parentFolder
            FolderDepth        = $Depth
            ShareServer        = $ShareInfo.ShareServer
            ShareName          = $ShareInfo.ShareName
            ShareLocalPath     = $ShareInfo.ShareLocalPath
            ShareAccessSummary = $ShareInfo.ShareAccessSummary
            ACEOrder           = $aceOrder
            ACEType            = $aceType
            Identity           = $ace.IdentityReference.Value
            FileSystemRights   = $ace.FileSystemRights.ToString()
            PermissionLevel    = $permissionLevel
            AccessControlType  = $ace.AccessControlType.ToString()
            InheritanceFlags   = $ace.InheritanceFlags.ToString()
            PropagationFlags   = $ace.PropagationFlags.ToString()
            IsInherited        = $ace.IsInherited
            Owner              = $acl.Owner
            LastWriteTime      = $Folder.LastWriteTime
            CreationTime       = $Folder.CreationTime
        }

        Write-AceRow -Row $row -CsvPath $CsvPath
    }
}

Write-Log "Enumerating and auditing folders under '$RootPath' with MaxDepth = $maxDepthDisplay ..."

# Process root folder
try {
    $rootItem = Get-Item -LiteralPath $RootPath -ErrorAction Stop
    if (-not ($rootItem -is [System.IO.DirectoryInfo])) {
        Write-Error "Root path '$RootPath' is not a folder."
        exit 1
    }
} catch {
    Write-Log "Failed to access root path '$RootPath': $($_.Exception.Message)" "ERROR"
    exit 1
}

# Root depth is always 0
Process-Folder -Folder $rootItem -Depth 0 -ShareInfo $shareInfo -CsvPath $OutputCsvPath -IdCounterRef ([ref]$idCounter) -ErrorsList $errors

# If MaxDepthInt is 0, we stop at the root
if ($MaxDepthInt -gt 0) {
    # Stream all subfolders and filter by depth
    Get-ChildItem -LiteralPath $RootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $folderDepth = Get-FolderDepth -FolderPath $_.FullName -RootPath $RootPath

            if ($folderDepth -le $MaxDepthInt) {
                Process-Folder -Folder $_ -Depth $folderDepth -ShareInfo $shareInfo -CsvPath $OutputCsvPath -IdCounterRef ([ref]$idCounter) -ErrorsList $errors
            }
        }
}

Write-Log "Finished collecting ACLs. CSV written to '$OutputCsvPath'"

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
Write-Host "Total ACE rows: $idCounter"
Write-Host "Audit complete."

try {
    Stop-Transcript | Out-Null
} catch {
    Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
}
