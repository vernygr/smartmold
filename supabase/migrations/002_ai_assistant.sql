-- ══════════════════════════════════════════════════════════
-- SmartMold EP — Asistente de IA (respaldo del árbol de diagnóstico)
-- Ejecutar una sola vez en: Supabase Dashboard → SQL Editor
-- Requiere que supabase/schema.sql ya se haya ejecutado antes.
-- ══════════════════════════════════════════════════════════

alter table public.records
  add column if not exists origen text not null default 'manual'
    check (origen in ('manual', 'arbol', 'ia'));

alter table public.records
  add column if not exists revisado boolean not null default true;

comment on column public.records.origen is
  'Cómo se creó el registro: manual (formulario), arbol (diagnóstico guiado) o ia (asistente de IA).';
comment on column public.records.revisado is
  'Falso para sugerencias de IA que un admin todavía no confirmó como correctas.';
