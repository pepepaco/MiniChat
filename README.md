# MiniChat - Dual Implementation (Zero Backend & Zero JavaScript)

**MiniChat** provides two implementations for chatting with OpenAI-compatible APIs:

1. **index.html** - A client-side only solution with **zero backend** (pure HTML/JS in browser)
2. **app.js** - A server-side solution with **zero JavaScript** in browser (pure server-rendered HTML)
3. **PowerShell Scripts** - PowerShell script that converts natural language instructions to PowerShell commands

Both are proof-of-concept implementations designed for testing and experimentation.

[![Deploy to Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/pepepaco/MiniChat)

## Implementation 1: index.html (Zero Backend)

**index.html** is a client-side only implementation that runs entirely in the browser with no backend required.

**Try it live:**
[https://pepepaco.github.io/MiniChat/](https://pepepaco.github.io/MiniChat/)

**Usage:**

1. **Open the `index.html` file directly in your browser.**
2. Open the configuration panel and fill in the following:
   - `Base URL` (for example, `https://api.openai.com/v1`)
   - `API Key`
   - `Model` (e.g., `gpt-3.5-turbo`)
   - Optional: `System prompt` (example: "You are a helpful and precise assistant.")
3. Start chatting!
4. Use the **"New Chat"** button to start a fresh conversation.

**Requirements:**

- A modern browser supporting JavaScript ES6 and [Fetch Streams](https://developer.mozilla.org/en-US/docs/Web/API/Streams_API).
- A valid API key from OpenAI, Azure OpenAI, or any service compatible with the `/chat/completions` endpoint.

**Security Notes:**

- **Your API key is only stored in your browser**, never sent anywhere except to the endpoint you configure.
- The project is fully client-side (HTML, JS, and CSS)—no backend server involved.

## Implementation 2: app.js (Zero JavaScript)

**app.js** is a server-side Node.js implementation where all processing happens on the server and the browser receives pure HTML with no JavaScript required for core functionality.

**Usage:**

1. **Install dependencies:** `npm install`
2. **Start the server:** `node app.js`
3. **Open your browser to:** `http://localhost:3000`
4. Configure your API settings in the configuration panel
5. Start chatting!

**Requirements:**

- Node.js installed
- Valid API key for OpenAI or compatible service

**Features:**

- Server-side state management using encrypted VIEWSTATE
- All API calls handled server-side
- New chat functionality opens in separate browser windows while preserving configuration
- Zero JavaScript required in browser for core functionality

## Security Notes for app.js

- No persistent storage is used - all state is maintained in encrypted VIEWSTATE
- The encrypted VIEWSTATE travels with each request/response cycle
- No session management is required

## Dependencies

For app.js:

- express: Web framework
- marked: Markdown processing
- node-fetch: HTTP client for API calls

## Implementation 3: PowerShell Scripts (AI-Powered Command Execution)

**MiniChat** now includes an updated PowerShell script that converts natural language instructions to PowerShell commands:

1. **mini-ps.ps1** - An enhanced PowerShell script that converts natural language instructions to PowerShell commands with an interactive chat interface

**Usage (mini-ps.ps1):**

1. **Set environment variables:**
   - `OPENAI_API_KEY` (Required: your API key)
   - `OPENAI_API_ENDPOINT` (Optional: API endpoint, defaults to `https://api.openai.com/v1/chat/completions`)
   - `OPENAI_MODEL` (Optional: model to use, defaults to `gpt-4`)
2. **Run the script:** `.\\mini-ps.ps1`
3. **Type your instructions in natural language**
4. **Review the explanation and safety notes provided by the AI**
5. **The AI will execute appropriate PowerShell commands automatically if needed**

**Special Commands:**

- `history` - Shows the conversation history
- `debug` - Toggles debug mode to see API requests/responses
- `exit` or `quit` - Ends the session

**Features:**

- Interactive chat interface with colored output
- Automatic PowerShell command execution based on AI interpretation
- Safety warnings for potentially dangerous operations
- Conversation history management with automatic truncation
- Support for both Spanish and English interfaces

**Requirements:**

- PowerShell 5.1+ (Windows) or PowerShell 7+
- Valid API key from OpenAI, Azure OpenAI, or any service compatible with the Chat Completions API

## Self-Improving Project

> **Fun fact:**
> Much of the code and interface for this chat app was developed and refined using the app itself! The project served as its own coding assistant, iteratively reviewing and improving its own code and features through conversations within the very same environment you see here.
