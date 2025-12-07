#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

# Configuration
$script:DebugMode = $false
$script:MaxHistoryItems = 40
$script:MaxOutputLength = 32000
$script:ConversationHistory = @()

$Colors = @{
    Info = "Cyan"; Success = "Green"; Error = "Red"
    Warning = "Yellow"; Command = "Magenta"; AI = "Blue"
}

# ============================
# UTILITY FUNCTIONS
# ============================

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Show-Banner {
    Clear-Host
    Write-ColorOutput "`n╔════════════════════════════════════════════════════════════╗" $Colors.Info
    Write-ColorOutput "║      Intelligent PowerShell - AI Assistant v1.0            ║" $Colors.Info
    Write-ColorOutput "╚════════════════════════════════════════════════════════════╝`n" $Colors.Info
    Write-ColorOutput "Special commands: install | history | debug | exit/quit`n" $Colors.Warning
}

function Test-Configuration {
    try {
        Write-ColorOutput "Verifying configuration..." $Colors.Info

        if (-not $env:OPENAI_API_KEY) {
            throw "OPENAI_API_KEY not found. Set it with: `$env:OPENAI_API_KEY = 'your-key'"
        }

        $script:PSVersion = "{0}.{1}" -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor
        $script:ApiEndpoint = if ($env:OPENAI_API_ENDPOINT) { $env:OPENAI_API_ENDPOINT } else { "https://api.openai.com/v1/chat/completions" }
        $script:Model = if ($env:OPENAI_MODEL) { $env:OPENAI_MODEL } else { "gpt-4" }

        Write-ColorOutput "✓ API Key: configured | Endpoint: $script:ApiEndpoint | Model: $script:Model | PS: $script:PSVersion`n" $Colors.Success
        return $true
    } catch {
        Write-ColorOutput "ERROR: $($_.Exception.Message)" $Colors.Error
        return $false
    }
}

function Install-Configuration {
    try {
        Write-ColorOutput "`nPersisting configuration to User environment..." $Colors.Info

        # Persist all variables
        if ($env:OPENAI_API_KEY) {
            [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $env:OPENAI_API_KEY, "User")
            Write-ColorOutput "✓ OPENAI_API_KEY saved" $Colors.Success
        }

        [Environment]::SetEnvironmentVariable("OPENAI_API_ENDPOINT", $script:ApiEndpoint, "User")
        [Environment]::SetEnvironmentVariable("OPENAI_MODEL", $script:Model, "User")
        Write-ColorOutput "✓ OPENAI_API_ENDPOINT and OPENAI_MODEL saved" $Colors.Success

        # Add script to PATH
        $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

        if ($userPath -notlike "*$scriptDir*") {
            $newPath = "$userPath;$scriptDir".Trim(';')
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-ColorOutput "✓ Added to PATH: $scriptDir" $Colors.Success
        } else {
            Write-ColorOutput "✓ Already in PATH" $Colors.Success
        }

        Write-ColorOutput "`n✓ Configuration persisted. Open NEW PowerShell to use saved variables.`n" $Colors.Success
    } catch {
        Write-ColorOutput "ERROR installing: $($_.Exception.Message)" $Colors.Error
    }
}

function Add-ToHistory {
    param([string]$Role, [string]$Content)

    if ($Content.Length -gt $script:MaxOutputLength) {
        $Content = $Content.Substring(0, $script:MaxOutputLength) + "`n... [Truncated - $($Content.Length) chars]"
    }

    $script:ConversationHistory += @{ role = $Role; content = $Content }

    $userAssistant = $script:ConversationHistory | Where-Object { $_.role -ne "system" }
    if ($userAssistant.Count -gt ($script:MaxHistoryItems * 2)) {
        $system = $script:ConversationHistory | Where-Object { $_.role -eq "system" }
        $recent = $userAssistant | Select-Object -Last ($script:MaxHistoryItems * 2)
        $script:ConversationHistory = @($system) + $recent
    }
}

function Show-History {
    Write-ColorOutput "`n═══ CONVERSATION HISTORY ═══" $Colors.Info
    $items = $script:ConversationHistory | Where-Object { $_.role -ne "system" }

    if ($items.Count -eq 0) {
        Write-ColorOutput "  (Empty)" $Colors.Warning
        return
    }

    for ($i = 0; $i -lt $items.Count; $i++) {
        $label = if ($items[$i].role -eq "user") { "User" } else { "Assistant" }
        $color = if ($items[$i].role -eq "user") { $Colors.Info } else { $Colors.AI }
        Write-ColorOutput "`n[$label #$($i + 1)]" $color
        Write-ColorOutput $items[$i].content "White"
    }
    Write-ColorOutput "`n═══════════════════════════════`n" $Colors.Info
}

