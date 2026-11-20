const MAX_BODY_BYTES = 4 * 1024 * 1024;
const MAX_TEMPLATE_BYTES = 256 * 1024;
const GITHUB_API = 'https://api.github.com';
const DEFAULT_APP_ORIGIN = 'https://synthetixapp17.github.io';
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin');
    const allowedOrigins = [DEFAULT_APP_ORIGIN, env.APP_ORIGIN].filter(Boolean);
    const cors = corsHeaders(origin, allowedOrigins);

    if (request.method === 'GET' &&
        (url.pathname === '/' || url.pathname === '/health')) {
      return json({
        status: 'ok',
        service: 'synthetix-store-and-restaurant-publisher',
      }, 200, cors);
    }

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          ...cors,
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    if (request.method !== 'POST' || !['/', '/publish'].includes(url.pathname)) {
      return json({ error: 'Ruta no encontrada.' }, 404, cors);
    }

    if (origin && !allowedOrigins.includes(origin)) {
      return json({ error: 'Origen no autorizado.' }, 403, cors);
    }

    if (!env.GITHUB_TOKEN ||
        !env.GITHUB_OWNER ||
        !env.APP_ORIGIN ||
        !env.APP_TEMPLATE_URL ||
        !env.APP_RESTAURANT_TEMPLATE_URL ||
        !env.STORE_CONFIGS ||
        !env.PUBLISH_RATE_LIMITER) {
      return json({
        error: 'El servicio no está configurado. Revisa GITHUB_TOKEN, GITHUB_OWNER, APP_ORIGIN, las plantillas, STORE_CONFIGS y PUBLISH_RATE_LIMITER.',
      }, 503, cors);
    }

    let rateLimit;
    try {
      rateLimit = await env.PUBLISH_RATE_LIMITER.limit({
        key: request.headers.get('CF-Connecting-IP') || 'unknown',
      });
    } catch {
      return json({
        error: 'No se pudo comprobar el límite de publicaciones.',
      }, 503, cors);
    }
    if (!rateLimit.success) {
      return json({
        error: 'Se alcanzó el límite de publicaciones. Inténtalo más tarde.',
      }, 429, cors);
    }

    const contentLength = Number(request.headers.get('Content-Length') || 0);
    if (contentLength > MAX_BODY_BYTES) {
      return json({ error: 'La publicación supera el límite de 4 MB.' }, 413, cors);
    }

    let rawBody;
    try {
      rawBody = await readLimitedBody(request);
    } catch {
      return json({ error: 'No se pudo leer la solicitud.' }, 400, cors);
    }
    if (rawBody === null) {
      return json({ error: 'La publicación supera el límite de 4 MB.' }, 413, cors);
    }

    let body;
    try {
      body = JSON.parse(rawBody);
    } catch {
      return json({ error: 'El cuerpo no contiene JSON válido.' }, 400, cors);
    }

    const siteType = body?.siteType ?? 'store';
    if (siteType !== 'store' && siteType !== 'restaurant') {
      return json({
        error: 'El tipo de publicación no es válido.',
      }, 400, cors);
    }

    const isRestaurant = siteType === 'restaurant';
    const siteLabel = isRestaurant ? 'el menú del restaurante' : 'la tienda';
    const templateUrl = isRestaurant
      ? env.APP_RESTAURANT_TEMPLATE_URL
      : env.APP_TEMPLATE_URL;
    const businessId = body?.businessId;
    const clientSecret = body?.clientSecret;
    if (typeof businessId !== 'string' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(businessId) ||
        typeof clientSecret !== 'string' ||
        !/^[A-Za-z0-9_-]{43}$/.test(clientSecret)) {
      return json({ error: 'La identidad de la publicación no es válida.' }, 400, cors);
    }

    const normalizedBusinessId = businessId.toLowerCase();
    const publication = isRestaurant
      ? (body.menu ?? body.catalog)
      : body.catalog;
    const validPublication = isRestaurant
      ? isCatalogValid(publication)
      : isStoreCatalogValid(publication, normalizedBusinessId);
    if (!validPublication) {
      return json({
        error: `La publicación de ${siteLabel} no es válida o no corresponde a esta identidad.`,
      }, 400, cors);
    }

    let clientSecretHash;
    try {
      clientSecretHash = await hashSecret(clientSecret);
    } catch {
      return json({
        error: 'No se pudo validar la identidad de la publicación.',
      }, 500, cors);
    }

    const configKey = `${siteType}:${normalizedBusinessId}`;
    let storeConfig;
    let isFirstRequest = false;
    try {
      const stored = await env.STORE_CONFIGS.get(configKey);
      if (stored) {
        storeConfig = JSON.parse(stored);
        if (!constantTimeEqual(storeConfig.clientSecretHash, clientSecretHash)) {
          return json({
            error: isRestaurant
              ? 'La clave secreta no corresponde a este menú.'
              : 'La clave secreta no corresponde a esta tienda.',
          }, 401, cors);
        }
      } else {
        isFirstRequest = true;
        storeConfig = {
          siteType,
          businessId: normalizedBusinessId,
          clientSecretHash,
          repository: `${isRestaurant ? 'menu' : 'tienda'}-${normalizedBusinessId}`,
        };
      }
    } catch {
      return json({
        error: 'No se pudo consultar la identidad de la publicación.',
      }, 503, cors);
    }

    const owner = env.GITHUB_OWNER.trim();
    if (!/^[A-Za-z0-9-]{1,39}$/.test(owner)) {
      return json({
        error: 'GITHUB_OWNER no está configurado correctamente.',
      }, 503, cors);
    }

    const githubHeaders = {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${env.GITHUB_TOKEN.trim()}`,
      'Content-Type': 'application/json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Synthetix-Publisher',
    };

    let repositoryInfo;
    try {
      repositoryInfo = await ensureRepository(
        owner,
        storeConfig.repository,
        isRestaurant ? 'Carta digital del restaurante' : 'Tienda virtual',
        githubHeaders,
        isFirstRequest,
        cors,
      );
    } catch {
      return json({
        error: `No se pudo preparar el repositorio para ${siteLabel}.`,
      }, 502, cors);
    }
    if (repositoryInfo instanceof Response) {
      return repositoryInfo;
    }

    const branch = repositoryInfo.default_branch;
    if (typeof branch !== 'string' || !branch) {
      return json({
        error: 'El repositorio no tiene una rama principal válida.',
      }, 502, cors);
    }

    try {
      if (isFirstRequest) {
        await env.STORE_CONFIGS.put(configKey, JSON.stringify(storeConfig));
      }

      const template = await fetchTemplate(
        templateUrl,
        env.APP_ORIGIN,
        isRestaurant ? 'del menú del restaurante' : 'de la tienda',
      );
      if (!template.ok) {
        return json({ error: template.error }, template.status, cors);
      }

      const templateHash = await hashTemplate(template.contents);
      if (storeConfig.templateHash !== templateHash) {
        const templateResult = await writeGithubFile({
          owner,
          repository: storeConfig.repository,
          branch,
          path: isRestaurant ? 'menu.html' : 'tienda.html',
          contents: template.contents,
          message: `Configurar ${siteLabel} ${normalizedBusinessId}`,
          githubHeaders,
          cors,
        });
        if (templateResult instanceof Response) {
          return templateResult;
        }
        storeConfig.templateHash = templateHash;
      }

      const publicationBytes = new TextEncoder().encode(
        JSON.stringify(publication, null, 2),
      );
      const publicationResult = await writeGithubFile({
        owner,
        repository: storeConfig.repository,
        branch,
        path: isRestaurant ? 'menu.json' : 'productos.json',
        contents: publicationBytes,
        message: `Actualizar ${siteLabel} ${normalizedBusinessId}`,
        githubHeaders,
        cors,
      });
      if (publicationResult instanceof Response) {
        return publicationResult;
      }

      const pagesResult = await ensurePages(
        owner,
        storeConfig.repository,
        branch,
        githubHeaders,
        cors,
      );
      if (pagesResult instanceof Response) {
        return pagesResult;
      }

      await env.STORE_CONFIGS.put(configKey, JSON.stringify(storeConfig));
    } catch {
      return json({
        error: `No se pudo publicar ${siteLabel}.`,
      }, 502, cors);
    }

    const page = isRestaurant ? 'menu.html' : 'tienda.html';
    const publicUrl =
      `https://${owner.toLowerCase()}.github.io/${storeConfig.repository}/${page}` +
      `?negocio=${encodeURIComponent(normalizedBusinessId)}`;
    return json({ ok: true, url: publicUrl }, 200, cors);
  },
};

