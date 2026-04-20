#Requires -Version 5.1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Continue"

$script:DebugMode    = $false
$script:MaxSteps     = 12
$script:MaxOutput    = 24000
$script:MaxHistory   = 60
$script:History      = @()
$C = @{ I="Cyan"; S="Green"; E="Red"; W="Yellow"; M="Magenta"; A="Blue"; D="DarkGray" }

function Write-C { param($Msg, $Col="White"); Write-Host $Msg -ForegroundColor $Col }

function Show-Banner {
    Clear-Host
    Write-C "`n╔══════════════════════════════════════════════════════════╗" $C.I
    Write-C "║      Intelligent PowerShell  ·  Agentic AI Shell  v3.0   ║" $C.I
    Write-C "╚══════════════════════════════════════════════════════════╝`n" $C.I
    Write-C "  Commands: install | history | clear | debug | exit`n" $C.W
}

function Read-Field {
    param($Prompt, $Default="", [switch]$Secret)
    while ($true) {
        $label = if ($Default) { "$Prompt [$Default]: " } else { "${Prompt}: " }
        Write-Host $label -NoNewline -ForegroundColor $C.W
        $v = if ($Secret) {
            $s = Read-Host -AsSecureString
            [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
        } else { Read-Host }
        $v = $v.Trim()
        if ($v)       { return $v }
        if ($Default) { return $Default }
        Write-C "  This field is required." $C.E
    }
}

function Save-Config {
    [Environment]::SetEnvironmentVariable("OPENAI_API_KEY",      $env:OPENAI_API_KEY,      "User")
    [Environment]::SetEnvironmentVariable("OPENAI_API_ENDPOINT", $env:OPENAI_API_ENDPOINT, "User")
    [Environment]::SetEnvironmentVariable("OPENAI_MODEL",        $env:OPENAI_MODEL,        "User")
    $dir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $p   = [Environment]::GetEnvironmentVariable("Path","User")
    if ($p -notlike "*$dir*") { [Environment]::SetEnvironmentVariable("Path","$p;$dir".Trim(';'),"User") }
    Write-C "  ✓ Configuration saved permanently.`n" $C.S
}

function Test-Config {
    $script:PSVer = "{0}.{1}" -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor
    $changed = $false
    if (-not $env:OPENAI_API_KEY) {
        $env:OPENAI_API_KEY = Read-Field "OpenAI API Key" -Secret; $changed = $true
    }
    if (-not $env:OPENAI_API_ENDPOINT) {
        $env:OPENAI_API_ENDPOINT = Read-Field "API Endpoint" "https://api.openai.com/v1/chat/completions"; $changed = $true
    }
    if (-not $env:OPENAI_MODEL) {
        $env:OPENAI_MODEL = Read-Field "Model" "gpt-4o"; $changed = $true
    }
    $script:Endpoint = $env:OPENAI_API_ENDPOINT
    $script:Model    = $env:OPENAI_MODEL
    if ($changed) {
        Write-Host "  Save permanently? (y/n): " -NoNewline -ForegroundColor $C.W
        if ((Read-Host).Trim() -match "^(y|yes)$") { Save-Config }
        else { Write-C "  Session-only. Run 'install' to save later.`n" $C.W }
    }
    Write-C "✓ Key: set | Endpoint: $script:Endpoint | Model: $script:Model | PS: $script:PSVer`n" $C.S
}

function Install-Config {
    Write-C "`n─── Reconfigure ───" $C.I
    Write-C "  API Key: $(if($env:OPENAI_API_KEY){'[set]'}else{'[not set]'})" $C.D
    $env:OPENAI_API_KEY      = Read-Field "New API Key (Enter to keep)" $env:OPENAI_API_KEY -Secret
    $env:OPENAI_API_ENDPOINT = Read-Field "Endpoint" $script:Endpoint
    $env:OPENAI_MODEL        = Read-Field "Model"    $script:Model
    $script:Endpoint = $env:OPENAI_API_ENDPOINT
    $script:Model    = $env:OPENAI_MODEL
    Save-Config
}

function Add-History {
    param($Role, $Content)
    if ($Content.Length -gt $script:MaxOutput) { $Content = $Content.Substring(0,$script:MaxOutput) + "`n...[truncated]" }
    $script:History += @{ role=$Role; content=$Content }
    $ns = $script:History | Where-Object { $_.role -ne "system" }
    if ($ns.Count -gt $script:MaxHistory * 2) {
        $script:History = @($script:History | Where-Object { $_.role -eq "system" }) + ($ns | Select-Object -Last ($script:MaxHistory * 2))
    }
}

function Show-History {
    Write-C "`n═══ HISTORY ═══" $C.I
    $items = $script:History | Where-Object { $_.role -ne "system" }
    if (-not $items) { Write-C "  (empty)" $C.W; return }
    for ($i=0; $i -lt $items.Count; $i++) {
        $col = if ($items[$i].role -eq "user") { $C.I } else { $C.A }
        Write-C "`n[$(if($items[$i].role -eq 'user'){'User'}else{'Agent'}) #$($i+1)]" $col
        Write-Host $items[$i].content
    }
    Write-C "`n════════════════`n" $C.I
}

function Invoke-AI {
    $body = @{
        model           = $script:Model
        messages        = @($script:History | ForEach-Object { @{role=$_.role; content=$_.content} })
        temperature     = 0.2
        response_format = @{ type="json_object" }
    } | ConvertTo-Json -Depth 8

    if ($script:DebugMode) { Write-C "`n─── REQUEST ───`n$body`n" $C.W }

    $resp = Invoke-RestMethod -Uri $script:Endpoint -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
        -Headers @{ Authorization="Bearer $env:OPENAI_API_KEY" } -ContentType "application/json; charset=utf-8"

    $out = $resp.choices[0].message.content
    if ($script:DebugMode) { Write-C "─── RESPONSE ───`n$out`n" $C.W }
    return $out
}

function Get-FirstJson {
    param($Raw)
    try { return $Raw | ConvertFrom-Json } catch {}
    $d=0; $s=-1
    for ($i=0; $i -lt $Raw.Length; $i++) {
        if ($Raw[$i] -eq '{') { if ($d -eq 0) { $s=$i }; $d++ }
        elseif ($Raw[$i] -eq '}') { $d--; if ($d -eq 0 -and $s -ge 0) { return $Raw.Substring($s,$i-$s+1) | ConvertFrom-Json } }
    }
    throw "No JSON found in response"
}

function Invoke-Command-Safe {
    param($Cmd)
    Write-C "`n  ► $Cmd" $C.M
    $global:LASTEXITCODE = 0
    $out = Invoke-Expression $Cmd 2>&1 | Out-String
    if ($global:LASTEXITCODE -gt 0) { return @{ Success=$false; Error="Exit code $global:LASTEXITCODE`n$out" } }
    return @{ Success=$true; Output=$out.Trim() }
}

function Invoke-AgentTurn {
    Write-Host ""
    for ($step=1; $step -le $script:MaxSteps; $step++) {
        Write-C "  🤖 Thinking (step $step)..." $C.D

        $raw      = Invoke-AI
        $response = Get-FirstJson $raw
        $action   = ($response.action + "").ToLower().Trim()

        if ($script:DebugMode -and $response.thought) { Write-C "  [thought] $($response.thought)" $C.D }

        switch ($action) {
            "done" {
                $answer = if ($response.answer) { $response.answer } else { $response.explanation }
                Write-C "`n💬 " $C.A; Write-Host $answer
                Add-History "assistant" $answer
                return
            }
            "ask" {
                Write-C "`n❓ $($response.question)" $C.W
                Add-History "assistant" "[ASK] $($response.question)"
                Write-Host "`nYou: " -NoNewline -ForegroundColor $C.I
                $ans = (Read-Host).Trim(); if (-not $ans) { $ans = "(no answer)" }
                Add-History "user" "[CLARIFICATION] $ans"
            }
            "run" {
                $cmd = ($response.command + "").Trim()
                if (-not $cmd) { Write-C "Agent returned 'run' with no command." $C.E; return }
                if ($response.thought -and -not $script:DebugMode) { Write-C "  💭 $($response.thought)" $C.D }
                $result = Invoke-Command-Safe $cmd
                $status = if ($result.Success) { $tag="OUTPUT"; Write-C "  ✓ Done" $C.S; $result.Output } else { $tag="ERROR"; Write-C "  ✗ $($result.Error)" $C.E; $result.Error }
                Add-History "assistant" "[STEP $step] RAN: $cmd`n[$tag]`n$status"
            }
            default {
                $fallback = if ($response.answer) { $response.answer } elseif ($response.explanation) { $response.explanation } else { $raw }
                Write-C "`n💬 " $C.A; Write-Host $fallback
                Add-History "assistant" $fallback
                return
            }
        }
    }
    Write-C "`n⚠️  Step limit ($script:MaxSteps) reached." $C.W
}

function Start-Shell {
    Show-Banner
    Test-Config

    Add-History "system" @"
You are an autonomous PowerShell agent on a live Windows machine (PS $script:PSVer).
Resolve the user's request by running as many commands as needed, inspecting results, and iterating.

Always respond with a single JSON object using one of these actions:

Run a command:
{ "action": "run", "thought": "<reasoning>", "command": "<powershell command>" }

Ask the user:
{ "action": "ask", "thought": "<why>", "question": "<question>" }

Finish:
{ "action": "done", "thought": "<summary>", "answer": "<final answer>" }

Rules:
- Use "thought" to reason before acting.
- Chain commands: use output from step N to decide step N+1.
- Self-correct on errors; try a different approach.
- Prefer read-only commands unless user asks to change something.
- Warn before destructive actions (Remove-Item, Stop-Service, etc.).
- Answer knowledge questions directly with "done" — no command needed.
- Never fabricate output; only report what the system actually returned.
"@

    Write-C "Agent ready. Ask me anything.`n" $C.S

    while ($true) {
        Write-Host "You: " -NoNewline -ForegroundColor $C.I
        $input = Read-Host
        if (-not $input.Trim()) { continue }
        switch -Regex ($input.ToLower().Trim()) {
            "^(exit|quit)$" { Write-C "`nGoodbye! 👋`n" $C.S; return }
            "^install$"     { Install-Config; continue }
            "^history$"     { Show-History;   continue }
            "^clear$"       { $script:History = @($script:History | Where-Object {$_.role -eq "system"}); Write-C "`n✓ Cleared`n" $C.S; continue }
            "^debug$"       { $script:DebugMode = -not $script:DebugMode; Write-C "`nDebug $(if($script:DebugMode){'ON'}else{'OFF'})`n" $C.W; continue }
        }
        Add-History "user" $input
        Invoke-AgentTurn
    }
}

Start-Shell
