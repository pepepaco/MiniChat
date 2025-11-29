const express = require('express');
const crypto = require('crypto');
const app = express();

app.use(express.urlencoded({ extended: true, limit: '5mb' }));

let marked;
(async () => (marked = await import('marked')))();

const DEFAULT_CONFIG = {
	urlBase: 'https://api.openai.com/v1',
	apiKey: '',
	model: 'gpt-4.1',
	systemPrompt: 'helpful human assistant',
};

const CSS = `
html,body{height:100%;width:100%;margin:0;padding:0;background:#f8f9fa}
.message span{display:inline-block;padding:.5rem .75rem;border-radius:1rem;margin:.375rem 0;max-width:80%;word-break:break-word}
.message.user span{background:#0d6efd;color:#fff}
.message.openai span{background:#e9ecef;color:#333}
.chat-id-tag{font-size:.75rem;color:#888;font-family:monospace;background:#eee;padding:2px 7px;border-radius:12px;margin-left:.5rem}
.speed-indicator{font-size:.85em;color:#888;padding-left:1em}
.chat-messages{scroll-behavior:smooth}
code,pre{font-family:'Fira Mono','Consolas',monospace;background:#f1f3f5;border-radius:4px;padding:2px 6px}
@media(max-width:600px){.message span{max-width:100%;font-size:1em}}
`;

const ENCRYPTION_KEY = crypto.scryptSync(
	'your-secret-password-that-is-long-enough',
	'salt-for-the-key',
	32,
);
const IV_LENGTH = 16;

function encrypt(text) {
	const iv = crypto.randomBytes(IV_LENGTH);
	const cipher = crypto.createCipheriv('aes-256-cbc', ENCRYPTION_KEY, iv);
	return (
		iv.toString('hex') +
		':' +
		Buffer.concat([cipher.update(text), cipher.final()]).toString('hex')
	);
}

function decrypt(text) {
	try {
		const [iv, encrypted] = text.split(':');
		const decipher = crypto.createDecipheriv(
			'aes-256-cbc',
			ENCRYPTION_KEY,
			Buffer.from(iv, 'hex'),
		);
		return Buffer.concat([
			decipher.update(Buffer.from(encrypted, 'hex')),
			decipher.final(),
		]).toString();
	} catch {
		return null;
	}
}

function getState(req) {
	const viewstate = req.body?.__VIEWSTATE || req.query?.__VIEWSTATE;
	const qChatId = req.query?.chatId;
	let state = {};

	// Try to get state from VIEWSTATE
	if (viewstate) {
		const decrypted = decrypt(viewstate);
		if (decrypted) {
			try {
				state = JSON.parse(decrypted);
			} catch {}
		}
	}

	// Try to get ready state from global storage
	const chatId = state.chatId || qChatId;
	if (chatId && global.__readyStates?.[chatId]) {
		try {
			const readyDecrypted = decrypt(global.__readyStates[chatId]);
			delete global.__readyStates[chatId];
			if (readyDecrypted) return JSON.parse(readyDecrypted);
		} catch {}
	}

	// Initialize default state
	return {
		config: state.config || { ...DEFAULT_CONFIG },
		messages: state.messages || [],
		chatId: state.chatId || Date.now().toString(36),
		title: state.title || 'New Chat',
		showConfig: state.showConfig,
	};
}

