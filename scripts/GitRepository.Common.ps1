Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-RepositoryGit {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [switch] $AllowFailure,
        [string[]] $InputLines
    )
    # Capture native stderr without Windows PowerShell turning it into a terminating error.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = $null
        if ($PSBoundParameters.ContainsKey('InputLines')) {
            $output = @($InputLines | & git -C $script:RepositoryRoot @Arguments 2>&1)
        } else {
            $output = @(& git -C $script:RepositoryRoot @Arguments 2>&1)
        }
        $code = $global:LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $lines = @($output | ForEach-Object { $_.ToString() })
    if ($null -eq $code) { throw "Unable to start git $($Arguments[0])." }
    $result = [pscustomobject]@{ ExitCode = $code; Lines = $lines; Text = ($lines -join "`n") }
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments[0]) failed (exit $code).`n$($result.Text)"
    }
    return $result
}

function Initialize-RepositorySync {
    param([string] $ConfigPath)
    $script:RepositoryRoot = Split-Path $PSScriptRoot -Parent
    $script:RepositoryRoot = (Invoke-RepositoryGit @('rev-parse', '--show-toplevel')).Text
    if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'git-repository.config.json' }
    $script:SyncConfig = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # Do this before switching branches, fetching or changing refs.
    $branch = (Invoke-RepositoryGit @('symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFailure).Text
    if ($branch -ne $script:SyncConfig.privateBranch) {
        throw "Run this script on branch '$($script:SyncConfig.privateBranch)' (current: '$branch')."
    }
    if ($script:SyncConfig.publicBranch -eq $script:SyncConfig.privateBranch) {
        throw 'The public and private branches must differ.'
    }
    foreach ($name in @($script:SyncConfig.publicBranch, $script:SyncConfig.privateBranch, $script:SyncConfig.remoteBranch)) {
        $null = Invoke-RepositoryGit @('check-ref-format', '--branch', $name)
    }
    $null = Invoke-RepositoryGit @('remote', 'get-url', $script:SyncConfig.remote)
    $script:PublicRef = 'refs/heads/' + $script:SyncConfig.publicBranch
    $script:PrivateRef = 'refs/heads/' + $script:SyncConfig.privateBranch
    $script:RemoteRef = 'refs/remotes/' + $script:SyncConfig.remote + '/' + $script:SyncConfig.remoteBranch
    $null = Invoke-RepositoryGit @('rev-parse', '--verify', "$script:PublicRef^{commit}")
    Assert-RepositoryClean
    Assert-PrivateHistory

    $values = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rule in $script:SyncConfig.protectedValues) {
        $source = (Invoke-RepositoryGit @('show', ($rule.commit + ':' + $rule.path))).Text
        $match = [regex]::Match($source, $rule.pattern)
        if (-not $match.Success -or -not $match.Groups['value'].Success) {
            throw 'Unable to load a protected value from the configured private commit.'
        }
        $value = $match.Groups['value'].Value
        $values.Add($value)
        if ($rule.decodeBase64) {
            $values.Add([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)))
        }
    }
    foreach ($value in $values) {
        if ([string]::IsNullOrWhiteSpace($value) -or $value.Contains("`n") -or $value.Contains("`r")) {
            throw 'Protected values must be nonempty single-line strings.'
        }
    }
    $script:ProtectedValues = @($values | Select-Object -Unique)
}

function Test-RepositoryOperation {
    foreach ($name in @('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer')) {
        $path = (Invoke-RepositoryGit @('rev-parse', '--git-path', $name)).Text
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $script:RepositoryRoot $path }
        if (Test-Path -LiteralPath $path) { return $true }
    }
    return $false
}

function Assert-RepositoryClean {
    if (Test-RepositoryOperation) { throw 'Finish or abort the current Git operation first.' }
    $status = (Invoke-RepositoryGit @('status', '--porcelain=v1', '--untracked-files=normal')).Text
    if ($status) { throw "Commit or stash all changes before running this script.`n$status" }
}

function Test-RepositoryAncestor {
    param([string] $Ancestor, [string] $Descendant)
    $result = Invoke-RepositoryGit @('merge-base', '--is-ancestor', $Ancestor, $Descendant) -AllowFailure
    if ($result.ExitCode -gt 1) { throw "Cannot inspect commit ancestry.`n$($result.Text)" }
    return ($result.ExitCode -eq 0)
}

