# Intelligent PowerShell - OpenAI Chat Client
# Conversational system that converts natural language into PowerShell commands

#Requires -Version 5.1

# ============================
# INITIAL CONFIGURATION
# ============================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Continue"

# Configuration variables
$script:DebugMode = $false
$script:MaxHistoryItems = 20
$script:MaxOutputLength = 2000
$script:ConversationHistory = @()

# Colors for output
$Colors = @{
    Info = "Cyan"
    Success = "Green"
    Error = "Red"
    Warning = "Yellow"
    Command = "Magenta"
    AI = "Blue"
}

# ============================
# UTILITY FUNCTIONS
# ============================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Show-Banner {
    Clear-Host
    Write-ColorOutput "`n╔════════════════════════════════════════════════════════════╗" $Colors.Info
    Write-ColorOutput "║      Intelligent PowerShell - AI Assistant v1.0            ║" $Colors.Info
    Write-ColorOutput "╚════════════════════════════════════════════════════════════╝`n" $Colors.Info
    Write-ColorOutput "Special commands:" $Colors.Warning
    Write-ColorOutput "  • history - Show conversation history" $Colors.Info
    Write-ColorOutput "  • debug - Toggle debug mode" $Colors.Info
    Write-ColorOutput "  • exit/quit - End session`n" $Colors.Info
}

function Test-Configuration {
    Write-ColorOutput "Verifying configuration..." $Colors.Info

    # Verify API Key
    $apiKey = $env:OPENAI_API_KEY
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-ColorOutput "ERROR: OPENAI_API_KEY environment variable not found." $Colors.Error
        Write-ColorOutput "Please configure your OpenAI API key:" $Colors.Warning
        Write-ColorOutput '  $env:OPENAI_API_KEY = "your-api-key-here"' $Colors.Info
        return $false
    }

    # Custom endpoint (optional for Azure OpenAI)
    $script:ApiEndpoint = $env:OPENAI_API_ENDPOINT
    if ([string]::IsNullOrWhiteSpace($script:ApiEndpoint)) {
        $script:ApiEndpoint = "https://api.openai.com/v1/chat/completions"
    }

    # Model
    $script:Model = $env:OPENAI_MODEL
    if ([string]::IsNullOrWhiteSpace($script:Model)) {
        $script:Model = "gpt-4"
    }

    Write-ColorOutput "✓ API Key configured" $Colors.Success
    Write-ColorOutput "✓ Endpoint: $script:ApiEndpoint" $Colors.Success
    Write-ColorOutput "✓ Model: $script:Model`n" $Colors.Success

    return $true
}

function Add-ToHistory {
    param(
        [string]$Role,
        [string]$Content
    )

    # Truncate very long content
    if ($Content.Length -gt $script:MaxOutputLength) {
        $Content = $Content.Substring(0, $script:MaxOutputLength) + "`n... [Output truncated - Total: $($Content.Length) characters]"
    }

    $script:ConversationHistory += @{
        role = $Role
        content = $Content
    }

    # Keep only the last N messages (excluding system)
    $userAssistantMessages = $script:ConversationHistory | Where-Object { $_.role -ne "system" }
    if ($userAssistantMessages.Count -gt ($script:MaxHistoryItems * 2)) {
        $systemMessage = $script:ConversationHistory | Where-Object { $_.role -eq "system" }
        $recentMessages = $userAssistantMessages | Select-Object -Last ($script:MaxHistoryItems * 2)
        $script:ConversationHistory = @($systemMessage) + $recentMessages
    }
}

function Show-History {
    Write-ColorOutput "`n═══ CONVERSATION HISTORY ═══" $Colors.Info

    $historyItems = $script:ConversationHistory | Where-Object { $_.role -ne "system" }

    if ($historyItems.Count -eq 0) {
        Write-ColorOutput "  (History empty)" $Colors.Warning
        return
    }

    for ($i = 0; $i -lt $historyItems.Count; $i++) {
        $item = $historyItems[$i]
        $label = if ($item.role -eq "user") { "User" } else { "Assistant" }
        $color = if ($item.role -eq "user") { $Colors.Info } else { $Colors.AI }

        Write-ColorOutput "`n[$label #$($i + 1)]" $color
        Write-ColorOutput $item.content "White"
    }

    Write-ColorOutput "`n═══════════════════════════════`n" $Colors.Info
}

