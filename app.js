const express = require('express');
const crypto = require('crypto');
const cookieParser = require('cookie-parser');
const fetch = require('node-fetch').default;

const app = express();
const CONFIG_COOKIE = 'chat_config_v1';

app.use(express.urlencoded({ extended: true, limit: '5mb' }));
app.use(express.json({ limit: '5mb' }));
app.use(cookieParser());

const DEFAULT_CONFIG = {
	urlBase: 'https://api.openai.com/v1',
	apiKey: '',
	model: 'gpt-4.1',
	systemPrompt: 'helpful human assistant',
};

const CSS = `
@keyframes fadeIn{from{opacity:0}to{opacity:1}}
html,body{height:100%;width:100%;margin:0;padding:0;background:#f8f9fa;animation:fadeIn .4s ease-out}
.message span{display:inline-block;padding:.5rem .75rem;border-radius:1rem;margin:.375rem 0;max-width:80%;word-break:break-word}
.message.user span{background:#0d6efd;color:#fff}
.message.openai span{background:#e9ecef;color:#333}
.chat-id-tag{font-size:.75rem;color:#888;font-family:monospace;background:#eee;padding:2px 7px;border-radius:12px;margin-left:.5rem}
.speed-indicator{font-size:.85em;color:#888;padding-left:1em}
code,pre{font-family:'Fira Mono','Consolas',monospace;background:#f1f3f5;border-radius:4px;padding:2px 6px}
@media(max-width:600px){.message span{max-width:100%;font-size:1em}}
`;

// Import dinámico de marked como variable global
let marked;
(async () => {
	marked = (await import('marked')).marked;
})();

// Crypto simplificado
const ENCRYPTION_KEY = crypto.scryptSync(
	'your-secret-password-that-is-long-enough',
	'salt-for-the-key',
	32,
);
const encrypt = text => {
	const iv = crypto.randomBytes(16);
	const cipher = crypto.createCipheriv('aes-256-cbc', ENCRYPTION_KEY, iv);
	return (
		iv.toString('hex') +
		':' +
		Buffer.concat([cipher.update(text), cipher.final()]).toString('hex')
	);
};

const decrypt = text => {
	try {
		const [ivHex, encHex] = text.split(':');
		const decipher = crypto.createDecipheriv(
			'aes-256-cbc',
			ENCRYPTION_KEY,
			Buffer.from(ivHex, 'hex'),
		);
		return Buffer.concat([
			decipher.update(Buffer.from(encHex, 'hex')),
			decipher.final(),
		]).toString();
	} catch {
		return null;
	}
};

// State management
const loadConfig = req => {
	const cookie = req.cookies?.[CONFIG_COOKIE];
	if (cookie) {
		const decrypted = decrypt(cookie);
		if (decrypted)
			try {
				return JSON.parse(decrypted);
			} catch {}
	}
	return {};
};

const getState = req => {
	let state = {};
	const viewstate = req.body?.__VIEWSTATE || req.query?.__VIEWSTATE;
	if (viewstate) {
		const decrypted = decrypt(viewstate);
		if (decrypted)
			try {
				state = JSON.parse(decrypted);
			} catch {}
	}
	state.config = { ...DEFAULT_CONFIG, ...state.config, ...loadConfig(req) };
	state.messages = state.messages || [];
	state.chatId = state.chatId || Date.now().toString(36);
	state.title = state.title || 'New Chat 💬';
	return state;
};

