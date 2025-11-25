# Folder ACL & Share Permission Audit Script

`FolderAclAudit.ps1` is a PowerShell-based auditing tool designed to
extract **NTFS folder permissions** and **SMB share permissions** from a
file server. It generates a detailed CSV report including access control
entries, inheritance details, folder metadata, and share-level rights
--- all in one place.

This script is ideal for security audits, least-privilege reviews,
migration prep, and identifying permission drift across large directory
structures.

## Features

-   Audits **folders only** (no files) for faster processing.\
-   Collects **NTFS ACLs** including explicit/inherited ACEs.\
-   Pulls **SMB share permissions** (Full / Change / Read).\
-   Adds a unique **ID column** for easy cross-referencing.\
-   Includes useful metadata:
    -   Parent folder\
    -   Folder depth\
    -   Permission level (Full / Modify / Read / Other)\
    -   ACE order\
    -   Timestamps\
-   Supports UNC paths (`\\Server\\Share`) or local paths.\
-   Fully compatible with **DFS namespaces**.\
-   Logs the entire audit start-to-finish.\
-   Exports results to Excel-friendly CSV files.

## Output Columns

The generated CSV includes the following columns:

    ID
    Path
    ItemType
    ParentFolder
    FolderDepth
    ShareServer
    ShareName
    ShareLocalPath
    ShareAccessSummary
    ACEOrder
    ACEType
    Identity
    FileSystemRights
    PermissionLevel
    AccessControlType
    InheritanceFlags
    PropagationFlags
    IsInherited
    Owner
    LastWriteTime
    CreationTime

Every ACE (Access Control Entry) on every folder becomes **one row** in
the report.

## Prerequisites

-   Windows workstation or server\
-   PowerShell 5+\
-   Network access to the file server\
-   Read permissions on the target folders\
-   For remote share lookups: WinRM / CIM must be allowed

## Usage

Open a PowerShell prompt and run:

``` powershell
.\FolderAclAudit.ps1 -RootPath "\\FileServer01\Finance$"
```

You may optionally specify custom output paths:

``` powershell
.\FolderAclAudit.ps1 `
  -RootPath "\\FileServer01\DeptShares" `
  -OutputCsvPath "C:\Audit\DeptShares_Audit.csv" `
  -LogFilePath "C:\Audit\DeptShares_Audit.log"
```

If no output paths are provided, the script writes both files to the
**current directory**.

## DFS Note

The script works with DFS paths.\
For multi-target DFS namespaces, audit each backend UNC path
individually to detect permission drift.

## Example Output (Single Folder Snippet)

    ID: 1
    Path: \\FS01\Finance\Budgets
    Identity: DOMAIN\FileAdmins
    FileSystemRights: FullControl
    PermissionLevel: FullControl
    ACEType: Explicit
    ShareAccessSummary: DOMAIN\FileAdmins:Allow:Full; Everyone:Allow:Read
    Owner: DOMAIN\FileAdmins
    ...

## License

This script is provided as-is. Modify and extend freely.
