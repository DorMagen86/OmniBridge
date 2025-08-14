param(
    [string]$CommitMessage
)

$ErrorActionPreference = 'Stop'

# ===== Config =====
$Owner        = 'DorMagen86'
$Repo         = 'OmniBridge'
$Branch       = 'main'
$WorkflowFile = 'deploy-pages.yml'
$TimeoutMin   = 15
$PollSec      = 10

function Say([string]$msg, [string]$color='Gray') { Write-Host -ForegroundColor $color $msg }

# Ensure modern TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Ensure git repo
git rev-parse --is-inside-work-tree *>$null

# Commit if needed
$hasChanges = ((git status --porcelain) | Measure-Object).Count -gt 0
if (-not $CommitMessage -or $CommitMessage.Trim().Length -eq 0) {
    $CommitMessage = 'Auto update ' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
}
if ($hasChanges) {
    Say ("[gitpub] Committing: {0}" -f $CommitMessage) 'Cyan'
    git add -A
    git commit -m "$CommitMessage" | Out-Null
} else {
    Say '[gitpub] No local changes.' 'Yellow'
}

# Sync & push
Say ("[gitpub] Pull --rebase origin/{0}" -f $Branch) 'Gray'
git pull --rebase origin $Branch | Out-Null

Say ("[gitpub] Push origin/{0}" -f $Branch) 'Gray'
git push origin $Branch | Out-Null

$HeadSha = (git rev-parse HEAD).Trim()
Say ("[gitpub] Pushed commit: {0}" -f $HeadSha) 'DarkGray'

# ===== Build GitHub Actions API URL robustly =====
$apiBase = "https://api.github.com/repos/$Owner/$Repo/actions/workflows/$WorkflowFile/runs"
$ub = [System.UriBuilder]::new($apiBase)
$ub.Query = "branch=$Branch&per_page=20"
$api = $ub.Uri.AbsoluteUri
Say ("[gitpub] API URL = {0}" -f $api) 'DarkGray'

$headers = @{ 'User-Agent' = 'gitpub-script' }
# Optional token to avoid rate limits (set env var GH_TOKEN or GITHUB_TOKEN)
if ($env:GH_TOKEN) { $headers['Authorization'] = "Bearer $env:GH_TOKEN" }
elseif ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

# ===== Poll GitHub Actions =====
Say '[gitpub] Waiting for GitHub Actions run...' 'Gray'
$deadline = (Get-Date).AddMinutes($TimeoutMin)
while ($true) {
    try {
        $resp = Invoke-RestMethod -Uri $api -Headers $headers -Method GET -ErrorAction Stop
        $run  = $resp.workflow_runs | Where-Object { $_.head_sha -eq $HeadSha } | Select-Object -First 1
        if ($run) {
            if ($run.status -eq 'completed') {
                if ($run.conclusion -eq 'success') {
                    Say '[gitpub] Actions completed successfully.' 'Green'
                    break
                } else {
                    Say ("[gitpub] Actions failed. Logs: {0}" -f $run.html_url) 'Red'
                    exit 1
                }
            }
        }
    } catch {
        Say ("[gitpub] API error: {0}" -f $_.Exception.Message) 'Yellow'
    }

    if ((Get-Date) -gt $deadline) {
        Say ("[gitpub] Timeout after {0} minutes." -f $TimeoutMin) 'Yellow'
        exit 2
    }

    Start-Sleep -Seconds $PollSec
}

# ===== Check GitHub Pages HTTP =====
$pagesUrl = "https://$Owner.github.io/$Repo/"
try {
    $r = Invoke-WebRequest -Uri $pagesUrl -UseBasicParsing -TimeoutSec 15
    if ($r.StatusCode -eq 200) {
        Say ("[gitpub] Site is live: {0}" -f $pagesUrl) 'Cyan'
        [console]::Beep(800,300); [console]::Beep(1000,300); [console]::Beep(1200,400)
    } else {
        Say ("[gitpub] Site responded with status {0}" -f $r.StatusCode) 'Yellow'
    }
} catch {
    Say '[gitpub] Could not reach site.' 'Red'
    [console]::Beep(400,500); [console]::Beep(300,500)
}