function Invoke-OpenAIChat {
    param()

    try {
        $apiKey = $env:OPENAI_API_KEY

        # Build message array cleanly
        $conversationContext = @()
        foreach ($msg in $script:ConversationHistory) {
            $conversationContext += @{
                role = $msg.role
                content = $msg.content
            }
        }

        # Build the payload
        $chatPayload = @{
            model = $script:Model
            messages = $conversationContext
            max_tokens = 1500
            temperature = 0.7
            response_format = @{ type = "json_object" }
        } | ConvertTo-Json -Depth 6

        $requestBody = $chatPayload

        # Debug mode
        if ($script:DebugMode) {
            Write-ColorOutput "`n═══ DEBUG: REQUEST ═══" $Colors.Warning
            Write-ColorOutput "URL: $script:ApiEndpoint" $Colors.Info
            Write-ColorOutput "Headers: Authorization: Bearer ****..." $Colors.Info
            Write-ColorOutput "Payload:`n$requestBody`n" $Colors.Info
            Write-ColorOutput "═══════════════════════`n" $Colors.Warning
        }

        # Make the request with explicit UTF-8 encoding
        $headers = @{
            "Authorization" = "Bearer $apiKey"
            "Content-Type" = "application/json; charset=utf-8"
        }

        # Convert body to UTF-8 bytes explicitly
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($requestBody)

        $response = Invoke-RestMethod -Uri $script:ApiEndpoint -Method Post -Headers $headers -Body $bodyBytes -ContentType "application/json; charset=utf-8" -ErrorAction Stop

        # Extract response content
        $content = $response.choices[0].message.content

        if ($script:DebugMode) {
            Write-ColorOutput "═══ DEBUG: RESPONSE ═══" $Colors.Warning
            Write-ColorOutput $content $Colors.Info
            Write-ColorOutput "═══════════════════════`n" $Colors.Warning
        }

        return $content

    } catch {
        Write-ColorOutput "`nERROR communicating with OpenAI API:" $Colors.Error
        Write-ColorOutput $_.Exception.Message $Colors.Error

        if ($_.ErrorDetails) {
            Write-ColorOutput "Details: $($_.ErrorDetails.Message)" $Colors.Error
        }

        return $null
    }
}

function Invoke-PowerShellCommand {
    param(
        [string]$Command
    )

    try {
        Write-ColorOutput "`n► Executing command:" $Colors.Command
        Write-ColorOutput "  $Command`n" $Colors.Command

        # Execute command and capture output and errors
        $output = Invoke-Expression $Command 2>&1 | Out-String

        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Command finished with exit code: $LASTEXITCODE"
        }

        return @{
            Success = $true
            Output = $output
        }

    } catch {
        $errorMessage = $_.Exception.Message

        # Distinguish error types
        if ($errorMessage -like "*not recognized*" -or $errorMessage -like "*no se reconoce*") {
            $errorType = "Command not found"
        } else {
            $errorType = "Execution error"
        }

        return @{
            Success = $false
            Error = "$errorType`: $errorMessage"
        }
    }
}

