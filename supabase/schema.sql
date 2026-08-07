-- ══════════════════════════════════════════════════════════
-- SmartMold EP — esquema Supabase
-- Ejecutar una sola vez en: Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════

-- ── PROFILES (rol de cada usuario autenticado) ──────────────
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role         text not null default 'tecnico' check (role in ('admin', 'tecnico')),
  created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

-- Crea automáticamente un perfil "tecnico" cuando alguien se registra.
-- Para dar acceso de admin: en el SQL Editor,
--   update public.profiles set role = 'admin' where id = '<uuid del usuario>';
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)));
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ── DEFECT_CATEGORIES (fuente única para el árbol de diagnóstico Y el formulario) ──
create table if not exists public.defect_categories (
  id         text primary key,
  label      text not null,
  icon       text not null,
  hint       text not null,
  sort_order int not null
);

alter table public.defect_categories enable row level security;

create policy "defect_categories_select_all"
  on public.defect_categories for select
  using (true);

insert into public.defect_categories (id, label, icon, hint, sort_order) values
  ('rechupe',         'Rechupe / Hundimiento',         '🕳️', 'Hoyos o hundimientos en superficie',              1),
  ('rebaba',          'Rebaba / Flash',                 '✂️', 'Material extra en bordes',                        2),
  ('vacio',           'Vacío / Pieza Incompleta',        '📉', 'Pieza incompleta o sin llenar',                   3),
  ('marcas_flujo',    'Marcas de Flujo',                 '〰️', 'Líneas, ondas o rayas plateadas',                 4),
  ('burbujas',        'Burbujas / Vacíos',               '💨', 'Ampollas o huecos internos',                      5),
  ('deformacion',     'Deformación / Warpage',           '📐', 'Pieza torcida, curvada o encogida',               6),
  ('quemado',         'Quemado / Degradación',           '🔥', 'Manchas oscuras o material degradado',            7),
  ('pegado',          'Pegado en Molde',                 '🪤', 'La pieza no desmolda bien',                       8),
  ('lineas_union',    'Líneas de Unión',                 '⚡', 'Línea visible donde flujos se unen',              9),
  ('manchas_color',   'Manchas de Color',                '🎨', 'Rayas o manchas de color incorrecto',            10),
  ('hilos_plateados', 'Hilos Plateados (Splay)',         '💦', 'Rayas plateadas por humedad en material',        11),
  ('puntos_negros',   'Puntos Negros',                   '⚫', 'Partículas carbonizadas en la pieza',            12),
  ('fractura',        'Fractura / Fragilidad',           '💥', 'Pieza se rompe o es muy frágil',                 13),
  ('hilos_stringing', 'Hilos / Stringing',                '🧵', 'Filamentos de material al abrir el molde',       14),
  ('baja_densidad',   'Baja Densidad / Porosidad',       '🧽', 'Pieza esponjosa o más liviana',                  15),
  ('contaminacion',   'Contaminación del Material',      '🔵', 'Material extraño o inclusiones en la pieza',     16),
  ('inestabilidad',   'Inestabilidad Dimensional',       '📊', 'Dimensiones variables o fuera de tolerancia',    17),
  ('opacidad',        'Opacidad / Brillo Inconsistente', '🔅', 'Superficie opaca o brillo irregular',            18)
on conflict (id) do nothing;

-- ── RECORDS (troubleshooting general) ───────────────────────
create table if not exists public.records (
  id             text primary key,
  fecha          date,
  categoria      text not null,
  severidad      text not null check (severidad in ('alta', 'media', 'baja')),
  sintoma        text not null,
  causa_raiz     text not null,
  solucion       text not null,
  parametro      text not null default '',
  valor_anterior text not null default '',
  valor_nuevo    text not null default '',
  material       text not null default '',
  tecnico        text not null default '',
  created_by     uuid references public.profiles(id),
  created_at     timestamptz not null default now()
);

-- Nota: "categoria" es texto libre (no FK a defect_categories) a propósito.
-- Los 78 registros históricos del Excel de Rodolfo usan una taxonomía de
-- categorías ligeramente distinta a las 18 canónicas del árbol de
-- diagnóstico (p.ej. "Trampas de Aire", "Fractura de Pieza"); forzar un
-- remapeo exacto perdería información histórica. Los registros NUEVOS
-- creados desde el formulario sí usan las 18 categorías canónicas.

alter table public.records enable row level security;

