const MAX_BODY_BYTES = 4 * 1024 * 1024;
const MAX_TEMPLATE_BYTES = 256 * 1024;
const GITHUB_API = 'https://api.github.com';
const DEFAULT_APP_ORIGIN = 'https://synthetixapp17.github.io';

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin');
    const allowedOrigins = [DEFAULT_APP_ORIGIN, env.APP_ORIGIN].filter(Boolean);
    const cors = corsHeaders(origin, allowedOrigins);
    if (origin && !allowedOrigins.includes(origin)) {
      return json({ error: 'Origen no autorizado.' }, 403);
    }

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          ...cors,
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    const pathname = new URL(request.url).pathname;
    if (request.method !== 'POST' || !['/', '/publish'].includes(pathname)) {
      return json({ error: 'Ruta no encontrada.' }, 404, cors);
    }

    if (!env.GITHUB_TOKEN ||
        !env.GITHUB_OWNER ||
        !env.APP_ORIGIN ||
        !env.APP_TEMPLATE_URL ||
        !env.STORE_CONFIGS ||
        !env.PUBLISH_RATE_LIMITER) {
      return json({ error: 'El servicio de publicación no está configurado.' }, 503, cors);
    }

    let rateLimit;
    try {
      const clientIp = request.headers.get('CF-Connecting-IP') || 'unknown';
      rateLimit = await env.PUBLISH_RATE_LIMITER.limit({ key: clientIp });
    } catch {
      return json({ error: 'No se pudo verificar el límite de solicitudes.' }, 503, cors);
    }
    if (!rateLimit.success) {
      return json({ error: 'Demasiadas solicitudes. Intenta de nuevo más tarde.' }, 429, cors);
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

    const businessId = body?.businessId;
    if (typeof businessId !== 'string' ||
        !businessId.trim() ||
        businessId.trim().length > 80) {
      return json({ error: 'El nombre de la tienda no es válido.' }, 400, cors);
    }

    const storeName = businessId.trim();
    const storeSlug = normalizeStoreSlug(storeName);
    if (!storeSlug) {
      return json({ error: 'El nombre debe incluir letras o números.' }, 400, cors);
    }

    const catalog = body.catalog;
    if (!isCatalogValid(catalog, storeName)) {
      return json({ error: 'El catálogo no es válido o no corresponde a esta tienda.' }, 400, cors);
    }

    const configKey = `store:${storeSlug}`;
    let storeConfig;
    let isFirstRequest = false;
    try {
      const stored = await env.STORE_CONFIGS.get(configKey);
      if (stored) {
        storeConfig = JSON.parse(stored);
        if (storeConfig.businessId !== storeName) {
          return json(
            { error: 'El nombre de tienda coincide con otro nombre publicado.' },
            409,
            cors,
          );
        }
      } else {
        isFirstRequest = true;
        storeConfig = {
          businessId: storeName,
          repository: `tienda-${storeSlug}`,
        };
      }
    } catch {
      return json({ error: 'No se pudo consultar la tienda.' }, 503, cors);
    }

    const owner = env.GITHUB_OWNER.trim();
    if (!/^[A-Za-z0-9-]{1,39}$/.test(owner)) {
      return json({ error: 'El propietario de publicación no está configurado correctamente.' }, 503, cors);
    }

    const githubHeaders = {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${env.GITHUB_TOKEN.trim()}`,
      'Content-Type': 'application/json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Synthetix-Store-Publisher',
    };

    let repository;
    try {
      repository = await ensureRepository(
        owner,
        storeConfig.repository,
        githubHeaders,
        isFirstRequest,
        cors,
      );
    } catch {
      return json({ error: 'No se pudo preparar el repositorio de la tienda.' }, 502, cors);
    }
    if (repository instanceof Response) return repository;

    const branch = repository.default_branch;
    if (typeof branch !== 'string' || !branch) {
      return json({ error: 'El repositorio no tiene una rama principal válida.' }, 502, cors);
    }

    try {
      if (isFirstRequest) {
        await env.STORE_CONFIGS.put(configKey, JSON.stringify(storeConfig));
      }

      const template = await fetchStoreTemplate(env.APP_TEMPLATE_URL, env.APP_ORIGIN);
      if (!template.ok) return json({ error: template.error }, template.status, cors);
      const templateHash = await hashTemplate(template.contents);
      if (storeConfig.templateHash !== templateHash) {
        const templateResult = await writeGithubFile({
          owner,
          repository: storeConfig.repository,
          branch,
          path: 'tienda.html',
          contents: template.contents,
          message: `Configurar tienda ${storeName}`,
          githubHeaders,
          cors,
        });
        if (templateResult instanceof Response) return templateResult;
        storeConfig.templateHash = templateHash;
      }

      const catalogBytes = new TextEncoder().encode(JSON.stringify(catalog, null, 2));
      const catalogResult = await writeGithubFile({
        owner,
        repository: storeConfig.repository,
        branch,
        path: 'productos.json',
        contents: catalogBytes,
        message: `Actualizar tienda ${storeName}`,
        githubHeaders,
        cors,
      });
      if (catalogResult instanceof Response) return catalogResult;

      const pagesResult = await ensurePages(owner, storeConfig.repository, branch, githubHeaders, cors);
      if (pagesResult instanceof Response) return pagesResult;

      await env.STORE_CONFIGS.put(configKey, JSON.stringify(storeConfig));
    } catch {
      return json({ error: 'No se pudo publicar el catálogo de la tienda.' }, 502, cors);
    }

    const url = `https://${owner.toLowerCase()}.github.io/${storeConfig.repository}/tienda.html` +
      `?negocio=${encodeURIComponent(storeName)}`;
    return json({ ok: true, url }, 200, cors);
  },
};

