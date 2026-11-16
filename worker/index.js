const MAX_BODY_BYTES = 4 * 1024 * 1024;
const GITHUB_API = 'https://api.github.com';

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin');
    const cors = corsHeaders(origin, env.APP_ORIGIN);
    if (origin && origin !== env.APP_ORIGIN) {
      return json({ error: 'Origen no autorizado.' }, 403);
    }

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          ...cors,
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    const pathname = new URL(request.url).pathname;
    if (request.method !== 'POST' || !['/', '/publish'].includes(pathname)) {
      return json({ error: 'Ruta no encontrada.' }, 404, cors);
    }

    if (!env.GITHUB_TOKEN ||
        !env.CLIENT_API_KEYS ||
        !env.GITHUB_BRANCH ||
        !env.APP_ORIGIN) {
      return json({ error: 'El servicio de publicación no está configurado.' }, 503, cors);
    }

    const contentLength = Number(request.headers.get('Content-Length') || 0);
    if (contentLength > MAX_BODY_BYTES) {
      return json({ error: 'El catálogo supera el límite de 4 MB.' }, 413, cors);
    }

    let rawBody;
    try {
      rawBody = await readLimitedBody(request);
    } catch {
      return json({ error: 'No se pudo leer la solicitud.' }, 400, cors);
    }
    if (rawBody === null) {
      return json({ error: 'El catálogo supera el límite de 4 MB.' }, 413, cors);
    }

    let body;
    try {
      body = JSON.parse(rawBody);
    } catch {
      return json({ error: 'El cuerpo de la solicitud no contiene JSON válido.' }, 400, cors);
    }

    const owner = body?.owner;
    const repository = body?.repository;
    if (typeof owner !== 'string' ||
        !/^[A-Za-z0-9-]{1,39}$/.test(owner) ||
        typeof repository !== 'string' ||
        !/^[A-Za-z0-9._-]{1,100}$/.test(repository)) {
      return json({ error: 'El propietario o repositorio GitHub no es válido.' }, 400, cors);
    }

    const repositoryKey = `${owner.toLowerCase()}/${repository.toLowerCase()}`;
    let clientKey;
    try {
      const clientKeys = JSON.parse(env.CLIENT_API_KEYS);
      if (!clientKeys || typeof clientKeys !== 'object' || Array.isArray(clientKeys)) {
        return json({ error: 'La lista de clientes del Worker no es válida.' }, 503, cors);
      }
      clientKey = clientKeys[repositoryKey];
    } catch {
      return json({ error: 'La lista de clientes del Worker no es válida.' }, 503, cors);
    }
    const authorization = request.headers.get('Authorization') || '';
    const providedKey = authorization.startsWith('Bearer ')
      ? authorization.slice(7)
      : '';
    if (typeof clientKey !== 'string' ||
        !constantTimeEqual(providedKey, clientKey)) {
      return json({ error: 'Clave de publicación incorrecta para ese repositorio.' }, 401, cors);
    }

    const catalog = body.catalog;
    if (!isCatalogValid(catalog, repositoryKey)) {
      return json({ error: 'El catálogo no es válido o no corresponde al repositorio.' }, 400, cors);
    }

    let githubToken;
    try {
      githubToken = resolveGithubToken(env.GITHUB_TOKEN, repositoryKey);
    } catch {
      return json({ error: 'El secreto GITHUB_TOKEN no está configurado correctamente.' }, 503, cors);
    }
    if (typeof githubToken !== 'string' || !githubToken.trim()) {
      return json({ error: 'No hay un token GitHub asignado a este repositorio.' }, 503, cors);
    }

    const githubHeaders = {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${githubToken.trim()}`,
      'Content-Type': 'application/json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Synthetix-Store-Publisher',
    };
    const apiUrl =
      `${GITHUB_API}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}` +
      '/contents/productos.json';
    const current = await fetch(
      `${apiUrl}?ref=${encodeURIComponent(env.GITHUB_BRANCH)}`,
      { headers: githubHeaders },
    );
    let sha;
    if (current.ok) {
      const currentFile = await current.json();
      sha = currentFile.sha;
    } else if (current.status !== 404) {
      return githubError(current, cors);
    }

    const catalogBytes = new TextEncoder().encode(JSON.stringify(catalog, null, 2));
    const update = await fetch(apiUrl, {
      method: 'PUT',
      headers: githubHeaders,
      body: JSON.stringify({
        message: `Actualizar tienda ${repositoryKey}`,
        content: toBase64(catalogBytes),
        branch: env.GITHUB_BRANCH,
        ...(sha ? { sha } : {}),
      }),
    });
    if (!update.ok) return githubError(update, cors);

    const pagesPath =
      repository.toLowerCase() === `${owner.toLowerCase()}.github.io`
        ? ''
        : `/${repository.toLowerCase()}`;
    const url =
      `https://${owner.toLowerCase()}.github.io${pagesPath}/tienda.html` +
      `?negocio=${encodeURIComponent(repositoryKey)}`;
    return json({ ok: true, url }, 200, cors);
  },
};

