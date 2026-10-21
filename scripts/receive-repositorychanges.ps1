[CmdletBinding()]
param([string] $ConfigPath)

. (Join-Path $PSScriptRoot 'GitRepository.Common.ps1')
try {
    Initialize-RepositorySync $ConfigPath
    try { Receive-RepositoryChanges }
    finally { Restore-RepositoryPrivateBranch }
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
