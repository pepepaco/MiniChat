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
    Write-ColorOutput "║      Intelligent PowerShell - AI Assistant v2.0            ║" $Colors.Info
    Write-ColorOutput "╚════════════════════════════════════════════════════════════╝`n" $Colors.Info
    Write-ColorOutput "Special commands: install | history | debug | clear | exit/quit`n" $Colors.Warning
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

        if ($env:OPENAI_API_KEY) {
            [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $env:OPENAI_API_KEY, "User")
            Write-ColorOutput "✓ OPENAI_API_KEY saved" $Colors.Success
        }

        [Environment]::SetEnvironmentVariable("OPENAI_API_ENDPOINT", $script:ApiEndpoint, "User")
        [Environment]::SetEnvironmentVariable("OPENAI_MODEL", $script:Model, "User")
        Write-ColorOutput "✓ OPENAI_API_ENDPOINT and OPENAI_MODEL saved" $Colors.Success

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
            temperature      = 1
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

        return @{ Success = $true; Output = $output.Trim() }
    } catch {
        $errorType = if ($_.Exception.Message -match "not recognized|no se reconoce") {
            "Command not found"
        } else {
            "Execution error"
        }
        return @{ Success = $false; Error = "$errorType`: $($_.Exception.Message)" }
    }
}

function Process-UserQuery {
    param([string]$UserInput)

    Write-ColorOutput "`n🤖 Analyzing request..." $Colors.AI

    # Paso 1: IA decide qué comando ejecutar
    $aiResponse = Invoke-OpenAIChat

    if (-not $aiResponse) {
        Write-ColorOutput "Could not get AI response. Try again." $Colors.Error
        return
    }

    try {
        $response = $aiResponse | ConvertFrom-Json

        # Mostrar lo que la IA planea hacer
        if ($response.explanation) {
            Write-ColorOutput "`n💡 Plan:" $Colors.AI
            Write-ColorOutput $response.explanation "White"
        }

        if ($response.safety) {
            Write-ColorOutput "`n⚠️  Safety:" $Colors.Warning
            Write-ColorOutput $response.safety "Yellow"
        }

        # Paso 2: Ejecutar el comando si existe
        if ($response.command -and $response.command.Trim()) {
            $command = $response.command.Trim()
            $result = Invoke-PowerShellCommand -Command $command

            # Paso 3: Preparar el resultado para que la IA lo analice
            if ($result.Success) {
                $outputText = if ($result.Output) {
                    Write-ColorOutput "`n✓ Output:" $Colors.Success
                    Write-Host $result.Output
                    $result.Output
                } else {
                    Write-ColorOutput "`n✓ Command executed successfully (no output)" $Colors.Success
                    "<No output>"
                }

                # Agregar resultado al historial
                Add-ToHistory -Role "assistant" -Content @"
[EXECUTED] $command

[OUTPUT]
$outputText
"@

                # Paso 4: IA analiza el resultado
                Write-ColorOutput "`n🤖 Analyzing result..." $Colors.AI
                $analysisResponse = Invoke-OpenAIChat

                if ($analysisResponse) {
                    $analysis = $analysisResponse | ConvertFrom-Json

                    if ($analysis.explanation) {
                        Write-ColorOutput "`n📊 Analysis:" $Colors.AI
                        Write-ColorOutput $analysis.explanation "White"
                    }

                    Add-ToHistory -Role "assistant" -Content $analysis.explanation
                }

            } else {
                # Error en la ejecución
                Write-ColorOutput "`n✗ Error:" $Colors.Error
                Write-ColorOutput $result.Error $Colors.Error

                Add-ToHistory -Role "assistant" -Content @"
[ERROR] $command
$($result.Error)
"@
            }

        } else {
            # No hay comando, solo respuesta directa
            if ($response.explanation) {
                Add-ToHistory -Role "assistant" -Content $response.explanation
            }
        }

    } catch {
        Write-ColorOutput "`nERROR parsing response: $($_.Exception.Message)" $Colors.Error
        if ($script:DebugMode) {
            Write-ColorOutput "Raw response: $aiResponse" $Colors.Warning
        }
    }
}

# ============================
# MAIN
# ============================

function Start-IntelligentPowerShell {
    Show-Banner

    if (-not (Test-Configuration)) { return }

    $systemPrompt = @"
You are a PowerShell assistant. Your job is simple:

1. User asks a question
2. You generate ONE PowerShell command to answer it
3. System executes the command and shows you the output
4. You explain what the output means

RESPONSE FORMAT (always JSON):

When generating a command:
{
  "command": "the PowerShell command to run",
  "explanation": "what you're about to do",
  "safety": "any warnings if needed"
}

When analyzing output (you'll receive output from previous command):
{
  "command": "",
  "explanation": "your analysis of the output"
}

RULES:
- Generate ONE command per user request
- After seeing output, explain it clearly
- If file doesn't exist or command fails, explain that
- Use proper PowerShell syntax
- Never apologize excessively, just be helpful

EXAMPLES:

User: "show me txt files"
You: {"command": "Get-ChildItem *.txt", "explanation": "Listing all .txt files"}
[System shows output]
You: {"command": "", "explanation": "Found 3 files: a.txt (5KB), b.txt (2KB), c.txt (empty)"}

User: "what's in config.json"
You: {"command": "Get-Content config.json", "explanation": "Reading config.json"}
[System shows output or error]
You: {"command": "", "explanation": "The file contains API settings..."}
"@

    Add-ToHistory -Role "system" -Content $systemPrompt
    Write-ColorOutput "System ready. Enter your query:`n" $Colors.Success

    while ($true) {
        Write-Host "You: " -NoNewline -ForegroundColor $Colors.Info
        $userInput = Read-Host

        if (-not $userInput.Trim()) { continue }

        switch -Regex ($userInput.ToLower().Trim()) {
            "^(exit|quit)$" {
                Write-ColorOutput "`nGoodbye! 👋`n" $Colors.Success
                return
            }
            "^install$" {
                Install-Configuration
                continue
            }
            "^history$" {
                Show-History
                continue
            }
            "^clear$" {
                $script:ConversationHistory = $script:ConversationHistory | Where-Object { $_.role -eq "system" }
                Write-ColorOutput "`n✓ History cleared`n" $Colors.Success
                continue
            }
            "^debug$" {
                $script:DebugMode = -not $script:DebugMode
                Write-ColorOutput "`nDebug mode $(if($script:DebugMode){'enabled'}else{'disabled'})`n" $Colors.Warning
                continue
            }
        }

        Add-ToHistory -Role "user" -Content $userInput
        Process-UserQuery -UserInput $userInput
        Write-Host ""
    }
}

Start-IntelligentPowerShell