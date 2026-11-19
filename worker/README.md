# Worker de publicación de carta digital

El Worker recibe el JSON de la carta digital que genera la app Flutter en
`POST /` o `POST /publish`. No requiere `businessId`, `clientSecret`,
`Authorization` ni un nombre de repositorio en el cuerpo.

El documento debe incluir `format: "synthetix_restaurant_menu"`, `version: 1`
y `menu` con arreglos `categories` y `products`. La app envía este documento
directamente como JSON.

Un `GET /` o `GET /health` devuelve el estado del servicio. El endpoint de
publicación responde con la URL de GitHub Pages:

```json
{"ok":true,"url":"https://synthetixapp17.github.io/menu-restaurante-general/menu.html"}
```

## Configuración

1. En `wrangler.toml`, configura `GITHUB_OWNER`, `APP_ORIGIN`,
   `APP_RESTAURANT_TEMPLATE_URL` y `RESTAURANT_REPOSITORY`. El repositorio es
   fijo en la configuración del Worker; el cuerpo de la petición no puede
   elegir otro repositorio.
2. `PUBLISH_RATE_LIMITER` debe permitir hasta 10 publicaciones por minuto y
   por IP. No elimines esa binding.
3. Guarda el token como secreto de Cloudflare, no en el código:

   ```powershell
   wrangler secret put GITHUB_TOKEN --config worker/wrangler.toml
   ```

   El token necesita permisos para crear/acceder al repositorio configurado,
   publicar sus archivos y habilitar GitHub Pages.
4. Despliega el Worker:

   ```powershell
   wrangler deploy --config worker/wrangler.toml
   ```

   Prueba el estado con `GET https://<nombre-del-worker>.workers.dev/health`.

## Seguridad

Este endpoint no autentica a quien publica: cualquiera que alcance la ruta
puede intentar reemplazar la carta del repositorio fijo. CORS no es
autenticación; el límite por IP solo reduce abuso. Para una publicación
protegida antes de usarlo con datos reales, añade Cloudflare Turnstile u otro
mecanismo de autenticación y envía su prueba desde la app.