function Assert-PrivateHistory {
    foreach ($commit in $script:SyncConfig.privateCommits) {
        $null = Invoke-RepositoryGit @('rev-parse', '--verify', "$commit^{commit}")
        if (-not (Test-RepositoryAncestor $commit $script:PrivateRef)) {
            throw "Configured private commit $commit is missing from the private branch."
        }
        if (Test-RepositoryAncestor $commit $script:PublicRef) {
            throw "Refusing to publish: public branch contains private commit $commit."
        }
    }
}

function Update-RepositorySubmodules {
    $null = Invoke-RepositoryGit @('submodule', 'update', '--init', '--recursive')
}

function Switch-RepositoryBranch {
    param([string] $Branch)
    $null = Invoke-RepositoryGit @('switch', $Branch)
    Update-RepositorySubmodules
}

function Stop-RepositoryConflict {
    param([ValidateSet('cherry-pick', 'merge')] [string] $Operation)
    $branch = (Invoke-RepositoryGit @('branch', '--show-current')).Text
    $status = (Invoke-RepositoryGit @('status', '--short')).Text
    throw @"
Conflict on branch '$branch'. Nothing was pushed. The conflict has been left for you to resolve.
$status
Resolve and stage the files, then run: git $Operation --continue
Or cancel this operation with: git $Operation --abort
After finishing or aborting, switch back to '$($script:SyncConfig.privateBranch)' before rerunning the script.
"@
}

function Restore-RepositoryPrivateBranch {
    # Preserve an interrupted operation and all user edits for manual recovery.
    if (-not (Test-RepositoryOperation)) {
        $branch = (Invoke-RepositoryGit @('branch', '--show-current')).Text
        if ($branch -ne $script:SyncConfig.privateBranch) {
            $status = (Invoke-RepositoryGit @('status', '--porcelain=v1')).Text
            if (-not $status) { Switch-RepositoryBranch $script:SyncConfig.privateBranch }
        }
    }
}

function Assert-PublicCommitsSafe {
    param([string] $Base)
    Assert-PrivateHistory
    $commits = (Invoke-RepositoryGit @('rev-list', "$Base..$script:PublicRef")).Lines
    foreach ($commit in $commits) {
        $message = (Invoke-RepositoryGit @('cat-file', 'commit', $commit)).Text
        foreach ($value in $script:ProtectedValues) {
            if ($message.Contains($value)) { throw "Protected value found in commit message $commit. Push blocked." }
        }
        if ($script:ProtectedValues.Count -gt 0) {
            # Feed values through stdin: never print them or place them in command-line arguments.
            $scan = Invoke-RepositoryGit @('grep', '--fixed-strings', '--files-with-matches', '-f', '-', $commit, '--') -InputLines $script:ProtectedValues -AllowFailure
            if ($scan.ExitCode -eq 0) { throw "Protected value found in the tree of commit $commit. Push blocked." }
            if ($scan.ExitCode -ne 1) { throw "Cannot scan commit $commit. Push blocked." }
        }
        foreach ($rule in $script:SyncConfig.forbiddenPublicContent) {
            $exists = Invoke-RepositoryGit @('cat-file', '-e', ($commit + ':' + $rule.path)) -AllowFailure
            if ($exists.ExitCode -ne 0) { continue }
            $content = (Invoke-RepositoryGit @('show', ($commit + ':' + $rule.path))).Text
            if ([regex]::IsMatch($content, $rule.pattern)) {
                throw "Forbidden public configuration in commit $commit ($($rule.path)). Push blocked."
            }
        }
    }
}

