const express = require('express');
const marked = require('marked');
const crypto = require('crypto');
const app = express();

app.use(express.urlencoded({ extended: true, limit: '5mb' }));

const DEFAULT_CONFIG = {
	urlBase: 'https://api.openai.com/v1',
	apiKey: '',
	model: 'gpt-4.1',
	systemPrompt: 'helpful human assistant',
};

const CSS = `
html,body{height:100%;width:100vw;margin:0;padding:0;}
body{background:#f8f9fa;min-height:100vh;width:100vw;}
.chat-window{width:100vw;height:100vh;display:flex;flex-direction:column;background:#fff;}
.chat-messages{flex:1;overflow-y:auto;padding:16px;border-bottom:1px solid #eee;background:#fff;}
.message.user{text-align:right;}
.message.openai{text-align:left;}
.message span{display:inline-block;padding:8px 12px;border-radius:16px;margin:6px 0;max-width:80%;word-break:break-word;}
.message.user span{background:#0d6efd;color:#fff;}
.message.openai span{background:#e9ecef;color:#333;}
.settings-panel{border-bottom:1px solid #eee;padding:16px;background:#f7f7f7;}
.new-chat-btn{margin-right:10px;background:#198754;color:#fff;border:none;padding:5px 16px;border-radius:20px;font-size:1em;cursor:pointer;}
.new-chat-btn:hover{background:#157347;}
.chat-id-tag{font-size:.75em;color:#888;font-family:monospace;background:#eee;padding:1px 7px;border-radius:12px;margin-left:8px;}
.speed-indicator{font-size: .85em; color: #888; padding-left: 1em;}
@media(max-width:600px){
  .chat-window{width:100vw;height:100vh;border-radius:0;margin:0;}
  .chat-messages{padding:8px;}
  .settings-panel,.p-3{padding:8px !important;}
  .message span{max-width:100%;font-size:1em;}
}
code,pre{font-family:'Fira Mono','Consolas',monospace;background:#f1f3f5;border-radius:4px;padding:2px 6px;}
.btn {
  transition: background-color 0.2s, transform 0.1s;
}
.btn:active {
  background-color: #0d6efd;
  color: #fff;
  transform: scale(0.96);
  box-shadow: 0 2px 8px rgba(0,0,0,0.2);
}
`;

const ALGORITHM = 'aes-256-cbc';
const ENCRYPTION_KEY = crypto.scryptSync(
	'your-secret-password-that-is-long-enough',
	'salt-for-the-key',
	32,
);
const IV_LENGTH = 16;

function encrypt(text) {
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
    let encrypted = cipher.update(text);
    encrypted = Buffer.concat([encrypted, cipher.final()]);
    return iv.toString('hex') + ':' + encrypted.toString('hex');
}

function decrypt(text) {
    try {
        const textParts = text.split(':');
        const iv = Buffer.from(textParts.shift(), 'hex');
        const encryptedText = Buffer.from(textParts.join(':'), 'hex');
        const decipher = crypto.createDecipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
        let decrypted = decipher.update(encryptedText);
        decrypted = Buffer.concat([decrypted, decipher.final()]);
        return decrypted.toString();
    } catch (error) {
        return null;
    }
}

function getState(req) {
    let state = {};
    const viewstate = (req.body && req.body.__VIEWSTATE) || (req.query && req.query.__VIEWSTATE);

    if (viewstate) {
        const decrypted = decrypt(viewstate);
        if (decrypted) {
            try {
                state = JSON.parse(decrypted);
            } catch (e) {}
        }
    }
    
    if (!state.config) state.config = { ...DEFAULT_CONFIG };
    if (!state.messages) state.messages = [];
	if (!state.chatId) state.chatId = Date.now().toString(36);
    if (!state.title) state.title = 'New Chat';

    return state;
}