create policy "records_select_authenticated"
  on public.records for select
  using (auth.uid() is not null);

create policy "records_insert_authenticated"
  on public.records for insert
  with check (auth.uid() is not null);

create policy "records_delete_admin"
  on public.records for delete
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

create policy "records_update_admin"
  on public.records for update
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ── MOLD_RECORDS (problemas por molde) ──────────────────────
create table if not exists public.mold_records (
  id           uuid primary key default gen_random_uuid(),
  id_molde     text not null,
  fecha        date,
  problema     text not null,
  diagnostico  text not null default '',
  accion       text not null default '',
  estado       text not null default 'abierto' check (estado in ('abierto', 'en_proceso', 'resuelto')),
  severidad    text not null default 'media' check (severidad in ('alta', 'media', 'baja')),
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);

alter table public.mold_records enable row level security;

create policy "mold_records_select_authenticated"
  on public.mold_records for select
  using (auth.uid() is not null);

create policy "mold_records_insert_authenticated"
  on public.mold_records for insert
  with check (auth.uid() is not null);

create policy "mold_records_delete_admin"
  on public.mold_records for delete
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

create policy "mold_records_update_admin"
  on public.mold_records for update
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ══════════════════════════════════════════════════════════
-- SEED — datos demo + "Base de datos Excel Rodolfo" (78 registros)
-- ══════════════════════════════════════════════════════════

insert into public.records (id, fecha, categoria, severidad, sintoma, causa_raiz, solucion, parametro, valor_anterior, valor_nuevo, material, tecnico) values
  ('TS-001', '2025-01-10'::date, 'Rechupe / Hundimiento', 'alta', 'Hundimiento profundo en nervio central', 'Presión de mantenimiento insuficiente', 'Aumentar presión de 600 a 720 bar y tiempo a 7 seg', 'Presión mantenimiento', '600 bar', '720 bar', 'PP', 'Carlos M.'),
  ('TS-002', '2025-01-12'::date, 'Rebabas / Flash', 'media', 'Flash en línea de partición lado conductor', 'Fuerza de cierre insuficiente', 'Fuerza de cierre de 800 a 950 kN. Verificar paralelismo.', 'Fuerza de cierre', '800 kN', '950 kN', 'ABS', 'Luis R.'),
  ('TS-003', '2025-01-15'::date, 'Vacío / Pieza Incompleta', 'alta', 'Pieza incompleta o sin llenar en extremo distal', 'Temperatura zona 3 fuera de rango y velocidad baja', 'Temp Z3: 210→225°C. Velocidad: 45→70 mm/s', 'Temp Z3 / Velocidad', '210°C / 45mm/s', '225°C / 70mm/s', 'PA66', 'Ana G.')
on conflict (id) do nothing;