function Publish-RepositoryChanges {
    # git cherry recognizes patches already copied to main even though their hashes differ.
    $alreadyApplied = @{}
    foreach ($line in (Invoke-RepositoryGit @('cherry', $script:PublicRef, $script:PrivateRef)).Lines) {
        if ($line -match '^- ([0-9a-f]+)$') { $alreadyApplied[$Matches[1]] = $true }
    }
    # -x records the source even when a manual resolution changes the patch.
    $messages = (Invoke-RepositoryGit @('log', '--format=%B', $script:PublicRef)).Text
    foreach ($match in [regex]::Matches($messages, '(?m)^\(cherry picked from commit ([0-9a-f]{40,64})\)\s*$')) {
        $alreadyApplied[$match.Groups[1].Value] = $true
    }
    $privateCommits = @($script:SyncConfig.privateCommits)
    $candidates = (Invoke-RepositoryGit @('rev-list', '--reverse', '--topo-order', "$script:PublicRef..$script:PrivateRef")).Lines
    Switch-RepositoryBranch $script:SyncConfig.publicBranch
    foreach ($commit in $candidates) {
        if ($commit -in $privateCommits -or $alreadyApplied.ContainsKey($commit)) { continue }
        $parents = (Invoke-RepositoryGit @('rev-list', '--parents', '-n', '1', $commit)).Text.Split(' ')
        if ($parents.Count -lt 2) { throw "Cannot replay a root commit: $commit" }
        $diff = Invoke-RepositoryGit @('diff', '--quiet', $parents[1], $commit, '--') -AllowFailure
        if ($diff.ExitCode -eq 0) { continue }
        if ($diff.ExitCode -ne 1) { throw "Cannot inspect commit $commit." }
        $arguments = @('cherry-pick', '-x', '--allow-empty')
        if ($parents.Count -gt 2) { $arguments += @('-m', '1') }
        $result = Invoke-RepositoryGit ($arguments + $commit) -AllowFailure
        if ($result.ExitCode -ne 0) {
            $unmerged = (Invoke-RepositoryGit @('ls-files', '--unmerged')).Text
            if ($unmerged) { Stop-RepositoryConflict 'cherry-pick' }
            $pending = Invoke-RepositoryGit @('rev-parse', '--verify', 'CHERRY_PICK_HEAD') -AllowFailure
            $status = (Invoke-RepositoryGit @('status', '--porcelain=v1')).Text
            if ($pending.ExitCode -eq 0 -and -not $status) {
                # A merge from an earlier pull can be wholly present on main already.
                $null = Invoke-RepositoryGit @('cherry-pick', '--skip')
            } else {
                throw "Cannot replay commit $commit.`n$($result.Text)"
            }
        }
        Update-RepositorySubmodules
    }
    $fetchSpec = 'refs/heads/' + $script:SyncConfig.remoteBranch + ':' + $script:RemoteRef
    $null = Invoke-RepositoryGit @('fetch', '--no-tags', $script:SyncConfig.remote, $fetchSpec)
    Assert-PublicCommitsSafe $script:RemoteRef
    if (-not (Test-RepositoryAncestor $script:RemoteRef $script:PublicRef)) {
        throw 'Remote main has new commits. Run get-gitrepository.ps1 before retrying the push.'
    }
    $pushSpec = $script:PublicRef + ':refs/heads/' + $script:SyncConfig.remoteBranch
    $null = Invoke-RepositoryGit @('push', $script:SyncConfig.remote, $pushSpec)
    Switch-RepositoryBranch $script:SyncConfig.privateBranch
    Write-Host "Published '$($script:SyncConfig.publicBranch)'; back on '$($script:SyncConfig.privateBranch)'. Private commits were excluded."
}

function Receive-RepositoryChanges {
    $oldPublic = (Invoke-RepositoryGit @('rev-parse', $script:PublicRef)).Text
    Switch-RepositoryBranch $script:SyncConfig.publicBranch
    $result = Invoke-RepositoryGit @('pull', '--no-rebase', '--no-edit', $script:SyncConfig.remote, $script:SyncConfig.remoteBranch) -AllowFailure
    if ($result.ExitCode -ne 0) {
        if ((Invoke-RepositoryGit @('ls-files', '--unmerged')).Text) { Stop-RepositoryConflict 'merge' }
        throw "git pull failed.`n$($result.Text)"
    }
    Update-RepositorySubmodules
    Assert-PublicCommitsSafe $oldPublic
    Switch-RepositoryBranch $script:SyncConfig.privateBranch
    $result = Invoke-RepositoryGit @('merge', '--no-edit', $script:PublicRef) -AllowFailure
    if ($result.ExitCode -ne 0) {
        if ((Invoke-RepositoryGit @('ls-files', '--unmerged')).Text) { Stop-RepositoryConflict 'merge' }
        throw "Cannot merge public updates into the private branch.`n$($result.Text)"
    }
    Update-RepositorySubmodules
    Write-Host "Updated '$($script:SyncConfig.privateBranch)' from '$($script:SyncConfig.publicBranch)'; private changes retained."
}
