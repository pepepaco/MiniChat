# MiniChat AI Coding Agent Instructions

## Architecture Overview

MiniChat consists of three independent implementations of an OpenAI-compatible chat interface:

1. **index.html** - Client-side only implementation with zero backend (pure HTML/JS in browser)
2. **app.js** - Server-side Node.js implementation with zero JavaScript in browser (server-rendered HTML)
3. **mini-ps.ps1** - AI-powered PowerShell script that converts natural language to PowerShell commands

## Key Patterns & Conventions

### VIEWSTATE Pattern (app.js)
- State is serialized, encrypted, and passed between requests as `__VIEWSTATE` hidden field
- Encryption uses AES-256-CBC with a hardcoded password (for demo purposes)
- All conversation history, configuration, and UI state are preserved in encrypted form
- Never store sensitive data in VIEWSTATE without encryption

### Server-Side Rendering (app.js)
- Full HTML pages are rendered on each request
- No client-side JavaScript required for core functionality
- Form submissions drive all interactions
- Bootstrap CDN is used for styling

### Client-Side Streaming (index.html)
- Real-time streaming of AI responses using fetch API
- Markdown rendering with Marked.js library
- LocalStorage for conversation persistence
- Image upload support with preview functionality

### PowerShell AI Integration (mini-ps.ps1)
- Natural language queries converted to PowerShell commands via AI
- JSON responses with structured format: `{command, explanation, safety}`
- Two-phase execution: command generation → execution → AI analysis of output
- Colored console output with semantic meaning (cyan=user, green=success, red=error)

## Critical Workflows

### Building & Running
```bash
# For Node.js server
npm install
npm start
# Visit http://localhost:3000

# For client-side HTML
# Simply open index.html in browser
```

### Configuration Storage
- **app.js**: Encrypted cookies (`chat_config_v1`) and encrypted VIEWSTATE
- **index.html**: LocalStorage with keys prefixed by `chatConfig-` and `chatHistory-`
- **mini-ps.ps1**: Environment variables (`OPENAI_API_KEY`, `OPENAI_API_ENDPOINT`, `OPENAI_MODEL`)

### Security Considerations
- API keys are handled client-side in index.html (for demonstration)
- Server-side API calls in app.js prevent key exposure to browser
- VIEWSTATE encryption provides tamper resistance but not confidentiality
- Input validation occurs at the API boundary

## Component Interactions

### Message Flow
1. User input → Form submission (app.js) OR fetch request (index.html)
2. Request processed → API call to OpenAI-compatible endpoint
3. Response received → HTML rendering (app.js) OR streaming DOM updates (index.html)
4. State updated → VIEWSTATE (app.js) OR LocalStorage (index.html)

### Feature Parity
All implementations support:
- Configurable API endpoint, key, model, and system prompt
- Conversation history
- Multiple simultaneous chats
- Dynamic title generation
- Export/download functionality

## Common Modification Points

### Adding New Features
- **app.js**: Modify `renderPage()` for UI changes, add new action handlers in POST route
- **index.html**: Update JavaScript event handlers and DOM manipulation functions
- **mini-ps.ps1**: Add new special commands in the switch statement in `Start-IntelligentPowerShell`

### API Integration Changes
- **app.js**: Update `callOpenAI()` and `getAuthHeaders()` functions
- **index.html**: Modify `streamOpenAI()` function
- **mini-ps.ps1**: Update `Invoke-OpenAIChat()` function

### Styling
- **app.js**: CSS is embedded in the `CSS` constant
- **index.html**: CSS is in the `<style>` tag in the head
- Both use Bootstrap for layout components