-- Los 78 registros de "Base de datos — Excel Rodolfo" van a continuación.
﻿INSERT INTO public.records (id, fecha, categoria, severidad, sintoma, causa_raiz, solucion, parametro, valor_anterior, valor_nuevo, material, tecnico) VALUES
  ('TSE-01A', '2025-01-01'::date, 'Rechupe / Hundimiento', 'media', 'Rechupe (Sink marks)', 'A. Presión de compactación insuficiente', 'Aumentar la presión de empaque dentro del rango seguro del molde | Aumentar el tiempo de empaque para compensar contracción | Implementar un perfil de compactación escalonado en lugar de un valor fijo', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-01B', '2025-01-01'::date, 'Rechupe / Hundimiento', 'media', 'Rechupe (Sink marks)', 'B. Tiempo de compactación muy corto', 'Aumentar el tiempo de empaque hasta que se selle el gate | Ajustar el enfriamiento para un empaque más largo sin alargar ciclo total', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-01C', '2025-01-01'::date, 'Rechupe / Hundimiento', 'media', 'Rechupe (Sink marks)', 'C. Temperatura de molde demasiado alta', 'Reducir la temperatura del molde | Aumentar el caudal de agua en circuitos de enfriamiento', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-02A', '2025-01-01'::date, 'Marcas de Flujo', 'media', 'Marcas de flujo (Flow lines)', 'A. Baja velocidad de inyección', 'Aumentar la velocidad de inyección para llenar más rápido la pieza | Ajustar el perfil de velocidad para mantener un flujo constante', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-02B', '2025-01-01'::date, 'Marcas de Flujo', 'media', 'Marcas de flujo (Flow lines)', 'B. Temperatura de masa muy baja', 'Revisar las resistencias del cañón | Incrementar la temperatura del cañón y la boquilla | Reducir la velocidad del tornillo para mejor fusión del material', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-02C', '2025-01-01'::date, 'Marcas de Flujo', 'media', 'Marcas de flujo (Flow lines)', 'C. Presión de inyección insuficiente', 'Incrementar la presión de inyección para compactar mejor el material | Aumentar la presión de empaque para reducir líneas visibles | Revisar tiempo de empaque para evitar pérdida de compactación', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-02D', '2025-01-01'::date, 'Marcas de Flujo', 'media', 'Marcas de flujo (Flow lines)', 'D. Humedad en el material', 'Verificar el funcionamiento del secador y los filtros | Darle el secado apropiado al material (tiempo/temperatura adecuados)', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-03A', '2025-01-01'::date, 'Vacío / Pieza Incompleta', 'alta', 'Pieza corta / vacías', 'A. Temperatura de fusión baja', 'Aumentar las temperaturas en las zonas del cañón | Subir la temperatura de la boquilla para evitar solidificación prematura | Aumentar las rpm del tornillo | Asegurar que la temperatura del molde no sea baja', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-03B', '2025-01-01'::date, 'Vacío / Pieza Incompleta', 'alta', 'Pieza corta / vacías', 'B. Presión de inyección insuficiente', 'Incrementar la presión de inyección para mejorar el llenado | Mejorar el tiempo de inyección para asegurar que la cavidad llene bien', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-03C', '2025-01-01'::date, 'Vacío / Pieza Incompleta', 'alta', 'Pieza corta / vacías', 'C. Velocidad de inyección baja', 'Aumentar la velocidad de inyección | Verificar que los perfiles de velocidad sean los adecuados | Ajustar la transferencia para que no cambie antes de tiempo', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-03D', '2025-01-01'::date, 'Vacío / Pieza Incompleta', 'alta', 'Pieza corta / vacías', 'D. Material mal seco o con humedad', 'Asegurar que el secador funcione correctamente | Mejorar el secado del material (revisar ficha técnica) | Evitar que el material permanezca mucho tiempo en la tolva', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-03E', '2025-01-01'::date, 'Vacío / Pieza Incompleta', 'alta', 'Pieza corta / vacías', 'E. Ventilación deficiente del molde', 'Mantener limpias y sin obstrucciones las líneas de venteos | Ajustar parámetros de inyección para evitar atrapamientos de aire', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-04A', '2025-01-01'::date, 'Rebabas / Flash', 'alta', 'Rebabas (Flash)', 'A. Presión de inyección muy alta', 'Reducir la presión de inyección | Ajustar el tiempo de inyección para evitar el sobrellenado | Revisar que el punto de transferencia esté bien calibrado', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-04B', '2025-01-01'::date, 'Rebabas / Flash', 'alta', 'Rebabas (Flash)', 'B. Temperatura de fusión muy alta', 'Disminuir la temperatura del cilindro (zonas de plastificación) | Reducir la temperatura de la boquilla | Ajustar las rpm del tornillo | Evitar el tiempo de residencia del material en el cañón', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-04C', '2025-01-01'::date, 'Rebabas / Flash', 'alta', 'Rebabas (Flash)', 'C. Ventilación deficiente', 'Limpiar correctamente los venteos periódicamente | Pulir las superficies de cierre para un ajuste más hermético', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-04D', '2025-01-01'::date, 'Rebabas / Flash', 'alta', 'Rebabas (Flash)', 'D. Fuerza de cierre insuficiente', 'Aumentar la fuerza de cierre en la inyectora | Verificar que el sistema hidráulico de la máquina funcione correctamente', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-04E', '2025-01-01'::date, 'Rebabas / Flash', 'alta', 'Rebabas (Flash)', 'E. Molde desgastado o dañado', 'Revisar que los filos en las cavidades no estén golpeados o desgastados', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-05A', '2025-01-01'::date, 'Quemado / Degradación', 'alta', 'Quemaduras (Burn marks)', 'A. Atrapamiento de aire', 'Limpiar correctamente los canales de venteo en el molde | Pulir las zonas de cierre para la salida controlada del aire | Disminuir la velocidad de inyección para evitar atrapamientos de aire', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-05B', '2025-01-01'::date, 'Quemado / Degradación', 'alta', 'Quemaduras (Burn marks)', 'B. Temperatura del material muy elevada', 'Bajar la temperatura del cilindro en las zonas de plastificación | Reducir la temperatura de la boquilla | Disminuir el tiempo de residencia del material en el cilindro', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-05C', '2025-01-01'::date, 'Quemado / Degradación', 'alta', 'Quemaduras (Burn marks)', 'C. Velocidad de inyección muy alta', 'Reducir la velocidad de inyección en la primera fase | Aplicar un llenado en etapas (velocidad baja al inicio, mayor al final) | Ajustar la transferencia para evitar compresión excesiva del aire', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-06A', '2025-01-01'::date, 'Burbujas / Vacíos', 'media', 'Burbujas de aire / vacíos (Air bubbles / Voids)', 'A. Aire atrapado en cavidades', 'Limpiar correctamente los canales de venteo en el molde | Pulir las zonas de cierre para la salida controlada del aire | Disminuir la velocidad de inyección para evitar atrapamientos de aire', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-06B', '2025-01-01'::date, 'Burbujas / Vacíos', 'media', 'Burbujas de aire / vacíos (Air bubbles / Voids)', 'B. Temperatura de fusión muy baja (flujo deficiente)', 'Aumentar la temperatura del cilindro en las zonas de plastificación | Elevar la temperatura de la boquilla para mejorar el llenado | Verificar que el tiempo de plastificación sea suficiente para fundir homogéneamente', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-06C', '2025-01-01'::date, 'Burbujas / Vacíos', 'media', 'Burbujas de aire / vacíos (Air bubbles / Voids)', 'C. Presión de inyección o empaque insuficiente', 'Aumentar presión de sostenimiento | Optimizar perfil de inyección (llenado + empaque) | Extender el tiempo de empaque', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-07A', '2025-01-01'::date, 'Deformación / Warpage', 'media', 'Alabeo / Deformación (Warpage)', 'A. Parámetros de inyección inadecuados', 'Aumentar temperatura del material para mejorar la homogeneidad del llenado | Reducir la presión de inyección y ajustar el tiempo de compactación | Bajar la velocidad de inyección para evitar tensiones internas', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-07B', '2025-01-01'::date, 'Deformación / Warpage', 'media', 'Alabeo / Deformación (Warpage)', 'B. Expulsión incorrecta o temprana de la pieza', 'Revisar y ajustar el sistema de expulsión para que la pieza salga uniforme | Incrementar el tiempo de enfriamiento antes de la expulsión', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-07C', '2025-01-01'::date, 'Deformación / Warpage', 'media', 'Alabeo / Deformación (Warpage)', 'C. Enfriamiento desigual en el molde', 'Reducir la temperatura del molde | Ajustar los tiempos de enfriamiento para que la pieza salga estabilizada', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-08A', '2025-01-01'::date, 'Manchas de Color', 'media', 'Manchas de color (Color streaks)', 'A. Contaminación del material', 'Revisar y limpiar tolvas y silos antes de cambiar de material | Purgar bien el cañón con material exclusivo para purgas', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-08B', '2025-01-01'::date, 'Manchas de Color', 'media', 'Manchas de color (Color streaks)', 'B. Colorante mal dispersado', 'Ajustar la velocidad de plastificación y temperatura del tornillo para lograr uniformidad | Revisar y ajustar el dosificador del colorante', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-08C', '2025-01-01'::date, 'Manchas de Color', 'media', 'Manchas de color (Color streaks)', 'C. Residuos en la máquina', 'Realizar limpieza completa del tornillo | Usar ciclos de purga con material exclusivo para ese fin', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-08D', '2025-01-01'::date, 'Manchas de Color', 'media', 'Manchas de color (Color streaks)', 'D. Temperaturas de proceso inadecuadas', 'Revisar perfiles de temperatura a lo largo del cilindro | Ajustar temperatura de fusión según las recomendaciones del fabricante | Controlar temperatura de moldes para evitar enfriamiento desigual', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-09A', '2025-01-01'::date, 'Líneas de Unión', 'media', 'Líneas de soldadura (Weld lines / Knit lines)', 'A. Temperatura de fusión insuficiente', 'Incrementar la temperatura del cilindro en la zona de plastificación | Aumentar temperatura del molde en la zona de unión | Reducir la contrapresión para mejorar homogeneidad del fundido', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-09B', '2025-01-01'::date, 'Líneas de Unión', 'media', 'Líneas de soldadura (Weld lines / Knit lines)', 'B. Velocidad de inyección baja', 'Aumentar velocidad de inyección para mejorar fusión | Ajustar presión de inyección para mantener continuidad | Optimizar la transición entre inyección y compactación', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-09C', '2025-01-01'::date, 'Líneas de Unión', 'media', 'Líneas de soldadura (Weld lines / Knit lines)', 'C. Ventilación deficiente', 'Ajustar fuerza de cierre del molde para permitir venteo sin fugas | Mantener limpios los canales de ventilación', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-10A', '2025-01-01'::date, 'Degradación del Material', 'media', 'Degradación del material (Material degradation)', 'A. Temperatura excesiva del cilindro', 'Verificar funcionamiento de resistencias y termopares | Ajustar el perfil de temperaturas según la ficha técnica de la resina | Reducir la contrapresión para evitar sobrecalentamiento | Reducir las rpm del tornillo para evitar mucha fricción del fundido', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-10B', '2025-01-01'::date, 'Degradación del Material', 'media', 'Degradación del material (Material degradation)', 'B. Tiempo de residencia muy largo', 'Disminuir la temperatura del cilindro si el ciclo es lento | Reducir el tiempo de plastificación', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-10C', '2025-01-01'::date, 'Degradación del Material', 'media', 'Degradación del material (Material degradation)', 'C. Velocidades o presiones de plastificación inadecuadas', 'Reducir la velocidad de giro del husillo | Ajustar la presión de retroceso para evitar cizallamiento excesivo', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-11A', '2025-01-01'::date, 'Encogimiento Excesivo', 'media', 'Encogimiento excesivo (Excessive shrinkage)', 'A. Temperatura del molde demasiado alta', 'Reducir la temperatura del molde para acelerar solidificación | Revisar y balancear el sistema de refrigeración', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-11B', '2025-01-01'::date, 'Encogimiento Excesivo', 'media', 'Encogimiento excesivo (Excessive shrinkage)', 'B. Presión y tiempo de compactación insuficientes', 'Aumentar la presión de sostenimiento | Prolongar el tiempo de compactación | Optimizar el perfil de inyección (llenado + sostén)', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-11C', '2025-01-01'::date, 'Encogimiento Excesivo', 'media', 'Encogimiento excesivo (Excessive shrinkage)', 'C. Temperatura de fusión muy alta', 'Ajustar perfil de temperaturas del cilindro | Reducir contrapresión para evitar sobrecalentamiento | Evitar tiempos de residencia prolongados', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-12A', '2025-01-01'::date, 'Pegado en Molde', 'alta', 'Adherencia al molde (Sticking / Mold sticking)', 'A. Temperatura del molde demasiado baja', 'Subir temperatura del molde para evitar contracción excesiva | Usar controladores de temperatura para mayor estabilidad | Balancear temperaturas entre cavidades múltiples', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-12B', '2025-01-01'::date, 'Pegado en Molde', 'alta', 'Adherencia al molde (Sticking / Mold sticking)', 'B. Presión de inyección / empaque muy alta', 'Reducir presión de inyección inicial | Disminuir presión de empaque | Ajustar velocidad de inyección para controlar sobrellenado | Usar un perfil de presión escalonado en lugar de presión constante', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-12C', '2025-01-01'::date, 'Pegado en Molde', 'alta', 'Adherencia al molde (Sticking / Mold sticking)', 'C. Tiempo de enfriamiento insuficiente', 'Aumentar tiempo de enfriamiento en el ciclo | Mejorar circulación de agua en canales', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-12D', '2025-01-01'::date, 'Pegado en Molde', 'alta', 'Adherencia al molde (Sticking / Mold sticking)', 'D. Pulido deficiente o rugosidad del molde', 'Limpiar depósitos y residuos con agentes adecuados (solicitar personal del Taller de moldes) | Proteger contra corrosión con aceites o inhibidores (solicitar personal del Taller de moldes)', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-13A', '2025-01-01'::date, 'Contaminación del Material', 'media', 'Contaminación del material (Material contamination)', 'A. Materia prima contaminada (polvo, humedad, aceites, etc.)', 'Usar material virgen o reprocesado controlado y clasificado | Almacenar resina en ambientes cerrados y limpios | Secar adecuadamente el material antes del proceso | Implementar inspección visual del material antes de cargar', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-13B', '2025-01-01'::date, 'Contaminación del Material', 'media', 'Contaminación del material (Material contamination)', 'B. Sistema de alimentación (tolva, hopper, garganta) sucio', 'Limpiar regularmente tolvas, ductos y garganta de alimentación | Evitar acumulación de polvo y pellets triturados | Instalar filtros o separadores de polvo en sistemas de transporte neumático', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-13C', '2025-01-01'::date, 'Contaminación del Material', 'media', 'Contaminación del material (Material contamination)', 'C. Tornillo, cilindro o boquilla con restos de material degradado', 'Realizar purgas regulares con material purgante adecuado | Evitar permanencia prolongada de resina a alta temperatura | Usar perfiles de calentamiento estables para no degradar material', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-14A', '2025-01-01'::date, 'Inestabilidad Dimensional', 'media', 'Inestabilidad dimensional (Dimensional inconsistency)', 'A. Enfriamiento desigual o insuficiente en el molde', 'Asegurar balance térmico en moldes multicavidad | Controlar caudal y temperatura del agua de enfriamiento', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-14B', '2025-01-01'::date, 'Inestabilidad Dimensional', 'media', 'Inestabilidad dimensional (Dimensional inconsistency)', 'B. Contracción del material', 'Ajustar tiempo y presión de empaque para compensar contracción | Mantener temperatura del molde constante en todas las cavidades', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-14C', '2025-01-01'::date, 'Inestabilidad Dimensional', 'media', 'Inestabilidad dimensional (Dimensional inconsistency)', 'C. Variación en parámetros de proceso', 'Usar controladores de temperatura y presión estables y calibrados | Reducir fluctuaciones en velocidad y presión de inyección', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-15A', '2025-01-01'::date, 'Trampas de Aire', 'media', 'Trampas de aire (Air traps)', 'A. Ventilación insuficiente en el molde', 'Revisar y limpiar los venteos actuales para evitar obstrucciones | Asegurar escape de aire por líneas de partición correctamente ajustadas', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-15B', '2025-01-01'::date, 'Trampas de Aire', 'media', 'Trampas de aire (Air traps)', 'B. Velocidad de inyección demasiado alta', 'Reducir velocidad de inyección en la fase inicial | Implementar un perfil de inyección en etapas | Verificar que la boquilla y el bebedero no generen turbulencias excesivas', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-15C', '2025-01-01'::date, 'Trampas de Aire', 'media', 'Trampas de aire (Air traps)', 'C. Temperatura del material o molde incorrecta', 'Aumentar la temperatura del molde para mejorar flujo y evitar cierre prematuro de venteos | Ajustar temperatura del cilindro para mejorar homogeneidad del material | Evitar sobrecalentamiento que degrade el material y genere gases adicionales', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-16A', '2025-01-01'::date, 'Hilos Plateados / Splay', 'media', 'Hilos plateados por humedad (Splay / Silver streaks)', 'A. Material mal secado o con humedad excesiva', 'Secar la resina según especificaciones del proveedor (tiempo, temperatura) | Verificar el contenido de humedad con medidor antes de procesar | Asegurar que el secador esté trabajando correctamente | Evitar tiempos de almacenamiento prolongados en tolvas abiertas', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-16B', '2025-01-01'::date, 'Hilos Plateados / Splay', 'media', 'Hilos plateados por humedad (Splay / Silver streaks)', 'B. Sistema de secado ineficiente o defectuoso', 'Revisar funcionamiento del secador | Cambiar filtros y desecantes de forma preventiva para asegurar rendimiento', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-16C', '2025-01-01'::date, 'Hilos Plateados / Splay', 'media', 'Hilos plateados por humedad (Splay / Silver streaks)', 'C. Condiciones de proceso inadecuadas', 'Evitar temperaturas de cilindro demasiado altas que generen evaporación súbita | Ajustar velocidad de inyección para reducir turbulencias | Mantener boquillas y zonas calientes limpias | Optimizar contrapresión durante la plastificación', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-17A', '2025-01-01'::date, 'Fractura de Pieza', 'alta', 'Fractura de pieza (Brittleness / Cracking)', 'A. Parámetros de proceso incorrectos', 'Reducir presión de inyección o compactación para evitar sobreesfuerzos internos | Ajustar velocidad de inyección para evitar orientaciones moleculares excesivas | Asegurar enfriamiento uniforme y suficiente | Mantener temperaturas de cilindro y molde dentro del rango recomendado', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-17B', '2025-01-01'::date, 'Fractura de Pieza', 'alta', 'Fractura de pieza (Brittleness / Cracking)', 'B. Material degradado', 'Verificar condiciones de secado para evitar hidrólisis en materiales higroscópicos | Evitar temperaturas excesivas que degraden la resina durante el proceso', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-17C', '2025-01-01'::date, 'Fractura de Pieza', 'alta', 'Fractura de pieza (Brittleness / Cracking)', 'C. Enfriamiento demasiado rápido', 'Aumentar tiempo de enfriamiento para permitir contracción uniforme | Optimizar diseño y limpieza de canales de enfriamiento en el molde | Balancear caudal de agua en moldes multicavidad', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-17D', '2025-01-01'::date, 'Fractura de Pieza', 'alta', 'Fractura de pieza (Brittleness / Cracking)', 'D. Tensiones internas por sobreempaque', 'Reducir presión de empaque al mínimo necesario | Ajustar tiempo de empaque para no sobrecargar la pieza | Verificar perfil de presión en etapas en lugar de presión constante', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-17E', '2025-01-01'::date, 'Fractura de Pieza', 'alta', 'Fractura de pieza (Brittleness / Cracking)', 'E. Temperatura de material demasiado baja', 'Aumentar temperatura de cilindro dentro del rango recomendado | Incrementar contrapresión para mejorar homogeneidad de plastificación | Reducir velocidad de husillo para evitar degradación parcial', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-18A', '2025-01-01'::date, 'Baja Densidad / Piezas Esponjosas', 'media', 'Baja densidad / piezas esponjosas (Low packing / Porosity)', 'A. Presión de empaque insuficiente', 'Aumentar la presión de empaque para asegurar empaque adecuado | Prolongar el tiempo de empaque para compensar contracción | Ajustar el punto de transferencia más adelante para llenar mejor la cavidad | Implementar un perfil de presión escalonado', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-18B', '2025-01-01'::date, 'Baja Densidad / Piezas Esponjosas', 'media', 'Baja densidad / piezas esponjosas (Low packing / Porosity)', 'B. Tiempo de empaque muy corto', 'Aumentar tiempo de empaque hasta el sellado del gate | Ajustar enfriamiento para permitir un tiempo de empaque más largo | Revisar balance entre compactación y enfriamiento', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-18C', '2025-01-01'::date, 'Baja Densidad / Piezas Esponjosas', 'media', 'Baja densidad / piezas esponjosas (Low packing / Porosity)', 'C. Temperatura del material demasiado alta', 'Reducir temperaturas del cilindro dentro del rango recomendado | Verificar funcionamiento de resistencias y sensores | Disminuir contrapresión excesiva que degrade el material | Implementar purgas regulares para evitar material degradado en husillo', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-18D', '2025-01-01'::date, 'Baja Densidad / Piezas Esponjosas', 'media', 'Baja densidad / piezas esponjosas (Low packing / Porosity)', 'D. Ventilación deficiente en el molde', 'Limpiar canales de venteo en zonas críticas | Revisar líneas de partición para permitir microescapes de gas | Reducir velocidad de inyección en la primera fase para permitir salida del aire | Asegurar mantenimiento regular del molde', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-19A', '2025-01-01'::date, 'Hilos / Stringing', 'media', 'Hilos / Stringing', 'A. Temperatura de boquilla demasiado alta', 'Reducir la temperatura de la boquilla dentro del rango recomendado | Verificar que la termocupla de la boquilla funcione correctamente | Revisar el perfil de calentamiento para evitar sobrecalentamiento en punta', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-19B', '2025-01-01'::date, 'Hilos / Stringing', 'media', 'Hilos / Stringing', 'B. Presión de retroceso inadecuada', 'Reducir la presión de retroceso para evitar exceso de material presurizado | Ajustar la velocidad de dosificación para controlar la plastificación | Establecer un perfil de contrapresión en lugar de un valor fijo | Controlar la cantidad de material dosificado para evitar rebalse', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-19C', '2025-01-01'::date, 'Hilos / Stringing', 'media', 'Hilos / Stringing', 'C. Fuga de material por mala alineación de boquilla y anillo de centrado', 'Alinear correctamente la boquilla con el anillo de centrado del molde | Revisar desgaste en el anillo de centrado y reemplazarlo si es necesario | Usar boquillas con el mismo radio de punta que el anillo de centrado | Ajustar presión de cierre de la boquilla contra el molde', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-19D', '2025-01-01'::date, 'Hilos / Stringing', 'media', 'Hilos / Stringing', 'D. Tiempo de retracción incorrecto', 'Aumentar la retracción del husillo después de la inyección | Ajustar velocidad de retracción para evitar goteo | Sincronizar el tiempo de retracción con apertura del molde', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-20A', '2025-01-01'::date, 'Puntos Negros', 'alta', 'Puntos negros (Black specks)', 'A. Material degradado o quemado dentro del cilindro o boquilla', 'Ajustar y optimizar las temperaturas de las zonas del cilindro y boquilla | Evitar tiempos de residencia excesivos del material | Usar perfiles de calentamiento escalonados para reducir degradación | Verificar el funcionamiento de resistencias y termocuplas | Reducir la velocidad de plastificación si genera fricción excesiva', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-20B', '2025-01-01'::date, 'Puntos Negros', 'alta', 'Puntos negros (Black specks)', 'B. Residuos carbonizados de ciclos anteriores', 'Realizar una purga con materiales específicos de limpieza | Evitar arranques en frío sin purgar | Usar resina virgen con aditivos de purga antes de cada cambio de color/material', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-20C', '2025-01-01'::date, 'Puntos Negros', 'alta', 'Puntos negros (Black specks)', 'C. Exceso de temperatura en zonas del cilindro o boquilla', 'Revisar perfiles de temperatura y bajarlos en zonas críticas | Evitar mantener la máquina caliente sin producción activa | Corregir resistencias defectuosas que generan puntos calientes | Verificar calibración de termocuplas', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-20D', '2025-01-01'::date, 'Puntos Negros', 'alta', 'Puntos negros (Black specks)', 'D. Humedad en el material', 'Asegurarse que el material haya tenido un buen secado antes de la inyección | Revisar que el equipo de secado se encuentre trabajando correctamente | Purgar el material para eliminar humedad residual en el barril', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-20E', '2025-01-01'::date, 'Puntos Negros', 'alta', 'Puntos negros (Black specks)', 'E. Flujo inadecuado', 'Ajustar la velocidad de inyección y el perfil del tornillo para un flujo uniforme | Reducir la contrapresión para disminuir la fricción en el barril | Mantener la presión de inyección dentro de los rangos recomendados', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-21A', '2025-01-01'::date, 'Opacidad / Brillo Inconsistente', 'media', 'Opacidad o brillo inconsistente (Gloss variation / Surface dullness)', 'A. Temperatura de masa plástica inadecuada', 'Ajustar el perfil de temperaturas de husillo según Ficha Técnica de la resina | Verificar funcionamiento de resistencias y termocuplas | Reducir el tiempo de residencia para evitar degradación | Revisar que no haya zonas frías en el cilindro', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-21B', '2025-01-01'::date, 'Opacidad / Brillo Inconsistente', 'media', 'Opacidad o brillo inconsistente (Gloss variation / Surface dullness)', 'B. Temperatura del molde incorrecta / desigual', 'Ajustar temperatura de molde al rango recomendado por el fabricante de la resina | Balancear el flujo de agua en canales de enfriamiento | Precalentar el molde antes del arranque', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-21C', '2025-01-01'::date, 'Opacidad / Brillo Inconsistente', 'media', 'Opacidad o brillo inconsistente (Gloss variation / Surface dullness)', 'C. Velocidad de inyección incorrecta', 'Incrementar la velocidad en zonas donde se nota mateado | Reducir velocidad si hay turbulencia y brillo irregular | Utilizar inyección en múltiples etapas para estabilizar flujo', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-21D', '2025-01-01'::date, 'Opacidad / Brillo Inconsistente', 'media', 'Opacidad o brillo inconsistente (Gloss variation / Surface dullness)', 'D. Presión de empaque incorrecta', 'Aumentar presión de empaque si hay opacidad por falta de empuje | Reducir presión si se generan manchas brillantes localizadas | Asegurar que el punto de congelamiento del gate sea adecuado', '', '', '', '', 'Base de datos — Excel Rodolfo'),
  ('TSE-21E', '2025-01-01'::date, 'Opacidad / Brillo Inconsistente', 'media', 'Opacidad o brillo inconsistente (Gloss variation / Surface dullness)', 'E. Temperatura del molde fuera de rango', 'Verificar que la temperatura del molde sea la correcta | Verificar el acabado de las cavidades del molde', '', '', '', '', 'Base de datos — Excel Rodolfo')
on conflict (id) do nothing;
