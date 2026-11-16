# Worker de publicación de tiendas

El endpoint que usa la app es:

```text
https://synthetix-pos.synthetixapp17.workers.dev
```

La app genera y guarda un `businessId` UUID y un `clientSecret` aleatorio en sus
ajustes locales. Publica `POST /` (también se acepta `POST /publish`) con JSON:

```json
{
  "businessId": "4dd7c859-9c2a-4f4f-9479-ec7ef08a6b0a",
  "clientSecret": "secreto-aleatorio-base64url-de-43-caracteres",
  "catalog": {
    "schemaVersion": 1,
    "business": {
      "id": "4dd7c859-9c2a-4f4f-9479-ec7ef08a6b0a",
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

En la primera publicación, el Worker crea un repositorio público
`tienda-{businessId}` en la cuenta configurada, publica `tienda.html` y
`productos.json`, y habilita GitHub Pages. En las siguientes publicaciones,
compara el hash SHA-256 del secreto con el guardado en Cloudflare KV y solo
entonces actualiza el catálogo. El secreto nunca se escribe en el repositorio.
La respuesta incluye la URL pública final.

## Configuración de Cloudflare

1. Crea un namespace KV:

   ```powershell
   wrangler kv namespace create STORE_CONFIGS
   ```

   Copia el ID devuelto y reemplaza `REPLACE_WITH_KV_NAMESPACE_ID` en
   `wrangler.toml`.
2. En `wrangler.toml`, configura `GITHUB_OWNER` con la cuenta personal que
   posee el token maestro, `APP_ORIGIN` con el origen del frontend y
   `APP_TEMPLATE_URL` con la URL desplegada de `web/tienda.html`.
   El Worker verifica que la plantilla pertenezca a `APP_ORIGIN`.
3. Crea un token de GitHub limitado a esa cuenta, con permisos de repositorio
   **Administration: Read and write**, **Contents: Read and write** y
   **Pages: Read and write**. El Worker solo lo recibe como secreto de
   Cloudflare:

   ```powershell
   wrangler secret put GITHUB_TOKEN --config worker/wrangler.toml
   ```
4. Despliega:

   ```powershell
   wrangler deploy --config worker/wrangler.toml
   ```

El binding `PUBLISH_RATE_LIMITER` permite hasta 10 publicaciones por minuto y
por IP. El catálogo y las imágenes que se publican son públicos. No añadas
`GITHUB_TOKEN` ni el secreto de cliente al código, a `wrangler.toml` ni al
repositorio.
