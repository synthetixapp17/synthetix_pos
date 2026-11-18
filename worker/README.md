# Worker de publicación de tiendas

El endpoint que usa la app es:

```text
https://synthetix-pos.synthetixapp17.workers.dev/
```

La app publica el nombre de la tienda como `businessId` en `POST /` (también se
acepta `POST /publish`). El catálogo debe repetir el nombre en
`catalog.business.id`:

```json
{
  "businessId": "Tienda de Luis",
  "catalog": {
    "schemaVersion": 1,
    "business": {
      "id": "Tienda de Luis",
      "name": "Tienda de Luis",
      "whatsapp": "",
      "logo": null,
      "banner": null,
      "showUsdReference": false,
      "vesPerUsd": null,
      "colors": {
        "primary": "#008c95",
        "accent": "#ffb300"
      }
    },
    "products": []
  }
}
```

La app permite elegir colores, cargar un logo y un banner (cada imagen debe
pesar como máximo 1 MB) y publicar precios en USD con referencia en bolívares.
Al activar la referencia, `vesPerUsd` debe ser una tasa positiva guardada en la
calculadora de tasas de la app; el catálogo normaliza los precios del inventario
a USD antes de incluir la referencia.

El Worker convierte el nombre a un slug seguro y crea un repositorio público
`tienda-{slug}` en `GITHUB_OWNER`. Publica `tienda.html` y `productos.json`,
habilita GitHub Pages y devuelve la URL pública. Cloudflare KV conserva el
repositorio asociado al slug para futuras actualizaciones. En cada publicación,
compara la plantilla configurada con la versión del repositorio y la actualiza
si cambió, de modo que las tiendas ya creadas reciban los cambios del diseño.

Los pedidos acordados por WhatsApp se registran y administran localmente en la
app. Al marcar uno como entregado, se registra una venta en el historial del
POS y se descuenta el inventario; los pedidos no se sincronizan con el Worker.

Esta modalidad no autentica al dueño de la tienda: cualquier persona puede
publicar o sobrescribir el catálogo asociado al mismo nombre. El limitador
reduce ráfagas por IP, pero el nombre no es una credencial ni demuestra
propiedad. El `GITHUB_TOKEN` sigue siendo necesario y debe permanecer como
secreto del Worker; nunca se envía a Flutter.

## Configuración de Cloudflare

1. Crea un namespace KV:

   ```powershell
   wrangler kv namespace create STORE_CONFIGS
   ```

   Copia el ID devuelto y reemplaza `REPLACE_WITH_KV_NAMESPACE_ID` en
   `wrangler.toml`.
2. En `wrangler.toml`, configura `GITHUB_OWNER` con la cuenta propietaria del
   token, `APP_ORIGIN` con el origen del frontend y
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
`GITHUB_TOKEN` al código, a `wrangler.toml` ni al repositorio.
