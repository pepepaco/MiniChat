// server.js — con indicador de procesamiento sin JS cliente
const express = require('express');
const crypto = require('crypto');
const app = express();

app.use(express.urlencoded({ extended: true, limit: '5mb' }));

let marked;
(async () => (marked = await import('marked')))();

// ---------- Config por defecto ----------
const DEFAULT_CONFIG = {
	urlBase: 'https://api.openai.com/v1',
	apiKey: '',
	model: 'gpt-4.1',
	systemPrompt: 'helpful human assistant',
};

// ---------- CSS (mantener estética + animación) ----------
const CSS = `
html,body{height:100%;width:100%;margin:0;padding:0;background:#f8f9fa}
.message span{display:inline-block;padding:.5rem .75rem;border-radius:1rem;margin:.375rem 0;max-width:80%;word-break:break-word}
.message.user span{background:#0d6efd;color:#fff}
.message.openai span{background:#e9ecef;color:#333}
.message.processing span{background:#e9ecef;color:#666;font-style:italic}
.chat-id-tag{font-size:.75rem;color:#888;font-family:monospace;background:#eee;padding:2px 7px;border-radius:12px;margin-left:.5rem}
.speed-indicator{font-size:.85em;color:#888;padding-left:1em}
.chat-messages{scroll-behavior:smooth}
code,pre{font-family:'Fira Mono','Consolas',monospace;background:#f1f3f5;border-radius:4px;padding:2px 6px}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
.processing span{animation:pulse 1.5s ease-in-out infinite}
@media(max-width:600px){.message span{max-width:100%;font-size:1em}}
`;

// ---------- Cifrado ----------
const SECRET = process.env.VIEWSTATE_SECRET || 'please-set-VIEWSTATE_SECRET';
const KEY = crypto.scryptSync(SECRET, 'salt-for-the-key', 32);
const IVL = 16;

const encrypt = txt => {
	const iv = crypto.randomBytes(IVL);
	const c = crypto.createCipheriv('aes-256-cbc', KEY, iv);
	return (
		iv.toString('hex') +
		':' +
		Buffer.concat([c.update(txt), c.final()]).toString('hex')
	);
};
const decrypt = txt => {
	try {
		const [ivHex, dataHex] = txt.split(':');
		const d = crypto.createDecipheriv(
			'aes-256-cbc',
			KEY,
			Buffer.from(ivHex, 'hex'),
		);
		return Buffer.concat([
			d.update(Buffer.from(dataHex, 'hex')),
			d.final(),
		]).toString();
	} catch {
		return null;
	}
};

// ---------- Util: fetch (node compatibility) ----------
const fetcher =
	global.fetch || ((...a) => import('node-fetch').then(m => m.default(...a)));

function getAuthHeaders(cfg) {
	if (!cfg?.apiKey) return { 'Content-Type': 'application/json' };
	const isAzure = cfg.urlBase?.includes('openai.azure.com');
	return {
		'Content-Type': 'application/json',
		Authorization: isAzure ? cfg.apiKey : `Bearer ${cfg.apiKey}`,
		...(isAzure && { 'api-key': cfg.apiKey }),
	};
}

// ---------- Estado (VIEWSTATE + readyStates) ----------
global.__readyStates = global.__readyStates || {}; // chatId -> encrypted state

function getState(req) {
	const vs = req.body?.__VIEWSTATE || req.query?.__VIEWSTATE;
	let parsed = {};
	if (vs) {
		const dec = decrypt(vs);
		if (dec)
			try {
				parsed = JSON.parse(dec);
			} catch {}
	}

	const qChatId = req.query?.chatId || req.body?.chatId;
	const chatId = parsed.chatId || qChatId || Date.now().toString(36);

	// If there's a readyState stored in memory for this chatId, prefer it (race-safe)
	if (global.__readyStates[chatId]) {
		try {
			const dec = decrypt(global.__readyStates[chatId]);
			if (dec) return JSON.parse(dec);
		} catch {}
	}

	// default structure
	return {
		config: parsed.config || { ...DEFAULT_CONFIG },
		messages: parsed.messages || [],
		chatId,
		title: parsed.title || 'New Chat',
		showConfig: parsed.showConfig,
		speedInfo: parsed.speedInfo,
		waiting: parsed.waiting || false,
	};
}