function isCatalogValid(catalog, repositoryKey) {
  if (!catalog ||
      typeof catalog !== 'object' ||
      catalog.schemaVersion !== 1 ||
      !catalog.business ||
      typeof catalog.business !== 'object' ||
      catalog.business.id !== repositoryKey ||
      typeof catalog.business.name !== 'string' ||
      !catalog.business.name.trim() ||
      typeof catalog.business.slogan !== 'string' ||
      typeof catalog.business.whatsapp !== 'string' ||
      !/^\d{8,15}$/.test(catalog.business.whatsapp) ||
      !catalog.business.colors ||
      !/^#[0-9a-f]{6}$/i.test(catalog.business.colors.primary) ||
      !/^#[0-9a-f]{6}$/i.test(catalog.business.colors.accent) ||
      !isSafeImageSource(catalog.business.logo) ||
      !Array.isArray(catalog.products) ||
      catalog.products.length > 10000) {
    return false;
  }
  return catalog.products.every((product) =>
    product &&
    typeof product.id === 'string' &&
    product.id.length > 0 &&
    typeof product.name === 'string' &&
    product.name.trim().length > 0 &&
    Number.isFinite(product.price) && product.price >= 0 &&
    Number.isFinite(product.stock) &&
    typeof product.currencyCode === 'string' &&
    /^[A-Z]{3}$/.test(product.currencyCode) &&
    isSafeImageSource(product.image) &&
    Array.isArray(product.variants) &&
    product.variants.every((variant) =>
      variant &&
      typeof variant.id === 'string' &&
      Number.isFinite(variant.price) &&
      variant.price >= 0 &&
      Number.isFinite(variant.stock) &&
      variant.attributes &&
      typeof variant.attributes === 'object' &&
      !Array.isArray(variant.attributes)));
}

function isSafeImageSource(source) {
  if (source === null) return true;
  if (typeof source !== 'string') return false;
  if (/^data:image\/(?:png|jpeg|webp|gif);base64,[A-Za-z0-9+/]+=*$/.test(source)) {
    return true;
  }
  try {
    return new URL(source).protocol === 'https:';
  } catch {
    return false;
  }
}

function corsHeaders(origin, allowedOrigin) {
  if (!origin || !allowedOrigin || origin !== allowedOrigin) return {};
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    Vary: 'Origin',
  };
}

function json(value, status, headers = {}) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      ...headers,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}

function constantTimeEqual(first, second) {
  if (typeof first !== 'string' || typeof second !== 'string') return false;
  const firstBytes = new TextEncoder().encode(first);
  const secondBytes = new TextEncoder().encode(second);
  if (firstBytes.length !== secondBytes.length) return false;
  let difference = 0;
  for (let index = 0; index < firstBytes.length; index++) {
    difference |= firstBytes[index] ^ secondBytes[index];
  }
  return difference === 0;
}

function resolveGithubToken(secret, repositoryKey) {
  const value = secret.trim();
  if (!value.startsWith('{')) return value;
  const repositoryTokens = JSON.parse(value);
  if (!repositoryTokens ||
      typeof repositoryTokens !== 'object' ||
      Array.isArray(repositoryTokens)) {
    throw new Error('Invalid GITHUB_TOKEN map.');
  }
  return repositoryTokens[repositoryKey];
}

async function readLimitedBody(request) {
  const reader = request.body?.getReader();
  if (!reader) return '';
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > MAX_BODY_BYTES) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder().decode(bytes);
}

function toBase64(bytes) {
  let binary = '';
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

async function githubError(response, cors) {
  let detail = '';
  try {
    const body = await response.json();
    if (typeof body.message === 'string') detail = body.message;
  } catch {
    detail = '';
  }
  const message = response.status === 409
    ? 'El repositorio cambió al mismo tiempo. Intenta actualizar de nuevo.'
    : `GitHub rechazó la publicación (HTTP ${response.status})${detail ? `: ${detail}` : '.'}`;
  return json({ error: message }, response.status === 409 ? 409 : 502, cors);
}
