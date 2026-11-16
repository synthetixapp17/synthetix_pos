# Worker `synthetix-pos`

El endpoint que usa Flutter es:

```text
https://synthetix-pos.synthetixapp17.workers.dev
```

Acepta `POST /` (también `POST /publish`) con `Authorization: Bearer <clave
del cliente>` y este JSON:

```json
{
  "owner": "cliente",
  "repository": "tienda",
  "catalog": {
    "schemaVersion": 1,
    "business": {
      "id": "cliente/tienda",
      "name": "Mi tienda",
      "whatsapp": "584120000000",
      "colors": {
        "primary": "#008c95",
        "accent": "#ffb300"
      }
    },
    "products": []
  }
}
```

`CLIENT_API_KEYS` es un secreto JSON que asigna una clave diferente a cada
repositorio permitido. Las claves del mapa usan `owner/repository` en
minúsculas, por ejemplo:

```json
{"cliente/tienda":"clave-aleatoria-larga"}
```

`GITHUB_TOKEN` acepta un Fine-grained Personal Access Token con acceso solo a
los repositorios listados en `CLIENT_API_KEYS` y permiso **Contents: Read and
write**. El Worker no acepta repositorios que no tengan una clave registrada.
Si todos los repositorios pertenecen al mismo propietario de recursos, un
token puede cubrirlos. Para repositorios de distintos propietarios, configura
`GITHUB_TOKEN` como un mapa JSON de `owner/repository` a tokens independientes,
cada uno limitado a un solo repositorio:

```json
{"cliente-a/tienda":"github-token-a","cliente-b/tienda":"github-token-b"}
```

Los tokens Fine-grained están ligados a un propietario; no uses un PAT con
permisos amplios para resolver esta limitación.

## Secretos y variables de Cloudflare

En **Workers & Pages → synthetix-pos → Settings → Variables and Secrets**:

- Secret `GITHUB_TOKEN`: Fine-grained PAT limitado a los repositorios de los
  clientes.
- Secret `CLIENT_API_KEYS`: mapa JSON de `owner/repository` a una clave única.
- Variable `GITHUB_BRANCH`: `main`.
- Variable `APP_ORIGIN`: origen exacto de la app, actualmente
  `https://synthetixapp17.github.io`.

El Worker crea o actualiza `productos.json` en la raíz y rama configurada.
Cada repositorio debe existir, ser público y tener GitHub Pages habilitado desde
`main` y la raíz. Copia `web/tienda.html` a la raíz del repo como
`tienda.html`. El catálogo, imágenes, teléfono y marca publicados son públicos.

Para desplegar desde la raíz del proyecto con Wrangler:

```powershell
wrangler deploy --config worker/wrangler.toml
wrangler secret put GITHUB_TOKEN --config worker/wrangler.toml
wrangler secret put CLIENT_API_KEYS --config worker/wrangler.toml
```

También se puede pegar el contenido de `worker/index.js` directamente en
**Edit code** en el panel de Cloudflare; configura las mismas variables y
secretos en el panel.
