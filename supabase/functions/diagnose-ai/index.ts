// SmartMold EP — Asistente de IA (respaldo del árbol de diagnóstico)
//
// Se despliega y edita desde: Supabase Dashboard → Edge Functions → diagnose-ai
// Requiere el secreto GEMINI_API_KEY (Dashboard → Edge Functions → Secrets),
// obtenido gratis en https://aistudio.google.com/apikey
//
// IMPORTANTE: en la configuración de esta función (Dashboard → Edge Functions
// → diagnose-ai → Settings) desactiva "Enforce JWT Verification". La
// verificación a nivel de plataforma intercepta también el preflight CORS
// (OPTIONS) y lo rechaza porque el navegador no manda Authorization en esa
// solicitud — por eso la verificación de sesión se hace acá abajo, a mano,
// después de responder el OPTIONS.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    categoria_sugerida: { type: "STRING" },
    severidad: { type: "STRING", enum: ["alta", "media", "baja"] },
    sintoma_resumen: { type: "STRING" },
    causa_raiz: { type: "STRING" },
    solucion: { type: "STRING" },
    parametro: { type: "STRING" },
    confianza: { type: "STRING", enum: ["alta", "media", "baja"] },
    nota: { type: "STRING" },
  },
  required: ["categoria_sugerida", "severidad", "causa_raiz", "solucion", "confianza"],
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "No autenticado." }, 401);
    }

    // Cliente con la sesión del técnico que llama — respeta las mismas RLS
    // que ya protegen records/defect_categories, sin necesitar service role.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return jsonResponse({ error: "Sesión inválida o expirada. Vuelve a iniciar sesión." }, 401);
    }

    const { descripcion } = await req.json();
    if (!descripcion || typeof descripcion !== "string" || descripcion.trim().length < 8) {
      return jsonResponse({ error: "Describe el problema con al menos una frase completa." }, 400);
    }

    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      return jsonResponse({ error: "El asistente de IA no está configurado (falta GEMINI_API_KEY)." }, 500);
    }

    const [{ data: categorias }, { data: registros }] = await Promise.all([
      supabase.from("defect_categories").select("label, hint").order("sort_order"),
      supabase.from("records").select("categoria, sintoma, causa_raiz, solucion")
        .order("created_at", { ascending: false }).limit(120),
    ]);

    const prompt = buildPrompt(descripcion, categorias || [], registros || []);

    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=${geminiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: RESPONSE_SCHEMA,
            temperature: 0.2,
          },
        }),
      },
    );

    if (geminiRes.status === 429) {
      return jsonResponse({ error: "Se alcanzó el límite gratuito de consultas de IA por ahora. Intenta de nuevo en unos minutos." }, 429);
    }
    if (!geminiRes.ok) {
      const detail = await geminiRes.text();
      console.error("Gemini error:", geminiRes.status, detail);
      return jsonResponse({ error: "El asistente de IA no pudo responder en este momento." }, 502);
    }

    const geminiData = await geminiRes.json();
    const text = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) {
      return jsonResponse({ error: "El asistente de IA devolvió una respuesta vacía." }, 502);
    }

    const diagnostico = JSON.parse(text);
    return jsonResponse({ diagnostico });
  } catch (err) {
    console.error("diagnose-ai error:", err);
    return jsonResponse({ error: "Ocurrió un error inesperado procesando la consulta." }, 500);
  }
});

function buildPrompt(descripcion: string, categorias: any[], registros: any[]): string {
  const listaCategorias = categorias.map((c) => `- ${c.label}: ${c.hint}`).join("\n");
  const historial = registros
    .slice(0, 60)
    .map((r) => `- [${r.categoria}] síntoma: ${r.sintoma} | causa: ${r.causa_raiz} | solución: ${r.solucion}`)
    .join("\n");

  return `Eres un asistente experto en diagnóstico de defectos de moldeo por inyección de plástico, para técnicos de la planta ElectroPlast.

Un técnico describe un problema que no encajó claramente en el árbol de diagnóstico guiado de la app. Tu trabajo es sugerir un diagnóstico y solución, basándote en la categoría de defecto más parecida y en el historial de casos reales de la planta cuando sea relevante.

Categorías de defecto conocidas:
${listaCategorias}

Historial de casos reales (referencia, puede estar incompleto):
${historial}

Descripción del técnico:
"""
${descripcion.trim()}
"""

Responde SOLO con el diagnóstico estructurado. Si la descripción es demasiado ambigua para dar una causa raíz específica, dilo honestamente en "nota" y baja el nivel de "confianza" en vez de inventar una causa.`;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
