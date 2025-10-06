# Chat OpenAI Streaming (Persistent Markdown)

**Chat OpenAI Streaming** is a simple, customizable chat interface for real-time conversation with any API compatible with the `/v1/chat/completions` endpoint (such as OpenAI or Azure OpenAI). The app supports live streaming responses and persistently saves chat history in your browser for a smooth and continuous experience. It's ideal for prompt testing or managing conversations with ease.

## Features

- **Live Streaming:** Receive assistant responses token-by-token with a live indicator for speed and token count.
- **Full Markdown Support:** Assistant replies are rendered with proper Markdown formatting, including tables, lists, headings, and code blocks.
- **Persistent Chat History:** Each conversation is saved locally (in your browser) and you can start new chats with separate histories.
- **Configuration Panel:** Set the API base URL, API key, model, and system prompt from within the interface.
- **Model and System Prompt Selection:** Easily adjust which model you use and craft the AI’s behavior with a customizable system prompt.
- **Responsive, Clean UI:** User-friendly desktop and mobile experience powered by Bootstrap 5.

## Usage

1. **Clone or download this repository.**
2. **Open the `index.html` file in your browser.**
3. Open the configuration panel (`⚙️`) and fill in the following:
    - `Base URL` (for example, `https://api.openai.com/v1`)
    - `API Key`
    - `Model` (e.g., `gpt-3.5-turbo`)
    - Optional: `System prompt` (example: "You are a helpful and precise assistant.")
4. Start chatting!  
   The history of each conversation is preserved, even after reloading the page.
5. Use the **“New Chat”** button to start a fresh conversation (this creates a new chat history).

## Requirements

- A modern browser supporting JavaScript ES6 and [Fetch Streams](https://developer.mozilla.org/en-US/docs/Web/API/Streams_API).
- A valid API key from OpenAI, Azure OpenAI, or any service compatible with the `/chat/completions` endpoint.

## Security Notes

- **Your API key is only stored in your browser,** never sent anywhere except to the endpoint you configure.
- The project is fully client-side (HTML, JS, and CSS)—no backend server involved.

## Self-Improving Project

> **Fun fact:**  
> Much of the code and interface for this chat app was developed and refined using the app itself! The project served as its own coding assistant, iteratively reviewing and improving its own code and features through conversations within the very same environment you see here.