function Process-AIResponse {
    param(
        [string]$JsonResponse
    )

    try {
        $response = $JsonResponse | ConvertFrom-Json

        # Show explanation
        if ($response.explanation) {
            Write-ColorOutput "`n💡 Explanation:" $Colors.AI
            # Force correct UTF-8 encoding
            $text = $response.explanation
            $bytes = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetBytes($text)
            $decoded = [System.Text.Encoding]::UTF8.GetString($bytes)
            Write-ColorOutput $decoded "White"
        }

        # Show safety notes
        if ($response.safety) {
            Write-ColorOutput "`n⚠️  Safety notes:" $Colors.Warning
            # Force correct UTF-8 encoding
            $text = $response.safety
            $bytes = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetBytes($text)
            $decoded = [System.Text.Encoding]::UTF8.GetString($bytes)
            Write-ColorOutput $decoded "Yellow"
        }

        # Execute command if it exists
        if ($response.command -and -not [string]::IsNullOrWhiteSpace($response.command)) {
            $result = Invoke-PowerShellCommand -Command $response.command

            if ($result.Success) {
                Write-ColorOutput "`n✓ Result:" $Colors.Success
                if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
                    Write-Host $result.Output
                } else {
                    Write-ColorOutput "(Command executed with no output)" $Colors.Info
                }

                # Add to history
                Add-ToHistory -Role "assistant" -Content "Command executed: $($response.command)`nResult: $($result.Output)"

            } else {
                Write-ColorOutput "`n✗ Error:" $Colors.Error
                Write-ColorOutput $result.Error $Colors.Error

                # Add error to history
                Add-ToHistory -Role "assistant" -Content "Command attempted: $($response.command)`nError: $($result.Error)"
            }
        } else {
            # Response without command
            Add-ToHistory -Role "assistant" -Content $response.explanation
        }

    } catch {
        Write-ColorOutput "`nERROR parsing JSON response:" $Colors.Error
        Write-ColorOutput $_.Exception.Message $Colors.Error
        Write-ColorOutput "Response received: $JsonResponse" $Colors.Warning
    }
}

# ============================
# MAIN FUNCTION
# ============================

function Start-IntelligentPowerShell {
    Show-Banner

    # Verify configuration
    if (-not (Test-Configuration)) {
        return
    }

    # Initialize with system prompt
    $systemPrompt = @"
You are an expert PowerShell assistant. Your job is to help users perform tasks using PowerShell commands.

IMPORTANT: You must ALWAYS respond in valid JSON format with the following structure:
{
    "command": "PowerShell command to execute (string, can be empty if no command)",
    "explanation": "natural language explanation of what you're doing or information requested (string)",
    "safety": "safety notes or warnings if applicable (string, can be empty)"
}

Rules:
- If the user asks for information, provide the explanation and appropriate command
- If the user asks to execute something, provide the correct command
- If something is dangerous or destructive, indicate it in the "safety" field
- If you only need to respond without executing a command, leave "command" empty
- Be concise but clear in your explanations
- NEVER include text outside the JSON format
"@

    Add-ToHistory -Role "system" -Content $systemPrompt

    Write-ColorOutput "System ready. Write your query or command in natural language:`n" $Colors.Success

    # Main conversation loop
    while ($true) {
        Write-Host "You: " -NoNewline -ForegroundColor $Colors.Info
        $userInput = Read-Host

        if ([string]::IsNullOrWhiteSpace($userInput)) {
            continue
        }

        # Special commands
        switch -Regex ($userInput.ToLower().Trim()) {
            "^(exit|quit)$" {
                Write-ColorOutput "`nGoodbye! 👋" $Colors.Success
                return
            }
            "^history$" {
                Show-History
                continue
            }
            "^debug$" {
                $script:DebugMode = -not $script:DebugMode
                $status = if ($script:DebugMode) { "enabled" } else { "disabled" }
                Write-ColorOutput "`nDebug mode $status" $Colors.Warning
                continue
            }
        }

        # Add user message to history
        Add-ToHistory -Role "user" -Content $userInput

        # Get AI response
        Write-ColorOutput "`n🤖 Processing..." $Colors.AI
        $aiResponse = Invoke-OpenAIChat

        if ($aiResponse) {
            Process-AIResponse -JsonResponse $aiResponse
        } else {
            Write-ColorOutput "`nCould not get response from AI. Try again." $Colors.Error
            # Remove last user message from history
            $script:ConversationHistory = $script:ConversationHistory[0..($script:ConversationHistory.Count - 2)]
        }

        Write-Host ""
    }
}

# ============================
# ENTRY POINT
# ============================

Start-IntelligentPowerShell