function Invoke-OpenAIChat {
    try {
        $messages = @()
        foreach ($msg in $script:ConversationHistory) {
            $messages += @{
                role    = $msg.role
                content = $msg.content
            }
        }

        $payload = @{
            model            = $script:Model
            messages         = $messages
            max_tokens       = 1500
            temperature      = 0.7
            response_format  = @{ type = "json_object" }
        } | ConvertTo-Json -Depth 6

        if ($script:DebugMode) {
            Write-ColorOutput "`n═══ DEBUG REQUEST ═══`n$payload`n═══════════════════════`n" $Colors.Warning
        }

        $headers = @{
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
            "Content-Type"  = "application/json; charset=utf-8"
        }

        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $response = Invoke-RestMethod -Uri $script:ApiEndpoint -Method Post -Headers $headers -Body $bodyBytes -ContentType "application/json; charset=utf-8"

        # Fix UTF-8 encoding
        $content = $response.choices[0].message.content
        $bytes = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetBytes($content)
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)

        if ($script:DebugMode) {
            Write-ColorOutput "═══ DEBUG RESPONSE ═══`n$content`n═══════════════════════`n" $Colors.Warning
        }

        return $content
    } catch {
        Write-ColorOutput "`nERROR: $($_.Exception.Message)" $Colors.Error
        if ($_.ErrorDetails) { Write-ColorOutput "Details: $($_.ErrorDetails.Message)" $Colors.Error }
        return $null
    }
}

function Invoke-PowerShellCommand {
    param([string]$Command)

    try {
        Write-ColorOutput "`n► Executing: $Command`n" $Colors.Command

        $global:LASTEXITCODE = 0
        $output = Invoke-Expression $Command 2>&1 | Out-String

        if ($global:LASTEXITCODE -gt 0) {
            throw "Exit code: $global:LASTEXITCODE"
        }

        return @{ Success = $true; Output = $output }
    } catch {
        $errorType = if ($_.Exception.Message -match "not recognized|no se reconoce") { "Command not found" } else { "Execution error" }
        return @{ Success = $false; Error = "$errorType`: $($_.Exception.Message)" }
    }
}

function Process-AIResponse {
    param([string]$JsonResponse)

    try {
        $response = $JsonResponse | ConvertFrom-Json

        if ($response.explanation) {
            Write-ColorOutput "`n💡 Explanation:" $Colors.AI
            Write-ColorOutput $response.explanation "White"
        }

        if ($response.safety) {
            Write-ColorOutput "`n⚠️  Safety notes:" $Colors.Warning
            Write-ColorOutput $response.safety "Yellow"
        }

        if ($response.command -and $response.command.Trim()) {
            $result = Invoke-PowerShellCommand -Command $response.command

            if ($result.Success) {
                Write-ColorOutput "`n✓ Result:" $Colors.Success
                if ($result.Output.Trim()) {
                    Write-Host $result.Output
                    $outputForHistory = $result.Output
                } else {
                    Write-ColorOutput "(No output)" $Colors.Info
                    $outputForHistory = "<no output>"
                }

                # Store only the command output (not the full “Command: …” line)
                Add-ToHistory -Role "assistant" -Content $outputForHistory

                # Auto‑continue if AI indicates more steps needed
                if ($response.continue -eq $true) {
                    Write-ColorOutput "`n⏩ Continuing to next step..." $Colors.Warning
                    # Guardamos estado del workflow multi‑step
                    $state = @{
                        step                = "waiting-analysis"
                        originalUserMessage = ($script:ConversationHistory |
                                                Where-Object role -eq "user" |
                                                Select-Object -Last 1).content
                        commandOutput       = $outputForHistory
                    }
                    Add-ToHistory -Role "system" -Content ($state | ConvertTo-Json -Compress)

                    Start-Sleep -Milliseconds 500
                    return $true  # Signal to auto‑continue
                }
            } else {
                Write-ColorOutput "`n✗ Error:" $Colors.Error
                Write-ColorOutput $result.Error $Colors.Error
                Add-ToHistory -Role "assistant" -Content "Command: $($response.command)`nError: $($result.Error)"
            }
        } else {
            Add-ToHistory -Role "assistant" -Content $response.explanation
        }

        return $false  # No auto‑continue
    } catch {
        Write-ColorOutput "`nERROR parsing JSON: $($_.Exception.Message)" $Colors.Error
        Write-ColorOutput "Response: $JsonResponse" $Colors.Warning
        return $false
    }
}

# ============================
# MAIN
# ============================