function isCatalogValid(catalog) {
  if (!catalog ||
      typeof catalog !== 'object' ||
      catalog.format !== 'synthetix_restaurant_menu' ||
      catalog.version !== 1 ||
      !catalog.menu ||
      typeof catalog.menu !== 'object') {
    return false;
  }

  const categories = catalog.menu.categories;
  const products = catalog.menu.products;
  if (!Array.isArray(categories) ||
      categories.length > 100 ||
      !Array.isArray(products) ||
      products.length > 2000) {
    return false;
  }

  const categoryIds = new Set();
  for (const category of categories) {
    if (!category ||
        typeof category !== 'object' ||
        typeof category.id !== 'string' ||
        !category.id.trim() ||
        typeof category.name !== 'string' ||
        !category.name.trim() ||
        categoryIds.has(category.id)) {
      return false;
    }
    categoryIds.add(category.id);
  }

  const productIds = new Set();
  for (const product of products) {
    if (!product ||
        typeof product !== 'object' ||
        typeof product.id !== 'string' ||
        !product.id.trim() ||
        productIds.has(product.id) ||
        typeof product.categoryId !== 'string' ||
        !categoryIds.has(product.categoryId) ||
        typeof product.name !== 'string' ||
        !product.name.trim() ||
        typeof product.price !== 'number' ||
        !Number.isFinite(product.price) ||
        product.price < 0 ||
        typeof product.currencyCode !== 'string' ||
        !/^[A-Z]{3}$/.test(product.currencyCode) ||
        typeof product.isAvailable !== 'boolean') {
      return false;
    }
    productIds.add(product.id);
  }

  return true;
}