// ---------- Render compacto ----------
function renderPage(state, req = null, isDownload = false) {
	const { config, messages, chatId, title, showConfig, speedInfo, waiting } =
		state;
	const encrypted = encrypt(JSON.stringify(state));
	const meta = waiting
		? `<meta http-equiv="refresh" content="0.1;url=/?chatId=${encodeURIComponent(
				chatId,
		  )}">`
		: '';

	const cfgHtml = showConfig
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

	const lastUserIdx = messages.map(m => m.role).lastIndexOf('user');
	const msgsHtml = messages
		.map((m, i) => {
			if (m.role === 'user') {
				const idAttr = i === lastUserIdx ? ' id="last-user-msg"' : '';
				return `<div class="message user text-end"${idAttr}><span>${escapeHtml(
					m.content,
				)}</span></div>`;
			}
			// Detectar mensaje de procesamiento
			if (m.role === 'assistant' && m.content === '__PROCESSING__') {
				return `<div class="message processing text-start"><span>Processing your request...</span></div>`;
			}
			const speed =
				i === messages.length - 1 && speedInfo
					? `<br><small class="speed-indicator">${speedInfo}</small>`
					: '';
			return `<div class="message openai text-start"><span>${marked.parse(
				m.content,
			)}${speed}</span></div>`;
		})
		.join('\n');

	const baseUrl =
		isDownload && req
			? `<base href="${req.protocol}://${req.get('host')}">`
			: '';

	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
${baseUrl}
${meta}
<title>${escapeHtml(title)} - OpenAI Chat</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
<style>${CSS}</style>
</head>
<body class="d-flex flex-column" style="height:100vh;overflow:hidden">
<form action="/" method="post">
  <input type="hidden" name="__VIEWSTATE" value="${encrypted}"/>
  <!-- Hidden default submit FIRST so Enter triggers sendMessage -->
  <button type="submit" name="action" value="sendMessage" style="display:none" aria-hidden="true"></button>

  <div class="d-flex flex-column" style="height:100vh">
    <header class="p-3 border-bottom d-flex align-items-center justify-content-between">
      <span class="fw-bold">${escapeHtml(
				title,
			)} <small class="text-secondary">VIEWSTATE</small>
        <span class="chat-id-tag" title="ID">${chatId}</span></span>
      <div class="d-flex align-items-center gap-2">
        <button class="btn btn-outline-secondary btn-sm" type="submit" name="action" value="downloadChat">Save</button>
        <button class="btn btn-outline-primary btn-sm" type="submit" name="action" value="refreshTitle">Title</button>
        <button class="btn btn-outline-success btn-sm" type="submit" name="action" value="newChat" formaction="/newchat" formtarget="_blank">New</button>
        <button class="btn btn-link p-0" type="submit" name="action" value="toggleConfig" style="font-size:1.35em;color:#0d6efd" title="Config">&#9881;</button>
      </div>
    </header>

    ${cfgHtml}

    <div class="d-flex flex-column" style="flex:1;overflow-y:auto">
      <main class="p-3 bg-white">${msgsHtml}</main>
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

// ---------- Helpers ----------
function escapeHtml(s = '') {
	return String(s).replace(
		/[&<>"']/g,
		c =>
			({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[
				c
			]),
	);
}

// ---------- OpenAI call con streaming ----------
async function callOpenAIStream(state, messages, onChunk) {
	const url = `${state.config.urlBase}/chat/completions`;
	const res = await fetcher(url, {
		method: 'POST',
		headers: getAuthHeaders(state.config),
		body: JSON.stringify({ model: state.config.model, messages, stream: true }),
	});

	if (!res.ok) return { ok: false, status: res.status, text: await res.text() };

	let fullContent = '';
	let buffer = '';

	// Usar TextDecoder para manejar el stream
	const decoder = new TextDecoder();

	for await (const chunk of res.body) {
		buffer += decoder.decode(chunk, { stream: true });
		const lines = buffer.split('\n');

		// Mantener la última línea incompleta en el buffer
		buffer = lines.pop() || '';

		for (const line of lines) {
			const trimmed = line.trim();
			if (!trimmed || trimmed === 'data: [DONE]') continue;

			if (trimmed.startsWith('data: ')) {
				try {
					const jsonStr = trimmed.slice(6);
					const parsed = JSON.parse(jsonStr);
					const content = parsed.choices?.[0]?.delta?.content;

					if (content) {
						fullContent += content;
						if (onChunk) await onChunk(fullContent);
					}
				} catch (e) {
					// Ignorar errores de parsing de líneas individuales
				}
			}
		}
	}

	return { ok: true, content: fullContent || 'No response received' };
}

// ---------- Rutas ----------
app.get('/', (req, res) => {
	const state = getState(req); // prefer memory if exists
	// If GET and no viewstate but chatId provided, ensure we return the saved in-memory state (avoids empty page on meta-refresh)
	if (!req.query?.__VIEWSTATE && req.query?.chatId) {
		const mem = global.__readyStates[req.query.chatId];
		if (mem) {
			try {
				const dec = decrypt(mem);
				if (dec) return res.send(renderPage(JSON.parse(dec), req));
			} catch {}
		}
	}
	res.send(renderPage(state, req));
});

app.post('/', async (req, res) => {
	const state = getState(req);
	const { userInput, action, urlBase, apiKey, model, systemPrompt } = req.body;

	switch (action) {
		case 'sendMessage':
			if (!userInput) break;

			// Agregar mensaje del usuario
			state.messages.push({ role: 'user', content: userInput });

			// Agregar mensaje temporal de procesamiento
			state.messages.push({ role: 'assistant', content: '__PROCESSING__' });

			state.waiting = true;

			// Persist interim state so meta-refresh GET can read it
			global.__readyStates[state.chatId] = encrypt(JSON.stringify(state));

			// Send interim page (with waiting meta-refresh and processing indicator)
			res.send(renderPage(state));

			// Background generation con streaming
			(async () => {
				// Crear conversación sin el mensaje de procesamiento
				const conv = state.messages.filter(m => m.content !== '__PROCESSING__');

				if (state.config.systemPrompt && conv[0]?.role !== 'system') {
					conv.unshift({ role: 'system', content: state.config.systemPrompt });
				}

				let reply = '';
				const startTime = Date.now();

				try {
					const r = await callOpenAIStream(state, conv, async content => {
						// Actualizar el mensaje de procesamiento con el contenido parcial
						const processingIdx = state.messages.findIndex(
							m =>
								m.content === '__PROCESSING__' ||
								(m.role === 'assistant' &&
									m === state.messages[state.messages.length - 1]),
						);
						if (processingIdx !== -1) {
							state.messages[processingIdx] = { role: 'assistant', content };
						}
						// Guardar estado actualizado
						global.__readyStates[state.chatId] = encrypt(JSON.stringify(state));
					});

					if (!r.ok) {
						reply = `Error ${r.status}: ${r.text}`;
					} else {
						reply = r.content;
					}
				} catch (e) {
					reply = 'Error: ' + e.message;
					console.error('Streaming error:', e);
				}

				// Actualizar con respuesta final
				const processingIdx = state.messages.findIndex(
					m =>
						m.content === '__PROCESSING__' ||
						(m.role === 'assistant' &&
							m === state.messages[state.messages.length - 1]),
				);
				if (processingIdx !== -1) {
					state.messages[processingIdx] = { role: 'assistant', content: reply };
				} else {
					state.messages.push({ role: 'assistant', content: reply });
				}

				const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
				state.speedInfo = `Done in ${elapsed}s. Chars: ${reply.length}`;
				state.waiting = false;

				// Save final
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
			// Filtrar mensajes de procesamiento al descargar
			const cleanState = {
				...state,
				messages: state.messages.filter(m => m.content !== '__PROCESSING__'),
			};
			res.setHeader(
				'Content-Disposition',
				`attachment; filename="${state.title
					.replace(/[^a-z0-9]/gi, '_')
					.toLowerCase()}.html"`,
			);
			res.setHeader('Content-Type', 'text/html');
			return res.send(renderPage(cleanState, req, true));

		case 'refreshTitle':
			if (state.messages.length) {
				try {
					const cleanMsgs = state.messages.filter(
						m => m.content !== '__PROCESSING__',
					);
					const r = await callOpenAIStream(state, [
						...cleanMsgs,
						{
							role: 'user',
							content:
								'Generate a very short (max 5 words) title. Respond only with the title.',
						},
					]);
					state.title = r.ok
						? (r.content || 'New Chat')
								.trim()
								.replace(/[^a-zA-Z0-9 ]/g, '')
								.substring(0, 50)
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
					waiting: false,
				}),
			);
	}

	// Persist current state after non-send actions
	global.__readyStates[state.chatId] = encrypt(JSON.stringify(state));
	res.send(renderPage(state));
});

app.post('/newchat', (req, res) => {
	const old = getState(req);
	res.send(
		renderPage({
			config: { ...old.config },
			messages: [],
			chatId: Date.now().toString(36),
			title: 'New Chat',
			showConfig: old.showConfig,
			waiting: false,
		}),
	);
});

app.listen(process.env.PORT || 3000, () =>
	console.log(`Chat en http://localhost:${process.env.PORT || 3000}`),
);
