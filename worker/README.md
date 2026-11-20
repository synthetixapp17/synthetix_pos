# Worker de publicación de tiendas y menú de restaurante

El mismo Worker publica ambos tipos de sitio con `POST /` o `POST /publish`.
`GET /` y `GET /health` sirven para comprobar que está activo.

- La Tienda envía `businessId`, `clientSecret` y `catalog`.
- El Menú envía `siteType: "restaurant"`, `businessId`, `clientSecret`,
  `format`, `version` y `menu` en el nivel raíz.

El Worker valida la identidad en KV, conserva solo el hash SHA-256 del secreto
y crea un repositorio público independiente por negocio: `tienda-{businessId}`
o `menu-{businessId}`. Publica `tienda.html`/`productos.json` para la Tienda y
`menu.html`/`menu.json` para el Menú. GitHub Pages se configura en la rama
predeterminada del repositorio y en la carpeta raíz.

## Configuración

1. En `wrangler.toml`, verifica `GITHUB_OWNER`, `APP_ORIGIN`,
   `APP_TEMPLATE_URL` y `APP_RESTAURANT_TEMPLATE_URL`.
2. Usa el **mismo namespace KV `STORE_CONFIGS` que ya usa la Tienda**. Copia
   su ID real en lugar de `REPLACE_WITH_KV_NAMESPACE_ID`. No crees un namespace
   nuevo para desplegar esta versión si quieres conservar las identidades ya
   registradas.
3. Configura el secreto de GitHub en Cloudflare:

   ```powershell
   wrangler secret put GITHUB_TOKEN --config worker/wrangler.toml
   ```

   El token debe poder crear repositorios públicos bajo `GITHUB_OWNER`, leer y
   escribir contenido, y administrar GitHub Pages.
4. Despliega:

   ```powershell
   wrangler deploy --config worker/wrangler.toml
   ```

5. Comprueba `GET https://<nombre-del-worker>.workers.dev/health` y publica
   desde la app. La respuesta incluye la URL del sitio correspondiente.

El límite de publicación es de 10 solicitudes por minuto y por IP. No guardes
`GITHUB_TOKEN` en el repositorio ni en la app Flutter.