function isStoreCatalogValid(catalog, businessId) {
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
      !catalog.business.colors ||
      !/^#[0-9a-f]{6}$/i.test(catalog.business.colors.primary) ||
      !/^#[0-9a-f]{6}$/i.test(catalog.business.colors.accent) ||
      !isSafeImageSource(catalog.business.logo) ||
      !isSafeImageSource(catalog.business.banner) ||
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
    Number.isFinite(product.price) &&
    product.price >= 0 &&
    Number.isFinite(product.stock) &&
    typeof product.currencyCode === 'string' &&
    /^[A-Z]{3}$/.test(product.currencyCode) &&
    isSafeImageSource(product.image));
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

async function hashSecret(secret) {
  const bytes = new TextEncoder().encode(secret);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0')).join('');
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

async function ensureRepository(
  owner,
  repository,
  description,
  githubHeaders,
  isFirstRequest,
  cors,
) {
  const repositoryUrl =
    `${GITHUB_API}/repos/${encodeURIComponent(owner)}/` +
    encodeURIComponent(repository);
  const current = await fetch(repositoryUrl, {
    headers: githubHeaders,
  });
  if (current.ok) {
    if (isFirstRequest) {
      return json(
        { error: 'El nombre de publicación ya está en uso.' },
        409,
        cors,
      );
    }
    return current.json();
  }
  if (current.status !== 404) {
    return githubError(current, cors);
  }

  const created = await fetch(`${GITHUB_API}/user/repos`, {
    method: 'POST',
    headers: githubHeaders,
    body: JSON.stringify({
      name: repository,
      description,
      private: false,
      auto_init: true,
      has_issues: false,
      has_projects: false,
      has_wiki: false,
    }),
  });
  if (created.ok) {
    return created.json();
  }
  if (created.status === 422) {
    const retry = await fetch(repositoryUrl, { headers: githubHeaders });
    if (retry.ok) {
      return retry.json();
    }
  }
  return githubError(created, cors);
}

async function ensurePages(owner, repository, branch, githubHeaders, cors) {
  const pagesUrl =
    `${GITHUB_API}/repos/${encodeURIComponent(owner)}/` +
    `${encodeURIComponent(repository)}/pages`;
  const current = await fetch(pagesUrl, {
    headers: githubHeaders,
  });
  if (current.ok) {
    const pages = await current.json();
    if (pages.source?.branch === branch && pages.source?.path === '/') {
      return null;
    }

    const updated = await fetch(pagesUrl, {
      method: 'PUT',
      headers: githubHeaders,
      body: JSON.stringify({
        build_type: 'legacy',
        source: {
          branch,
          path: '/',
        },
      }),
    });
    if (updated.ok) {
      return null;
    }
    return githubError(updated, cors);
  }
  if (current.status !== 404) {
    return githubError(current, cors);
  }

  const created = await fetch(pagesUrl, {
    method: 'POST',
    headers: githubHeaders,
    body: JSON.stringify({
      build_type: 'legacy',
      source: {
        branch,
        path: '/',
      },
    }),
  });
  if (created.ok) {
    return null;
  }
  return githubError(created, cors);
}

async function fetchTemplate(templateUrl, appOrigin, siteLabel) {
  let template;
  try {
    template = new URL(templateUrl);
  } catch {
    return {
      ok: false,
      status: 503,
      error: 'La URL de la plantilla no es válida.',
    };
  }

  if (template.protocol !== 'https:' ||
      template.origin !== appOrigin) {
    return {
      ok: false,
      status: 503,
      error: `La plantilla ${siteLabel} debe pertenecer al origen configurado.`,
    };
  }

  let response;
  try {
    response = await fetch(template, {
      headers: { Accept: 'text/html' },
    });
  } catch {
    return {
      ok: false,
      status: 503,
      error: `No se pudo cargar la plantilla ${siteLabel}.`,
    };
  }
  if (!response.ok) {
    return {
      ok: false,
      status: 503,
      error: `La plantilla pública ${siteLabel} no está disponible.`,
    };
  }

  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length > MAX_TEMPLATE_BYTES) {
    return {
      ok: false,
      status: 503,
      error: `La plantilla ${siteLabel} supera el tamaño permitido.`,
    };
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
    `${GITHUB_API}/repos/${encodeURIComponent(owner)}/` +
    `${encodeURIComponent(repository)}/contents/${encodeURIComponent(path)}`;

  const current = await fetch(
    `${fileUrl}?ref=${encodeURIComponent(branch)}`,
    { headers: githubHeaders },
  );
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
  if (!update.ok) {
    return githubError(update, cors);
  }
  return null;
}

async function readLimitedBody(request) {
  const reader = request.body?.getReader();
  if (!reader) {
    return '';
  }

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

function corsHeaders(origin, allowedOrigins) {
  if (!origin || !allowedOrigins.includes(origin)) {
    return {};
  }
  return {
    'Access-Control-Allow-Origin': origin,
    'Vary': 'Origin',
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

async function githubError(response, cors) {
  let detail = '';
  try {
    const body = await response.json();
    if (typeof body.message === 'string') {
      detail = body.message;
    }
  } catch {
    detail = '';
  }
  const message = `GitHub rechazó la publicación (HTTP ${response.status})` +
    (detail ? `: ${detail}` : '.');
  return json(
    { error: message },
    response.status === 409 ? 409 : 502,
    cors,
  );
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
