#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Continue"

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────
$script:DebugMode        = $false
$script:MaxHistoryItems  = 60
$script:MaxOutputLength  = 24000
$script:MaxAgentSteps    = 12          # safety brake – max commands per user turn
$script:ConversationHistory = @()

$Colors = @{
    Info    = "Cyan";   Success = "Green";   Error   = "Red"
    Warning = "Yellow"; Command = "Magenta"; AI      = "Blue"; Dim = "DarkGray"
}

# ─────────────────────────────────────────────
# UTILITY
# ─────────────────────────────────────────────

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Show-Banner {
    Clear-Host
    Write-ColorOutput "`n╔══════════════════════════════════════════════════════════════╗" $Colors.Info
    Write-ColorOutput "║        Intelligent PowerShell  ·  Agentic AI Shell  v3.0      ║" $Colors.Info
    Write-ColorOutput "╚══════════════════════════════════════════════════════════════╝`n" $Colors.Info
    Write-ColorOutput "  Commands: install | history | clear | debug | exit`n" $Colors.Warning
}

function Test-Configuration {
    try {
        Write-ColorOutput "Verifying configuration..." $Colors.Info

        if (-not $env:OPENAI_API_KEY) {
            throw "OPENAI_API_KEY not found. Set it with: `$env:OPENAI_API_KEY = 'your-key'"
        }

        $script:PSVersion    = "{0}.{1}" -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor
        $script:ApiEndpoint  = if ($env:OPENAI_API_ENDPOINT) { $env:OPENAI_API_ENDPOINT } else { "https://api.openai.com/v1/chat/completions" }
        $script:Model        = if ($env:OPENAI_MODEL)        { $env:OPENAI_MODEL }        else { "gpt-4o" }

        Write-ColorOutput "✓ Key: set  |  Endpoint: $script:ApiEndpoint  |  Model: $script:Model  |  PS: $script:PSVersion`n" $Colors.Success
        return $true
    }
    catch {
        Write-ColorOutput "ERROR: $($_.Exception.Message)" $Colors.Error
        return $false
    }
}

function Install-Configuration {
    try {
        Write-ColorOutput "`nPersisting to User environment..." $Colors.Info
        if ($env:OPENAI_API_KEY) {
            [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $env:OPENAI_API_KEY, "User")
            Write-ColorOutput "✓ OPENAI_API_KEY saved" $Colors.Success
        }
        [Environment]::SetEnvironmentVariable("OPENAI_API_ENDPOINT", $script:ApiEndpoint, "User")
        [Environment]::SetEnvironmentVariable("OPENAI_MODEL",        $script:Model,       "User")
        Write-ColorOutput "✓ Endpoint and Model saved" $Colors.Success

        $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        $userPath  = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notlike "*$scriptDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$scriptDir".Trim(';'), "User")
            Write-ColorOutput "✓ Added to PATH: $scriptDir" $Colors.Success
        } else {
            Write-ColorOutput "✓ Already in PATH" $Colors.Success
        }
        Write-ColorOutput "`n✓ Done. Open a NEW PowerShell window to pick up saved variables.`n" $Colors.Success
    }
    catch { Write-ColorOutput "ERROR: $($_.Exception.Message)" $Colors.Error }
}

function Add-ToHistory {
    param([string]$Role, [string]$Content)
    if ($Content.Length -gt $script:MaxOutputLength) {
        $Content = $Content.Substring(0, $script:MaxOutputLength) + "`n... [truncated – $($Content.Length) chars total]"
    }
    $script:ConversationHistory += @{ role = $Role; content = $Content }

    # Trim to budget – keep system message
    $nonSystem = $script:ConversationHistory | Where-Object { $_.role -ne "system" }
    if ($nonSystem.Count -gt ($script:MaxHistoryItems * 2)) {
        $sys    = $script:ConversationHistory | Where-Object { $_.role -eq "system" }
        $recent = $nonSystem | Select-Object -Last ($script:MaxHistoryItems * 2)
        $script:ConversationHistory = @($sys) + $recent
    }
}

