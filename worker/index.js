const MAX_BODY_BYTES = 4 * 1024 * 1024;
const MAX_TEMPLATE_BYTES = 256 * 1024;
const GITHUB_API = 'https://api.github.com';
const DEFAULT_APP_ORIGIN = 'https://synthetixapp17.github.io';
const DEFAULT_REPOSITORY = 'menu-restaurante-general';

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
        service: 'synthetix-restaurant-publisher',
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
        !env.APP_RESTAURANT_TEMPLATE_URL) {
      return json({
        error: 'El servicio no está configurado. Faltan GITHUB_TOKEN, GITHUB_OWNER, APP_ORIGIN o APP_RESTAURANT_TEMPLATE_URL.',
      }, 503, cors);
    }

    const contentLength = Number(request.headers.get('Content-Length') || 0);
    if (contentLength > MAX_BODY_BYTES) {
      return json({ error: 'El menú supera el límite de 4 MB.' }, 413, cors);
    }

    let rawBody;
    try {
      rawBody = await readLimitedBody(request);
    } catch {
      return json({ error: 'No se pudo leer la solicitud.' }, 400, cors);
    }
    if (rawBody === null) {
      return json({ error: 'El menú supera el límite de 4 MB.' }, 413, cors);
    }

    let body;
    try {
      body = JSON.parse(rawBody);
    } catch {
      return json({ error: 'El cuerpo no contiene JSON válido.' }, 400, cors);
    }

    const publication = body?.menu ?? body?.catalog ?? body;
    if (!isCatalogValid(publication)) {
      return json({
        error: 'El menú no es válido. Se requiere format, version, menu.categories y menu.products.',
      }, 400, cors);
    }

    const owner = env.GITHUB_OWNER.trim();
    if (!/^[A-Za-z0-9-]{1,39}$/.test(owner)) {
      return json({
        error: 'GITHUB_OWNER no está configurado correctamente.',
      }, 503, cors);
    }

    const repository = body?.repository ??
      env.RESTAURANT_REPOSITORY ??
      DEFAULT_REPOSITORY;
    if (typeof repository !== 'string' ||
        !/^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$/.test(repository)) {
      return json({ error: 'El nombre del repositorio no es válido.' }, 400, cors);
    }

    const githubHeaders = {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${env.GITHUB_TOKEN.trim()}`,
      'Content-Type': 'application/json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Synthetix-Restaurant-Publisher',
    };

    let repositoryInfo;
    try {
      repositoryInfo = await ensureRepository(
        owner,
        repository,
        githubHeaders,
      );
    } catch {
      return json({
        error: 'No se pudo preparar el repositorio del menú.',
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
      const template = await fetchTemplate(
        env.APP_RESTAURANT_TEMPLATE_URL,
        env.APP_ORIGIN,
      );
      if (!template.ok) {
        return json({ error: template.error }, template.status, cors);
      }

      const templateResult = await writeGithubFile({
        owner,
        repository,
        branch,
        path: 'menu.html',
        contents: template.contents,
        message: 'Publicar plantilla del menú del restaurante',
        githubHeaders,
      });
      if (templateResult instanceof Response) {
        return templateResult;
      }

      const menuBytes = new TextEncoder().encode(
        JSON.stringify(publication, null, 2),
      );
      const menuResult = await writeGithubFile({
        owner,
        repository,
        branch,
        path: 'menu.json',
        contents: menuBytes,
        message: 'Actualizar menú del restaurante',
        githubHeaders,
      });
      if (menuResult instanceof Response) {
        return menuResult;
      }

      const pagesResult = await ensurePages(
        owner,
        repository,
        branch,
        githubHeaders,
      );
      if (pagesResult instanceof Response) {
        return pagesResult;
      }
    } catch {
      return json({
        error: 'No se pudo publicar el menú en GitHub.',
      }, 502, cors);
    }

    const publicUrl =
      `https://${owner.toLowerCase()}.github.io/${repository}/menu.html`;
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

async function ensureRepository(owner, repository, githubHeaders) {
  const repositoryUrl =
    `${GITHUB_API}/repos/${encodeURIComponent(owner)}/` +
    encodeURIComponent(repository);
  const current = await fetch(repositoryUrl, {
    headers: githubHeaders,
  });
  if (current.ok) {
    return current.json();
  }
  if (current.status !== 404) {
    return githubError(current);
  }

  const created = await fetch(`${GITHUB_API}/user/repos`, {
    method: 'POST',
    headers: githubHeaders,
    body: JSON.stringify({
      name: repository,
      description: 'Carta digital pública del restaurante',
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
  return githubError(created);
}

async function ensurePages(owner, repository, branch, githubHeaders) {
  const pagesUrl =
    `${GITHUB_API}/repos/${encodeURIComponent(owner)}/` +
    `${encodeURIComponent(repository)}/pages`;
  const current = await fetch(pagesUrl, {
    headers: githubHeaders,
  });
  if (current.ok) {
    return null;
  }
  if (current.status !== 404) {
    return githubError(current);
  }

  const created = await fetch(pagesUrl, {
    method: 'POST',
    headers: githubHeaders,
    body: JSON.stringify({
      source: {
        branch,
        path: '/',
      },
    }),
  });
  if (created.ok) {
    return null;
  }
  return githubError(created);
}

async function fetchTemplate(templateUrl, appOrigin) {
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
      error: 'La plantilla debe pertenecer al origen configurado.',
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
      error: 'No se pudo cargar la plantilla del menú.',
    };
  }
  if (!response.ok) {
    return {
      ok: false,
      status: 503,
      error: 'La plantilla pública del menú no está disponible.',
    };
  }

  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length > MAX_TEMPLATE_BYTES) {
    return {
      ok: false,
      status: 503,
      error: 'La plantilla supera el tamaño permitido.',
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
    return githubError(current);
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
    return githubError(update);
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

async function githubError(response) {
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
  return json({ error: message }, response.status === 409 ? 409 : 502);
}

function toBase64(bytes) {
  let binary = '';
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}