async function ensureRepository(owner, repository, headers, isFirstRequest, cors) {
  const repositoryUrl = `${GITHUB_API}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}`;
  const current = await fetch(repositoryUrl, { headers });
  if (current.ok) {
    if (isFirstRequest) {
      return json({ error: 'El nombre de tienda ya está en uso.' }, 409, cors);
    }
    return current.json();
  }
  if (current.status !== 404) return githubError(current, cors);

  const created = await fetch(`${GITHUB_API}/user/repos`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      name: repository,
      description: 'Catálogo público de tienda virtual',
      private: false,
      auto_init: true,
      has_issues: false,
      has_projects: false,
      has_wiki: false,
    }),
  });
  if (created.ok) return created.json();

  if (created.status === 422) {
    const retry = await fetch(repositoryUrl, { headers });
    if (retry.ok && !isFirstRequest) return retry.json();
  }
  return githubError(created, cors);
}

function normalizeStoreSlug(name) {
  const slug = name
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/[-_]{2,}/g, '-');
  return /^[a-z0-9][a-z0-9_-]{0,79}$/.test(slug) ? slug : null;
}

async function fetchStoreTemplate(templateUrl, appOrigin) {
  let template;
  try {
    template = new URL(templateUrl);
  } catch {
    return { ok: false, status: 503, error: 'La URL de la plantilla no es válida.' };
  }
  if (template.protocol !== 'https:' || template.origin !== appOrigin) {
    return { ok: false, status: 503, error: 'La plantilla debe pertenecer al origen configurado de la app.' };
  }

  let response;
  try {
    response = await fetch(template, {
      headers: { Accept: 'text/html' },
    });
  } catch {
    return { ok: false, status: 503, error: 'No se pudo cargar la plantilla de la tienda.' };
  }
  if (!response.ok) {
    return { ok: false, status: 503, error: 'La plantilla pública de la tienda no está disponible.' };
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length > MAX_TEMPLATE_BYTES) {
    return { ok: false, status: 503, error: 'La plantilla de la tienda supera el tamaño permitido.' };
  }
  return { ok: true, contents: bytes };
}

async function writeGithubFile({
  owner,
  repository,
  branch,
  path,
  contents,
  message,
  githubHeaders,
  cors,
}) {
  const fileUrl =
    `${GITHUB_API}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}` +
    `/contents/${path}`;
  const current = await fetch(`${fileUrl}?ref=${encodeURIComponent(branch)}`, {
    headers: githubHeaders,
  });
  let sha;
  if (current.ok) {
    const currentFile = await current.json();
    sha = currentFile.sha;
  } else if (current.status !== 404) {
    return githubError(current, cors);
  }

  const bytes = contents instanceof Uint8Array
    ? contents
    : new TextEncoder().encode(contents);
  const update = await fetch(fileUrl, {
    method: 'PUT',
    headers: githubHeaders,
    body: JSON.stringify({
      message,
      content: toBase64(bytes),
      branch,
      ...(sha ? { sha } : {}),
    }),
  });
  if (!update.ok) return githubError(update, cors);
  return null;
}

async function ensurePages(owner, repository, branch, headers, cors) {
  const pagesUrl =
    `${GITHUB_API}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}/pages`;
  const current = await fetch(pagesUrl, { headers });
  if (current.ok) return null;
  if (current.status !== 404) return githubError(current, cors);

  const created = await fetch(pagesUrl, {
    method: 'POST',
    headers,
    body: JSON.stringify({ source: { branch, path: '/' } }),
  });
  return created.ok ? null : githubError(created, cors);
}

function isCatalogValid(catalog, businessId) {
  if (!catalog ||
      typeof catalog !== 'object' ||
      catalog.schemaVersion !== 1 ||
      !catalog.business ||
      typeof catalog.business !== 'object' ||
      catalog.business.id !== businessId ||
      typeof catalog.business.name !== 'string' ||
      !catalog.business.name.trim() ||
      typeof catalog.business.slogan !== 'string' ||
      typeof catalog.business.whatsapp !== 'string' ||
      (catalog.business.whatsapp !== '' &&
        !/^\d{8,15}$/.test(catalog.business.whatsapp)) ||
      (catalog.business.showUsdReference !== undefined &&
        typeof catalog.business.showUsdReference !== 'boolean') ||
      (catalog.business.showUsdReference === true &&
        (!Number.isFinite(catalog.business.vesPerUsd) ||
          catalog.business.vesPerUsd <= 0)) ||
      !catalog.business.colors ||
      !/^#[0-9a-f]{6}$/i.test(catalog.business.colors.primary) ||
      !/^#[0-9a-f]{6}$/i.test(catalog.business.colors.accent) ||
      !isSafeImageSource(catalog.business.logo) ||
      !isSafeImageSource(catalog.business.banner ?? null) ||
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

function corsHeaders(origin, allowedOrigins) {
  if (!origin || !allowedOrigins.includes(origin)) return {};
  return {
    'Access-Control-Allow-Origin': origin,
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

async function githubError(response, cors = {}) {
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

async function hashTemplate(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('');
}