function Start-IntelligentPowerShell {
    Show-Banner

    if (-not (Test-Configuration)) { return }

    $systemPrompt = @"
You are an expert PowerShell assistant. Target version: $script:PSVersion

CRITICAL DECISION LOGIC - Apply this pattern to EVERY user request:

STEP 1: Does answering this question require CURRENT/LIVE data from the system?
  YES → Execute appropriate PowerShell command to get that data
  NO → Answer directly from your knowledge

STEP 2: After getting data (if needed), analyze and explain in your own words

MULTI-STEP WORKFLOW (for requests that need system data):

First Response (getting data):
{
    "command": "[command to get data]",
    "explanation": "Getting [data type]... Next: I will analyze and explain [what user asked for]",
    "continue": true  // IMPORTANT: Set true to trigger automatic second step
}

Second Response (analyzing data):
{
    "command": "",
    "explanation": "[Detailed analysis of the data received, answering the original question]",
    "continue": false
}

CRITICAL: When you execute a command to gather data, ALWAYS:
1. Set "continue": true
2. In explanation, state what you'll do NEXT with the data
3. Remember the ORIGINAL user question for the next response

EXAMPLES of this pattern (apply same logic to ANY similar request):

User: "explain processes running in my session"
Response 1: { command: "Get-Process", explanation: "Getting process list... Next: I will explain what each process does", continue: true }
Response 2: { command: "", explanation: "Here's what each process does: chrome.exe is your web browser, powershell.exe is...", continue: false }

User: "explain files in current directory"
Response 1: { command: "Get-ChildItem", explanation: "Getting directory contents... Next: I will explain each file's purpose", continue: true }
Response 2: { command: "", explanation: "Based on the files found: script.ps1 is..., data.json contains...", continue: false }

User: "what services are critical"
Response 1: { command: "Get-Service", explanation: "Getting service list... Next: I will identify critical services", continue: true }
Response 2: { command: "", explanation: "Critical services include: wuauserv (Windows Update)...", continue: false }

Pattern for conceptual questions (no system data needed):
User: "how does Get-Process work"
Response: { command: "", explanation: "Get-Process retrieves information about...", continue: false }

Pattern for actions:
User: "create file test.txt"
Response: { command: "New-Item test.txt", explanation: "Creating file test.txt", continue: false }

KEY PRINCIPLES:
1. When gathering system data, ALWAYS set continue=true and state what you'll do next
2. In the continuation response, answer the ORIGINAL question using the data
3. Don't lose track of what the user asked for
4. Be PROACTIVE - if you need system data, GET IT first

WRONG approaches:
❌ Getting data but forgetting to analyze it
❌ Setting continue=false after data gathering command
❌ Not stating what you'll do next with the data

CORRECT approaches:
✅ Get data → continue=true → explain what you'll do next
✅ Receive data → continue=false → analyze and explain thoroughly
✅ Always remember original user question throughout multi-step flow

Respond ONLY in valid JSON:
{
    "command": "PowerShell command (empty if no system data needed)",
    "explanation": "what you're doing + what's next (if continue=true) OR final analysis (if continue=false)",
    "safety": "warnings if applicable (empty string if none)",
    "continue": true/false (true when you need to process data in next step)
}

Remember: continue=true means "I need another turn to finish answering this question"
"@

    Add-ToHistory -Role "system" -Content $systemPrompt
    Write-ColorOutput "System ready. Enter your query:`n" $Colors.Success

    while ($true) {
        Write-Host "You: " -NoNewline -ForegroundColor $Colors.Info
        $userInput = Read-Host

        if (-not $userInput.Trim()) { continue }

        switch -Regex ($userInput.ToLower().Trim()) {
            "^(exit|quit)$" { Write-ColorOutput "`nGoodbye! 👋" $Colors.Success; return }
            "^install$" { Install-Configuration; continue }
            "^history$" { Show-History; continue }
            "^debug$" {
                $script:DebugMode = -not $script:DebugMode
                Write-ColorOutput "`nDebug mode $(if($script:DebugMode){'enabled'}else{'disabled'})" $Colors.Warning
                continue
            }
        }

        Add-ToHistory -Role "user" -Content $userInput

        # Loop for multi-step operations
        $shouldContinue = $true
        while ($shouldContinue) {
            Write-ColorOutput "`n🤖 Processing..." $Colors.AI
            $aiResponse = Invoke-OpenAIChat

            if ($aiResponse) {
                $shouldContinue = Process-AIResponse -JsonResponse $aiResponse
            } else {
                Write-ColorOutput "`nCould not get AI response. Try again." $Colors.Error
                $script:ConversationHistory = $script:ConversationHistory[0..($script:ConversationHistory.Count - 2)]
                $shouldContinue = $false
            }
        }

        Write-Host ""
    }
}

Start-IntelligentPowerShell