function renderPage(state) {
	const { config, messages, chatId } = state;
	const encryptedState = encrypt(JSON.stringify(state));
	const showConfig = state.showConfig;
	const lastUserMsgIndex = messages.map(m => m.role).lastIndexOf('user');

	let speedIndicatorHtml = '';
	if (state.speedInfo) {
		speedIndicatorHtml = `<br><small class="speed-indicator">${state.speedInfo}</small>`;
		state.speedInfo = null;
	}

	return `
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<base href="http://localhost:3000/">
<title>${state.title} - OpenAI Chat</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
<style>${CSS}</style>
</head>
<body>
<form action="/" method="post">
<input type="hidden" name="__VIEWSTATE" value="${encryptedState}" />
<button type="submit" name="action" value="sendMessage" style="display: none;" aria-hidden="true"></button>
<div class="chat-window">
  <header class="p-3 border-bottom d-flex align-items-center justify-content-between">
    <span class="fw-bold">
      ${state.title} <small class="text-secondary">VIEWSTATE (Encrypted)</small>
      <span class="chat-id-tag" title="Conversation ID">${chatId}</span>
    </span>
    <div class="d-flex align-items-center gap-2">
      <button class="btn btn-secondary btn-sm" type="submit" name="action" value="downloadChat" title="Save Chat">Save</button>
      <button class="btn btn-info btn-sm" type="submit" name="action" value="refreshTitle" title="Generate Title">Refresh Title</button>
      <button class="settings-toggle btn btn-link p-0" type="submit" name="action" value="toggleConfig" style="font-size:1.35em;line-height:1;vertical-align:middle;color:#0d6efd" title="Configuración">&#9881;</button>
      <button class="new-chat-btn" type="submit" name="action" value="newChat" formaction="/newchat" formtarget="_blank" title="New Chat">New chat</button>
    </div>
  </header>

  ${
		showConfig
			? `
    <section class="settings-panel mt-2 mb-3">
      <div class="mb-2">
          <label class="form-label">Base URL (up to /v1)</label>
          <input type="text" class="form-control" name="urlBase" value="${
						config.urlBase
					}" />
        </div>
        <div class="mb-2">
          <label class="form-label">API Key</label>
          <input type="text" class="form-control" name="apiKey" value="${
						config.apiKey
					}" />
        </div>
        <div class="mb-2">
          <label class="form-label">Model</label>
          <input type="text" class="form-control" name="model" value="${
						config.model
					}" />
        </div>
        <div class="mb-2">
          <label class="form-label">System prompt</label>
          <textarea class="form-control" name="systemPrompt" rows="2">${
						config.systemPrompt || ''
					}</textarea>
          <small class="text-secondary">Controls AI behavior.</small>
        </div>
        <button type="submit" class="btn btn-primary btn-sm w-100" name="action" value="saveSettings">Guardar configuración</button>
    </section>
  `
			: ''
	}

    <main class="chat-messages" id="chatMessages">
      ${messages
				.map((msg, i) => {
					if (msg.role === 'user') {
						const idAttr = i === lastUserMsgIndex ? ' id="last-user-msg"' : '';
						return `<div class="message user"${idAttr}><span>${msg.content}</span></div>`;
					} else {
						return `<div class="message openai"><span>${marked.parse(
							msg.content,
						)}${
							i === messages.length - 1 ? speedIndicatorHtml : ''
						}</span></div>`;
					}
				})
				.join('\n')}
      <div class="d-flex p-3 gap-2">
        <input type="text" class="form-control flex-grow-1" name="userInput" placeholder="Type your message..." autofocus autocomplete="off"/>
        <button class="btn btn-primary flex-shrink-0" type="submit" name="action" value="sendMessage">Send</button>
      </div>
    </main>
</div>
</form>
</body>
</html>`;
}

app.get('/', (req, res) => {
	const state = getState(req);
	res.send(renderPage(state));
});