function renderPage(state, req = null, isDownload = false) {
	const { config, messages, chatId, title, showConfig, speedInfo } = state;
	const encryptedState = encrypt(JSON.stringify(state));
	const lastUserMsgIndex = messages.map(m => m.role).lastIndexOf('user');
	const lastMsg = messages[messages.length - 1];
	const isWaiting =
		lastMsg?.role === 'assistant' &&
		lastMsg.content === 'Recibido, generando respuesta...';

	const speedHtml = speedInfo
		? `<br><small class="speed-indicator">${speedInfo}</small>`
		: '';
	const metaRefresh = isWaiting
		? `<meta http-equiv="refresh" content="2;url=/?chatId=${encodeURIComponent(
				chatId,
		  )}">`
		: '';
	const baseUrl =
		isDownload && req
			? `<base href="${req.protocol}://${req.get('host')}">`
			: '';

	const configSection = showConfig
		? `
		<section class="bg-light border-bottom" style="padding:16px">
			<div class="mb-2"><label class="form-label">Base URL</label>
				<input type="text" class="form-control" name="urlBase" value="${
					config.urlBase
				}" autocomplete="on"/></div>
			<div class="mb-2"><label class="form-label">API Key</label>
				<input type="text" class="form-control" name="apiKey" value="${
					config.apiKey
				}" autocomplete="on"/></div>
			<div class="mb-2"><label class="form-label">Model</label>
				<input type="text" class="form-control" name="model" value="${
					config.model
				}" autocomplete="on"/></div>
			<div class="mb-2"><label class="form-label">System prompt</label>
				<textarea class="form-control" name="systemPrompt" rows="2" autocomplete="on">${
					config.systemPrompt || ''
				}</textarea></div>
			<button type="submit" class="btn btn-primary btn-sm w-100" name="action" value="saveSettings">Guardar</button>
		</section>`
		: '';

	const messagesHtml = messages
		.map((msg, i) => {
			if (msg.role === 'user') {
				const idAttr = i === lastUserMsgIndex ? ' id="last-user-msg"' : '';
				return `<div class="message user text-end"${idAttr}><span>${msg.content}</span></div>`;
			}
			const speed = i === messages.length - 1 ? speedHtml : '';
			return `<div class="message openai text-start"><span>${marked.parse(
				msg.content,
			)}${speed}</span></div>`;
		})
		.join('\n');

	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
${baseUrl}
${metaRefresh}
<title>${title} - OpenAI Chat</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
<style>${CSS}</style>
</head>
<body class="d-flex flex-column" style="height:100vh;overflow:hidden">
<form action="/" method="post">
<input type="hidden" name="__VIEWSTATE" value="${encryptedState}"/>
<button type="submit" name="action" value="sendMessage" style="display:none" aria-hidden="true"></button>
<div class="d-flex flex-column" style="height:100vh">
	<header class="p-3 border-bottom d-flex align-items-center justify-content-between">
		<span class="fw-bold">${title} <small class="text-secondary">VIEWSTATE</small>
			<span class="chat-id-tag" title="ID">${chatId}</span></span>
		<div class="d-flex align-items-center gap-2">
			<button class="btn btn-outline-secondary btn-sm" type="submit" name="action" value="downloadChat">Save</button>
			<button class="btn btn-outline-primary btn-sm" type="submit" name="action" value="refreshTitle">Title</button>
			<button class="btn btn-outline-success btn-sm" type="submit" name="action" value="newChat" formaction="/newchat" formtarget="_blank">New</button>
			<button class="btn btn-link p-0" type="submit" name="action" value="toggleConfig" style="font-size:1.35em;color:#0d6efd" title="Config">&#9881;</button>
		</div>
	</header>
	${configSection}
	<div class="d-flex flex-column" style="flex:1;overflow-y:auto">
		<main class="p-3 bg-white">${messagesHtml}</main>
		<div class="d-flex p-3 gap-2 bg-white border-top">
			<input type="text" class="form-control flex-grow-1" name="userInput" placeholder="Message..." autofocus autocomplete="off"/>
			<button class="btn btn-primary" type="submit" name="action" value="sendMessage">Send</button>
		</div>
	</div>
</div>
</form>
</body>
</html>`;
}

function getAuthHeaders(cfg) {
	if (!cfg?.apiKey) return { 'Content-Type': 'application/json' };
	const isAzure = cfg.urlBase?.includes('openai.azure.com');
	return {
		'Content-Type': 'application/json',
		Authorization: isAzure ? cfg.apiKey : `Bearer ${cfg.apiKey}`,
		...(isAzure && { 'api-key': cfg.apiKey }),
	};
}

async function callOpenAI(state, messages) {
	const fetcher =
		global.fetch ||
		((...args) => import('node-fetch').then(({ default: f }) => f(...args)));
	const res = await fetcher(`${state.config.urlBase}/chat/completions`, {
		method: 'POST',
		headers: getAuthHeaders(state.config),
		body: JSON.stringify({
			model: state.config.model,
			messages,
			stream: false,
		}),
	});

	if (!res.ok) return { ok: false, status: res.status, text: await res.text() };
	return { ok: true, data: await res.json() };
}

app.get('/', (req, res) => res.send(renderPage(getState(req))));

app.post('/', async (req, res) => {
	const state = getState(req);
	const { userInput, action, urlBase, apiKey, model, systemPrompt } = req.body;

	switch (action) {
		case 'sendMessage':
			if (!userInput) break;

			state.messages.push({ role: 'user', content: userInput });
			const tempState = {
				...state,
				messages: [
					...state.messages,
					{ role: 'assistant', content: 'Recibido, generando respuesta...' },
				],
			};

			res.setHeader('Content-Type', 'text/html; charset=utf-8');
			res.send(renderPage(tempState));

			(async () => {
				let convSend = [...state.messages];
				if (state.config.systemPrompt && convSend[0]?.role !== 'system') {
					convSend.unshift({
						role: 'system',
						content: state.config.systemPrompt,
					});
				}

				let reply;
				try {
					const result = await callOpenAI(state, convSend);
					reply = result.ok
						? result.data.choices?.[0]?.message?.content ?? 'No response'
						: `Error ${result.status}: ${result.text}`;
				} catch (err) {
					reply = 'Error: ' + err.message;
				}

				state.messages.push({ role: 'assistant', content: reply });
				state.speedInfo = `Done. Tokens: ${reply.length}`;

				global.__readyStates = global.__readyStates || {};
				global.__readyStates[state.chatId] = encrypt(JSON.stringify(state));
			})();
			return;

		case 'toggleConfig':
			state.showConfig = !state.showConfig;
			break;

		case 'saveSettings':
			Object.assign(state.config, { urlBase, apiKey, model, systemPrompt });
			state.showConfig = false;
			break;

		case 'downloadChat':
			res.setHeader(
				'Content-Disposition',
				`attachment; filename="${state.title
					.replace(/[^a-z0-9]/gi, '_')
					.toLowerCase()}.html"`,
			);
			res.setHeader('Content-Type', 'text/html');
			return res.send(renderPage(state, req, true));

		case 'refreshTitle':
			if (state.messages.length) {
				try {
					const result = await callOpenAI(state, [
						...state.messages,
						{
							role: 'user',
							content:
								'Generate a very short (max 5 words) title. Respond only with the title.',
						},
					]);
					state.title = result.ok
						? result.data.choices?.[0]?.message?.content
								?.trim()
								.replace(/[^a-zA-Z0-9 ]/g, '')
								.substring(0, 50) || 'New Chat'
						: 'Error generating title';
				} catch {
					state.title = 'Error generating title';
				}
			}
			break;

		case 'newChat':
			return res.send(
				renderPage({
					config: { ...state.config },
					messages: [],
					chatId: Date.now().toString(36),
					title: 'New Chat',
					showConfig: state.showConfig,
				}),
			);
	}

	res.send(renderPage(state));
});

app.post('/newchat', (req, res) => {
	const oldState = getState(req);
	res.send(
		renderPage({
			config: { ...oldState.config },
			messages: [],
			chatId: Date.now().toString(36),
			title: 'New Chat',
			showConfig: oldState.showConfig,
		}),
	);
});

app.listen(process.env.PORT || 3000, () =>
	console.log(`Chat en http://localhost:${process.env.PORT || 3000}`),
);
