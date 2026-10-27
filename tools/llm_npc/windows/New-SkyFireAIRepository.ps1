#Requires -Version 5.1
<#
.SYNOPSIS
Creates an independent GitHub copy of the tested SkyFire+LLM feature branch.
.DESCRIPTION
Runs on a Windows developer computer with Git and GitHub CLI authenticated.
Never pushes to or modifies mrcool72/SkyFire_548. Creates a new PRIVATE GitHub
repository with the FULL SkyFire codebase and the feature commits as main.
The GitHub CLI cannot run in the ChatGPT connector: an operator must run this.
.EXAMPLE
.\tools\llm_npc\windows\New-SkyFireAIRepository.ps1
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$')]
    [string] $NewRepo = 'mrcool72/SkyFire_548_AI',

    [ValidatePattern('^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$')]
    [string] $SourceRepo = 'mrcool72/SkyFire_548',

    [string] $FeatureBranch = 'feature/llm-npc-dialogue-bridge-20261027',

    [string] $Destination = 'C:\SkyFire_548_AI',

    [switch] $Public
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Tool([string] $CommandName) {
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw ('Missing required tool: {0}. Install it and retry.' -f $CommandName)
    }
}

function Run-Native([string] $Executable, [string[]] $Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw ('{0} failed with exit code {1}' -f $Executable, $LASTEXITCODE)
    }
}

Require-Tool 'git'
Require-Tool 'gh'
Run-Native 'gh' @('auth', 'status')

if ($NewRepo -eq $SourceRepo) {
    throw 'The new repository MUST have a different name from the original.'
}
if (Test-Path -LiteralPath $Destination) {
    throw ('Destination already exists: {0}. Choose an unused directory.' -f $Destination)
}

# Ensure the operator has not already created this repository. GitHub CLI
# exits nonzero when the repository cannot be found or is not accessible.
& gh repo view $NewRepo --json nameWithOwner 1>$null 2>$null
if ($LASTEXITCODE -eq 0) {
    throw ('Refusing to overwrite an existing repository: {0}' -f $NewRepo)
}

$parent = Split-Path -Parent $Destination
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

Write-Host 'Cloning the complete SkyFire source and all AI feature files...' -ForegroundColor Cyan
Run-Native 'git' @('clone', '--single-branch', '--branch', $FeatureBranch,
    ('https://github.com/{0}.git' -f $SourceRepo), $Destination)

# Rename only the NEW LOCAL branch. Remove the source remote so subsequent
# pushes cannot accidentally write to the original source repository.
Run-Native 'git' @('-C', $Destination, 'branch', '-m', 'main')
Run-Native 'git' @('-C', $Destination, 'remote', 'remove', 'origin')

$visibility = if ($Public) { '--public' } else { '--private' }
Write-Host ('Creating {0} ({1}) with branch main...' -f $NewRepo, $visibility) -ForegroundColor Cyan
Run-Native 'gh' @('repo', 'create', $NewRepo, $visibility, '--source', $Destination,
    '--remote', 'origin', '--push',
    '--description', 'SkyFire 5.4.8 Windows Server 2022 + experimental LLM NPC integration')

Write-Host ''
Write-Host ('Created independent repository: https://github.com/{0}' -f $NewRepo) -ForegroundColor Green
Write-Host ('Local checkout: {0}' -f $Destination)
Write-Host 'Original repository was not changed.'
Write-Host 'Next: read tools\llm_npc\windows\WINDOWS_SERVER_2022.md in the new checkout.'