function Show-History {
    Write-ColorOutput "`n═══ CONVERSATION HISTORY ═══" $Colors.Info
    $items = $script:ConversationHistory | Where-Object { $_.role -ne "system" }
    if ($items.Count -eq 0) { Write-ColorOutput "  (empty)" $Colors.Warning; return }
    for ($i = 0; $i -lt $items.Count; $i++) {
        $label = if ($items[$i].role -eq "user") { "User" } else { "Agent" }
        $color = if ($items[$i].role -eq "user") { $Colors.Info } else { $Colors.AI }
        Write-ColorOutput "`n[$label #$($i+1)]" $color
        Write-Host $items[$i].content
    }
    Write-ColorOutput "`n════════════════════════════`n" $Colors.Info
}

# ─────────────────────────────────────────────
# API CALL
# ─────────────────────────────────────────────

function Invoke-OpenAIChat {
    try {
        $messages = $script:ConversationHistory | ForEach-Object { @{ role = $_.role; content = $_.content } }

        $payload = @{
            model           = $script:Model
            messages        = $messages
            temperature     = 0.2
            response_format = @{ type = "json_object" }
        } | ConvertTo-Json -Depth 8

        if ($script:DebugMode) {
            Write-ColorOutput "`n─── REQUEST ───`n$payload`n───────────────`n" $Colors.Warning
        }

        $headers   = @{ "Authorization" = "Bearer $env:OPENAI_API_KEY"; "Content-Type" = "application/json; charset=utf-8" }
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $response  = Invoke-RestMethod -Uri $script:ApiEndpoint -Method Post -Headers $headers -Body $bodyBytes -ContentType "application/json; charset=utf-8"

        $content = $response.choices[0].message.content

        if ($script:DebugMode) {
            Write-ColorOutput "─── RESPONSE ───`n$content`n────────────────`n" $Colors.Warning
        }
        return $content
    }
    catch {
        Write-ColorOutput "`nAPI ERROR: $($_.Exception.Message)" $Colors.Error
        if ($_.ErrorDetails) { Write-ColorOutput $_.ErrorDetails.Message $Colors.Error }
        return $null
    }
}

# ─────────────────────────────────────────────
# COMMAND EXECUTION
# ─────────────────────────────────────────────

function Invoke-PowerShellCommand {
    param([string]$Command)
    try {
        Write-ColorOutput "`n  ► $Command" $Colors.Command
        $global:LASTEXITCODE = 0
        $output = Invoke-Expression $Command 2>&1 | Out-String
        if ($global:LASTEXITCODE -gt 0) { throw "Exit code $global:LASTEXITCODE" }
        return @{ Success = $true; Output = $output.Trim() }
    }
    catch {
        $msg = $_.Exception.Message
        $type = if ($msg -match "not recognized|no se reconoce") { "CommandNotFound" } else { "ExecutionError" }
        return @{ Success = $false; Error = "$type`: $msg" }
    }
}

# ─────────────────────────────────────────────
# AGENTIC LOOP
# ─────────────────────────────────────────────
#
#  Each turn the agent returns JSON with one of three actions:
#
#    { "action": "run",      "command": "...", "thought": "..." }
#        → execute command, feed result back, keep looping
#
#    { "action": "ask",      "question": "...", "thought": "..." }
#        → ask the user for clarification, then continue
#
#    { "action": "done",     "answer": "...",   "thought": "..." }
#        → final answer to the user, end loop
#
# ─────────────────────────────────────────────

