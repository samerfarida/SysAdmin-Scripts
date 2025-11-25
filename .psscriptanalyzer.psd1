@{
    # Exclude specific rules for this script
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',      # Write-Host is needed for interactive prompts
        'PSUseApprovedVerbs',         # Process-Folder is an internal helper function
        'PSAvoidOverwritingBuiltInCmdlets'  # Write-Log is a common pattern
    )
}

