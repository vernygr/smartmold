# SmartMold EP

Herramienta de diagnóstico industrial para procesos de inyección de plástico, desarrollada para **ElectroPlast**.

Permite a técnicos y operadores navegar un árbol de decisión para diagnosticar defectos de inyección (rechupes, rebabas, piezas incompletas, etc.), registrar soluciones aplicadas y llevar un historial de incidencias por molde.

## Arquitectura

App estática de una sola página (`index.html` — HTML/CSS/JS embebidos, sin build step) que habla directo con [Supabase](https://supabase.com) (Postgres + Auth) usando el cliente `@supabase/supabase-js` desde CDN. No hay backend propio.

- **Auth**: Supabase Auth (email + contraseña). Cada usuario tiene un rol (`admin` o `tecnico`) en la tabla `profiles`; solo los admins pueden borrar registros.
- **Datos**: tablas `records`, `mold_records` y `defect_categories` en Supabase, protegidas con Row Level Security. Ver [supabase/schema.sql](supabase/schema.sql).
- **Despliegue**: sitio estático en [smartmoldep.netlify.app](https://smartmoldep.netlify.app) (Netlify sirve `index.html` tal cual, sin build).

## Configurar tu propio proyecto Supabase

1. Crea un proyecto gratis en [supabase.com](https://supabase.com).
2. En **SQL Editor**, pega y ejecuta el contenido completo de [supabase/schema.sql](supabase/schema.sql). Esto crea las tablas, las políticas de acceso (RLS) y carga los datos iniciales (3 registros demo + 78 de la base histórica "Excel Rodolfo").
3. En **Project Settings → API**, copia la **Project URL** y la **anon public key** (esta clave es segura para el cliente — la protección real la da RLS, no ocultar esta clave).
4. Abre `index.html` y reemplaza los dos placeholders al inicio del `<script>` principal:
   ```js
   const SUPABASE_URL      = "TU_SUPABASE_URL_AQUI";
   const SUPABASE_ANON_KEY = "TU_SUPABASE_ANON_KEY_AQUI";
   ```
5. Crea al menos un usuario: en Supabase → **Authentication → Users → Add user**. Se le crea automáticamente un perfil con rol `tecnico`.
6. Para darle rol de administrador (puede borrar registros), corre en el SQL Editor:
   ```sql
   update public.profiles set role = 'admin' where id = '<uuid del usuario>';
   ```

## Configurar el asistente de IA (opcional)

Cuando el árbol de diagnóstico no tiene una categoría clara para lo que describe el técnico, puede pedirle una sugerencia a un asistente de IA (Google Gemini, nivel gratuito) en vez de quedarse sin opciones.

1. Crea una API key gratis en [aistudio.google.com/apikey](https://aistudio.google.com/apikey).
2. En **SQL Editor**, corre [supabase/migrations/002_ai_assistant.sql](supabase/migrations/002_ai_assistant.sql) (agrega las columnas `origen` y `revisado` a `records`).
3. En **Edge Functions** del dashboard de Supabase, crea una función nueva llamada `diagnose-ai` y pega el contenido de [supabase/functions/diagnose-ai/index.ts](supabase/functions/diagnose-ai/index.ts).
4. En **Edge Functions → Secrets**, agrega `GEMINI_API_KEY` con la key del paso 1. (`SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` ya están disponibles automáticamente, no hay que configurarlos.)

Las sugerencias de la IA quedan guardadas en `records` marcadas como `origen = 'ia'` y `revisado = false` hasta que un admin las confirme desde la pestaña "Registros" (botón "✓ Revisado") — así el conocimiento generado por IA no se trata como confirmado hasta que un humano lo valide.

## Funcionalidades

- Diagnóstico guiado por árbol de decisión para 18 categorías de defectos comunes de inyección
- Asistente de IA como respaldo cuando ninguna opción del árbol aplica (ver arriba)
- Registro de troubleshooting (causa raíz, solución, parámetro/valor anterior/valor nuevo, material)
- Registro y búsqueda de incidencias por molde
- Estadísticas básicas (total de registros, moldes, categorías)
- Autenticación real por usuario, con control de quién puede borrar registros

## Probar localmente

No requiere build ni servidor: basta con abrir `index.html` en el navegador, o servirlo con cualquier servidor estático (por ejemplo `npx serve` si tienes Node, o la extensión Live Server de VS Code).