function Invoke-AgentTurn {
    param([string]$UserInput)

    Write-ColorOutput "" "White"

    $stepCount = 0

    while ($stepCount -lt $script:MaxAgentSteps) {
        $stepCount++
        Write-ColorOutput "  🤖 Thinking (step $stepCount)..." $Colors.Dim

        $raw = Invoke-OpenAIChat
        if (-not $raw) {
            Write-ColorOutput "No response from API." $Colors.Error
            return
        }

        # ── Parse (robust) ─────────────────────────────────────────────────────
        # The API occasionally returns extra text or multiple JSON blocks.
        # Strategy: find the FIRST complete {...} object in the raw string.
        $response = $null
        $jsonCandidate = $null

        # 1) Try the whole string first (fast path)
        try {
            $response = $raw | ConvertFrom-Json
        }
        catch {
            # 2) Extract the first balanced {...} block
            $depth = 0; $start = -1; $jsonCandidate = $null
            for ($ci = 0; $ci -lt $raw.Length; $ci++) {
                $ch = $raw[$ci]
                if ($ch -eq '{') {
                    if ($depth -eq 0) { $start = $ci }
                    $depth++
                } elseif ($ch -eq '}') {
                    $depth--
                    if ($depth -eq 0 -and $start -ge 0) {
                        $jsonCandidate = $raw.Substring($start, $ci - $start + 1)
                        break
                    }
                }
            }

            if ($jsonCandidate) {
                try { $response = $jsonCandidate | ConvertFrom-Json }
                catch {
                    Write-ColorOutput "Could not parse agent JSON: $($_.Exception.Message)" $Colors.Error
                    if ($script:DebugMode) { Write-ColorOutput "Raw: $raw" $Colors.Warning }
                    return
                }
            } else {
                Write-ColorOutput "No JSON object found in response." $Colors.Error
                if ($script:DebugMode) { Write-ColorOutput "Raw: $raw" $Colors.Warning }
                return
            }
        }

        $action = ($response.action + "").ToLower().Trim()

        # Optional: show reasoning in debug mode
        if ($script:DebugMode -and $response.thought) {
            Write-ColorOutput "  [thought] $($response.thought)" $Colors.Dim
        }

        # ── DONE ──────────────────────────────────────────────────────────────
        if ($action -eq "done") {
            $answer = if ($response.answer) { $response.answer } else { $response.explanation }
            Write-ColorOutput "`n💬 " $Colors.AI
            Write-Host $answer
            Add-ToHistory -Role "assistant" -Content $answer
            Write-ColorOutput "" "White"
            return
        }

        # ── ASK ───────────────────────────────────────────────────────────────
        if ($action -eq "ask") {
            Write-ColorOutput "`n❓ $($response.question)" $Colors.Warning
            Add-ToHistory -Role "assistant" -Content "[AGENT ASKS] $($response.question)"
            Write-Host ""
            Write-Host "You: " -NoNewline -ForegroundColor $Colors.Info
            $clarification = Read-Host
            if (-not $clarification.Trim()) { $clarification = "(no answer)" }
            Add-ToHistory -Role "user" -Content "[CLARIFICATION] $clarification"
            # Loop continues – agent now has the clarification in history
            continue
        }

        # ── RUN ───────────────────────────────────────────────────────────────
        if ($action -eq "run") {
            $cmd = ($response.command + "").Trim()
            if (-not $cmd) {
                Write-ColorOutput "Agent returned 'run' but no command – stopping." $Colors.Error
                return
            }

            if ($response.thought -and -not $script:DebugMode) {
                Write-ColorOutput "  💭 $($response.thought)" $Colors.Dim
            }

            $result = Invoke-PowerShellCommand -Command $cmd

            if ($result.Success) {
                $out = if ($result.Output) { $result.Output } else { "<no output>" }
                Write-ColorOutput "  ✓ Done" $Colors.Success

                $toolMsg = @"
[STEP $stepCount] RAN: $cmd

[OUTPUT]
$out
"@
                Add-ToHistory -Role "assistant" -Content $toolMsg
            }
            else {
                Write-ColorOutput "  ✗ $($result.Error)" $Colors.Error

                $toolMsg = @"
[STEP $stepCount] RAN: $cmd

[ERROR]
$($result.Error)
"@
                Add-ToHistory -Role "assistant" -Content $toolMsg
            }

            # Loop: agent will see the output and decide what to do next
            continue
        }

        # ── Unknown action fallback ────────────────────────────────────────────
        # Old-style response (plain explanation, no action field) → treat as done
        $fallback = if ($response.answer)      { $response.answer }
                    elseif ($response.explanation) { $response.explanation }
                    else { $raw }

        Write-ColorOutput "`n💬 " $Colors.AI
        Write-Host $fallback
        Add-ToHistory -Role "assistant" -Content $fallback
        Write-ColorOutput "" "White"
        return
    }

    Write-ColorOutput "`n⚠️  Agent reached the step limit ($script:MaxAgentSteps). Stopping." $Colors.Warning
}