app.post('/', async (req, res) => {
	const state = getState(req);
	const { userInput, action, urlBase, apiKey, model, systemPrompt } = req.body;

	switch (action) {
		case 'sendMessage':
			if (userInput) {
				state.messages.push({ role: 'user', content: userInput });

				let convSend = [...state.messages];
				if (
					state.config.systemPrompt &&
					!(convSend.length && convSend[0].role === 'system')
				) {
					convSend = [
						{ role: 'system', content: state.config.systemPrompt },
						...convSend,
					];
				}

				try {
					const fetch =
						global.fetch ||
						((...args) =>
							import('node-fetch').then(({ default: fetch }) =>
								fetch(...args),
							));
					const response = await fetch(
						`${state.config.urlBase}/chat/completions`,
						{
							method: 'POST',
							headers: {
								Authorization: state.config.urlBase.includes('openai.azure.com')
									? state.config.apiKey
									: `Bearer ${state.config.apiKey}`,
								...(state.config.urlBase.includes('openai.azure.com')
									? { 'api-key': state.config.apiKey }
									: {}),
								'Content-Type': 'application/json',
							},
							body: JSON.stringify({
								model: state.config.model,
								messages: convSend,
								stream: false,
							}),
						},
					);

					if (!response.ok) {
						const textErr = await response.text();
						state.messages.push({
							role: 'assistant',
							content: `Error de API (${response.status}): ${textErr}`,
						});
					} else {
						const data = await response.json();
						const reply = data.choices?.[0]?.message?.content ?? 'No response';
						state.messages.push({ role: 'assistant', content: reply });
						const tokens = reply.length;
						state.speedInfo = `Done. Tokens: ${tokens}`;
					}
				} catch (err) {
					state.messages.push({
						role: 'assistant',
						content: 'Error de conexión o API: ' + err.message,
					});
				}
			}
			break;
		case 'toggleConfig':
			state.showConfig = !state.showConfig;
			break;
		case 'saveSettings':
			state.config.urlBase = urlBase || state.config.urlBase;
			state.config.apiKey = apiKey || state.config.apiKey;
			state.config.model = model || state.config.model;
			state.config.systemPrompt = systemPrompt || state.config.systemPrompt;
			state.showConfig = false;
			break;

		case 'downloadChat':
			const htmlContent = renderPage(state);
			res.setHeader(
				'Content-Disposition',
				`attachment; filename="${state.title
					.replace(/[^a-z0-9]/gi, '_')
					.toLowerCase()}.html"`,
			);
			res.setHeader('Content-Type', 'text/html');
			return res.send(htmlContent);
		case 'refreshTitle':
			if (state.messages.length > 0) {
				try {
					const fetch =
						global.fetch ||
						((...args) =>
							import('node-fetch').then(({ default: fetch }) =>
								fetch(...args),
							));
					const response = await fetch(
						`${state.config.urlBase}/chat/completions`,
						{
							method: 'POST',
							headers: {
								Authorization: state.config.urlBase.includes('openai.azure.com')
									? state.config.apiKey
									: `Bearer ${state.config.apiKey}`,
								...(state.config.urlBase.includes('openai.azure.com')
									? { 'api-key': state.config.apiKey }
									: {}),
								'Content-Type': 'application/json',
							},
							body: JSON.stringify({
								model: state.config.model,
								messages: [
									...state.messages,
									{
										role: 'user',
										content:
											'Generate a very short (max 5 words) and concise title for this conversation. Respond only with the title, no other text.',
									},
								],
								stream: false,
							}),
						},
					);

					if (response.ok) {
						const data = await response.json();
						const generatedTitle =
							data.choices?.[0]?.message?.content?.trim() ?? 'New Chat';
						state.title = generatedTitle
							.replace(/[^a-zA-Z0-9 ]/g, '')
							.substring(0, 50);
					} else {
						state.title = 'Error generating title';
					}
				} catch (err) {
					state.title = 'Error generating title';
				}
			} else {
				state.title = 'New Chat';
			}
			break;
		case 'newChat':
			const newState = {
				config: { ...state.config },
				messages: [],
				chatId: Date.now().toString(36),
				title: 'New Chat',
				showConfig: state.showConfig || false,
			};
			res.send(renderPage(newState));
			return;
		default:
			break;
	}

	res.send(renderPage(state));
});

app.post('/newchat', (req, res) => {
	const oldState = getState(req);
	const state = {
		config: { ...oldState.config },
		messages: [],
		chatId: Date.now().toString(36),
		title: 'New Chat',
		showConfig: oldState.showConfig || false,
	};
	res.send(renderPage(state));
});

app.listen(3000, () => console.log('Chat en http://localhost:3000'));