// Render HTML (síncrono, usa variable global marked)
const renderPage = (state, req = null, isDownload = false) => {
	const { config, messages, chatId, showConfig } = state;
	const encryptedState = encrypt(JSON.stringify(state));
	const lastUserIdx = messages.map(m => m.role).lastIndexOf('user');
	const speedInfo = state.speedInfo
		? `<br><small class="speed-indicator">${state.speedInfo}</small>`
		: '';
	state.speedInfo = null;

	const baseUrl =
		isDownload && req
			? `<base href="${req.protocol}://${req.get('host')}">`
			: '';

	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
${baseUrl}
<title>${state.title} - OpenAI Chat</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="view-transition" content="same-origin">
<meta http-equiv="Cache-Control" content="no-cache,no-store,must-revalidate">
<meta name="theme-color" content="#0d6efd">
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
<style>${CSS}</style>
</head>
<body class="d-flex flex-column" style="height:100vh;overflow:hidden">
<form action="/" method="post">
<input type="hidden" name="__VIEWSTATE" value="${encryptedState}"/>
<button type="submit" name="action" value="sendMessage" style="display:none" aria-hidden="true"></button>
<div class="d-flex flex-column" style="height:100vh">
<header class="p-3 border-bottom d-flex align-items-center justify-content-between">
  <span class="fw-bold">${
		state.title
	} <small class="text-secondary">VIEWSTATE</small>
  <span class="chat-id-tag">${chatId}</span></span>
  <div class="d-flex align-items-center gap-2">
  <button class="btn btn-outline-secondary btn-sm" type="submit" name="action" value="downloadChat">Save</button>
  <button class="btn btn-outline-primary btn-sm" type="submit" name="action" value="refreshTitle">Refresh Title</button>
  <button class="btn btn-outline-success btn-sm" type="submit" name="action" value="newChat" formaction="/newchat" formtarget="_blank">New chat</button>
  <button class="btn btn-link p-0" type="submit" name="action" value="toggleConfig" style="font-size:1.35em;color:#0d6efd">&#9881;</button>
  </div>
</header>
${
	showConfig
		? `
<section class="bg-light border-bottom" style="padding:16px">
<div class="mb-2">
<label class="form-label">Base URL</label>
<input type="text" class="form-control" name="urlBase" value="${
				config.urlBase
		  }" autocomplete="on"/>
</div>
<div class="mb-2">
<label class="form-label">API Key</label>
<input type="text" class="form-control" name="apiKey" value="${
				config.apiKey
		  }" autocomplete="on"/>
</div>
<div class="mb-2">
<label class="form-label">Model</label>
<input type="text" class="form-control" name="model" value="${
				config.model
		  }" autocomplete="on"/>
</div>
<div class="mb-2">
<label class="form-label">System prompt</label>
<textarea class="form-control" name="systemPrompt" rows="2" autocomplete="on">${
				config.systemPrompt || ''
		  }</textarea>
</div>
<button type="submit" class="btn btn-primary btn-sm w-100" name="action" value="saveSettings">Guardar</button>
</section>`
		: ''
}
<div class="d-flex flex-column" style="flex:1;overflow-y:auto">
  <main class="p-3 bg-white">
  ${messages
		.map((msg, i) =>
			msg.role === 'user'
				? `<div class="message user text-end"${
						i === lastUserIdx ? ' id="last-user-msg"' : ''
				  }><span>${msg.content}</span></div>`
				: `<div class="message openai text-start"><span>${marked?.parse(
						msg.content,
				  )}${i === messages.length - 1 ? speedInfo : ''}</span></div>`,
		)
		.join('\n')}
  </main>
  <div class="d-flex p-3 gap-2 bg-white border-top">
  <input type="text" class="form-control flex-grow-1" name="userInput" placeholder="Type your message..." autofocus autocomplete="off"/>
  <button class="btn btn-primary flex-shrink-0" type="submit" name="action" value="sendMessage">Send</button>
  </div>
</div>
</div>
</form>
</body>
</html>`;
};

// API helpers
const getAuthHeaders = cfg => {
	if (!cfg?.apiKey) return { 'Content-Type': 'application/json' };
	const isAzure = cfg.urlBase?.includes('openai.azure.com');
	return {
		'Content-Type': 'application/json',
		...(isAzure
			? { 'api-key': cfg.apiKey }
			: { Authorization: `Bearer ${cfg.apiKey}` }),
	};
};

const callOpenAI = async (state, messages) => {
	const url = `${state.config.urlBase.replace(/\/+$/, '')}/chat/completions`;
	try {
		const res = await fetch(url, {
			method: 'POST',
			headers: getAuthHeaders(state.config),
			body: JSON.stringify({ model: state.config.model, messages }),
		});

		if (!res.ok) {
			const text = await res.text().catch(() => '');
			return { ok: false, status: res.status, text };
		}

		const data = await res.json();
		return { ok: true, data };
	} catch (err) {
		return { ok: false, status: 0, text: String(err) };
	}
};

// Routes
app.get('/', (req, res) => res.send(renderPage(getState(req)));

app.post('/', async (req, res) => {
	const state = getState(req);
	const { userInput, action, urlBase, apiKey, model, systemPrompt } = req.body;

	switch (action) {
		case 'sendMessage':
			if (userInput) {
				state.messages.push({ role: 'user', content: userInput });
				let conv = [...state.messages];
				if (state.config.systemPrompt && conv[0]?.role !== 'system') {
					conv = [
						{ role: 'system', content: state.config.systemPrompt },
						...conv,
					];
				}

				const result = await callOpenAI(state, conv);
				if (result.ok) {
					const reply =
						result.data.choices?.[0]?.message?.content ?? 'No response';
					state.messages.push({ role: 'assistant', content: reply });
					state.speedInfo = `Tokens: ${reply.length}`;
				} else {
					state.messages.push({
						role: 'assistant',
						content: `Error ${result.status}: ${result.text}`,
					});
				}
			}
			break;

		case 'toggleConfig':
			state.showConfig = !state.showConfig;
			break;

		case 'saveSettings':
			Object.assign(state.config, { urlBase, apiKey, model, systemPrompt });
			state.showConfig = false;
			res.cookie(CONFIG_COOKIE, encrypt(JSON.stringify(state.config)), {
				httpOnly: true,
				secure: app.get('env') === 'production',
				maxAge: 365 * 24 * 60 * 60 * 1000,
				sameSite: 'Strict',
			});
			break;

		case 'downloadChat':
			res.setHeader(
				'Content-Disposition',
				`attachment;filename="${state.title
					.replace(/[^a-z0-9]/gi, '_')
					.toLowerCase()}.html"`,
			);
			res.setHeader('Content-Type', 'text/html');
			return res.send(renderPage(state, req, true));

		case 'refreshTitle':
			if (state.messages.length) {
				const result = await callOpenAI(state, [
					...state.messages,
					{
						role: 'user',
						content:
							'Generate a very short (max 5 words) title with emoji at start. Only emoji + title, no other text.',
					},
				]);
				state.title = result.ok
					? (
							result.data.choices?.[0]?.message?.content?.trim() ??
							'New Chat 💬'
					  ).substring(0, 50)
					: 'Error ❌';
			}
			break;

		case 'newChat':
			return res.send(
				renderPage({
					config: state.config,
					messages: [],
					chatId: Date.now().toString(36),
					title: 'New Chat 💬',
					showConfig: state.showConfig,
				}),
			);
	}

	res.send(renderPage(state));
});

app.post('/newchat', (req, res) => {
	const old = getState(req);
	res.send(
		renderPage({
			config: old.config,
			messages: [],
			chatId: Date.now().toString(36),
			title: 'New Chat 💬',
			showConfig: old.showConfig,
		}),
	);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Chat en http://localhost:${PORT}`));