# ─────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────

function Start-IntelligentPowerShell {
    Show-Banner
    if (-not (Test-Configuration)) { return }

    # ── System Prompt ────────────────────────────────────────────────────────
    $systemPrompt = @"
You are an autonomous PowerShell agent running on a live Windows machine (PS $script:PSVersion).
Your job is to fully resolve the user's request by executing as many commands as needed, inspecting
results, and iterating — exactly like a skilled human sysadmin would.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESPONSE FORMAT — always return valid JSON with an "action" field:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Execute a command:
{
  "action":  "run",
  "thought": "Why you are running this command (your internal reasoning)",
  "command": "The exact PowerShell command to execute"
}

2. Ask the user for missing information:
{
  "action":   "ask",
  "thought":  "What you need and why",
  "question": "The specific question for the user"
}

3. Finish — when the task is fully done OR the question is answered without needing a command:
{
  "action": "done",
  "thought": "Summary of what you did",
  "answer": "Final response to the user (human-readable, clear, concise)"
}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AGENTIC BEHAVIOUR RULES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

• Plan before acting. Use "thought" to reason step-by-step.
• Explore before concluding. If the first command gives incomplete info, run more.
• Self-correct. If a command errors, understand why and try a different approach.
• Chain commands. Use results from step N to decide what to do in step N+1.
• Never hallucinate output. Only report what the system actually returned.
• Prefer read-only commands unless the user explicitly asks to change things.
• For destructive actions (Delete, Stop-Service, Remove-Item, etc.), always confirm
  intent in "thought" and warn clearly in "answer".
• Keep answers concise. Summarise output; don't dump raw text unless asked.
• If a task genuinely cannot be completed (permissions, missing tool, impossible),
  explain why and suggest alternatives — do not silently fail.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXAMPLES OF MULTI-STEP REASONING:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

User: "Which process is eating the most CPU?"
Step 1 → run: Get-Process | Sort-Object CPU -Desc | Select-Object -First 5 | Format-Table Name,CPU,Id -Auto
Step 2 (after seeing output) → done: "chrome.exe (PID 4821) is using the most CPU at 43%."

User: "Find all log files modified in the last 24h and count the errors in them"
Step 1 → run: Get-ChildItem C:\ -Recurse -Filter *.log -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-24) } | Select-Object FullName
Step 2 → run: <iterate over files found, search for ERROR keyword>
Step 3 → done: "Found 3 log files. Total error lines: 47."

User: "Is port 443 open on google.com?"
Step 1 → run: Test-NetConnection -ComputerName google.com -Port 443
Step 2 → done: "Yes, port 443 is open (TcpTestSucceeded: True)."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GENERAL KNOWLEDGE QUESTIONS (no command needed):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

If the user asks something you can answer from knowledge alone (e.g. "how does X work?"),
respond immediately with action "done" — no need to run a command.
"@

    $script:ConversationHistory = @()
    Add-ToHistory -Role "system" -Content $systemPrompt
    Write-ColorOutput "Agent ready. Ask me anything.`n" $Colors.Success

    while ($true) {
        Write-Host "You: " -NoNewline -ForegroundColor $Colors.Info
        $userInput = Read-Host

        if (-not $userInput.Trim()) { continue }

        switch -Regex ($userInput.ToLower().Trim()) {
            "^(exit|quit)$" { Write-ColorOutput "`nGoodbye! 👋`n" $Colors.Success; return }
            "^install$"     { Install-Configuration; continue }
            "^history$"     { Show-History; continue }
            "^clear$"       {
                $script:ConversationHistory = $script:ConversationHistory | Where-Object { $_.role -eq "system" }
                Write-ColorOutput "`n✓ History cleared`n" $Colors.Success
                continue
            }
            "^debug$"       {
                $script:DebugMode = -not $script:DebugMode
                Write-ColorOutput "`nDebug mode $(if($script:DebugMode){'ON'}else{'OFF'})`n" $Colors.Warning
                continue
            }
        }

        Add-ToHistory -Role "user" -Content $userInput
        Invoke-AgentTurn -UserInput $userInput
    }
}

Start-IntelligentPowerShell
