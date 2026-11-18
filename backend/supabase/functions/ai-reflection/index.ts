import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// DearCocoa — Edge Function "ai-reflection"
// Thread di riflessione AI 1:1 per ogni voce del diario, con memoria
// persistente (ai_memory) e compressione automatica ogni 6 risposte.
//
// Deploy:  supabase functions deploy ai-reflection
// Secrets: supabase secrets set AI_API_KEY=... AI_MODEL=gpt-4o-mini
//          (opzionale AI_BASE_URL per provider OpenAI-compatibili)
//
// Chiamata (dall'app): supabase.functions.invoke('ai-reflection',
//   body: { entryId, message })  ->  { reply }

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

const SYSTEM_PROMPT = `You are Cocoa, the warm, curious AI companion inside DearCocoa, a private journaling app.
Your role: help the writer reflect on the journal entry they shared with you.

Style and rules:
- Warm, grounded, never saccharine. Talk like a thoughtful friend, not a therapist or a search engine.
- Ask ONE thoughtful question at a time when it deepens reflection; do not interrogate.
- Ground your reply in the entry's actual content and the memory provided. Never invent facts.
- No diagnoses, no medical or clinical claims, no "you should" prescriptions.
- Keep replies under 220 words. Use plain prose; at most one short list.
- Write in the same language the user writes in.
- If the entry contains signals of self-harm, crisis or abuse: respond with care, validate the feeling,
  gently encourage contacting local emergency services or a professional, and do not lecture.

You receive: the journal entry, durable memory notes about the writer, and the recent conversation.`;

const MEMORY_PROMPT = `From this journaling conversation, extract up to 3 durable facts or preferences about the writer
that would help a future conversation feel continuous (e.g. "is preparing a job interview", "finds morning walks calming").
One short sentence each, no commentary, no sensitive data beyond what was written. If nothing durable emerged, return an empty line.
Reply with ONLY the lines, one per fact.`;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method === 'GET') {
    return json({ ok: true, service: 'ai-reflection' });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
    const AI_API_KEY = Deno.env.get('AI_API_KEY') ?? Deno.env.get('OPENAI_API_KEY') ?? '';
    const AI_BASE_URL = Deno.env.get('AI_BASE_URL') ?? 'https://api.openai.com/v1';
    const AI_MODEL = Deno.env.get('AI_MODEL') ?? 'gpt-4o-mini';

    if (!AI_API_KEY) {
      return json({ error: 'AI_API_KEY non configurata. Esegui: supabase secrets set AI_API_KEY=...' }, 500);
    }

    // --- auth: il JWT dell'utente arriva nell'header Authorization ---
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      return json({ error: 'Missing bearer token' }, 401);
    }

    // client con identità dell'utente: RLS garantisce che tocchi solo i suoi dati
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: 'Invalid token' }, 401);
    }
    const uid = userData.user.id;

    const body = await req.json().catch(() => null);
    const entryId = body?.entryId as string | undefined;
    const message = (body?.message as string | undefined)?.trim();
    if (!entryId || !message) {
      return json({ error: 'entryId e message sono richiesti' }, 400);
    }

    // --- la voce appartiene all'utente? (RLS: SELECT limitata al proprietario) ---
    const { data: entry, error: entryErr } = await userClient
      .from('journal_entries')
      .select('id, user_id, title, body, mood, entry_date')
      .eq('id', entryId)
      .limit(1)
      .maybeSingle();
    if (entryErr || !entry) {
      return json({ error: 'Entry non trovata o non tua' }, 404);
    }

    // --- contesto: thread recente + memoria persistente ---
    const [{ data: thread }, { data: memory }] = await Promise.all([
      userClient
        .from('ai_reflections')
        .select('role, content, created_at')
        .eq('entry_id', entryId)
        .order('created_at', { ascending: false })
        .limit(12),
      userClient
        .from('ai_memory')
        .select('content')
        .eq('user_id', uid)
        .order('importance', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(8),
    ]);

    const recent = (thread ?? []).reverse(); // cronologico
    const memoryText = (memory ?? []).map((m: { content: string }) => `- ${m.content}`).join('\n');
    const entryExcerpt = [
      `Title: ${entry.title || '(untitled)'}`,
      `Date: ${entry.entry_date}`,
      `Mood (1-5): ${entry.mood ?? 'not set'}`,
      `Entry: ${(entry.body || '').slice(0, 4000)}`,
    ].join('\n');

    const chatMessages = [
      { role: 'system', content: SYSTEM_PROMPT },
      {
        role: 'system',
        content: `Journal entry under discussion:\n${entryExcerpt}\n\nDurable memory about the writer:\n${memoryText || '(none yet)'}`,
      },
      ...recent.map((m: { role: string; content: string }) => ({ role: m.role, content: m.content })),
      { role: 'user', content: message },
    ];

    // --- salviamo subito il messaggio utente, poi generiamo la risposta ---
    const { error: insErr } = await userClient.from('ai_reflections').insert({
      entry_id: entryId,
      user_id: uid,
      role: 'user',
      content: message,
    });
    if (insErr) return json({ error: insErr.message }, 500);

    const reply = await callLLM(AI_BASE_URL, AI_API_KEY, AI_MODEL, chatMessages, 700, 0.8);
    if (!reply) return json({ error: 'LLM non ha risposto' }, 502);

    const { error: replyErr } = await userClient.from('ai_reflections').insert({
      entry_id: entryId,
      user_id: uid,
      role: 'assistant',
      content: reply,
    });
    if (replyErr) return json({ error: replyErr.message }, 500);

    // --- compressione memoria: ogni 6 risposte assistant estraiamo i fatti durevoli ---
    const assistantCount = recent.filter((m: { role: string }) => m.role === 'assistant').length + 1;
    let memorySaved = false;
    if (assistantCount % 6 === 0) {
      const transcript = recent
        .map((m: { role: string; content: string }) => `${m.role === 'user' ? 'Writer' : 'Cocoa'}: ${m.content}`)
        .join('\n')
        .slice(-6000);
      const facts = await callLLM(AI_BASE_URL, AI_API_KEY, AI_MODEL, [
        { role: 'system', content: MEMORY_PROMPT },
        { role: 'user', content: `Entry:\n${entryExcerpt}\n\nConversation:\n${transcript}` },
      ], 200, 0.3);
      const lines = (facts ?? '')
        .split('\n')
        .map((l) => l.replace(/^[-*\d.\s]+/, '').trim())
        .filter((l) => l.length > 8)
        .slice(0, 3);
      if (lines.length > 0) {
        const { error: memErr } = await userClient.from('ai_memory').insert(
          lines.map((content) => ({ user_id: uid, kind: 'summary', content, importance: 3, source_entry: entryId })),
        );
        memorySaved = !memErr;
      }
    }

    return json({ reply, memorySaved });
  } catch (e) {
    console.error('ai-reflection error:', e);
    return json({ error: 'Errore interno', detail: String(e) }, 500);
  }
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

async function callLLM(
  baseUrl: string,
  apiKey: string,
  model: string,
  messages: { role: string; content: string }[],
  maxTokens: number,
  temperature: number,
): Promise<string | null> {
  const res = await fetch(`${baseUrl.replace(/\/$/, '')}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ model, messages, max_tokens: maxTokens, temperature }),
  });
  if (!res.ok) {
    console.error('LLM error', res.status, await res.text());
    return null;
  }
  const data = await res.json();
  return data?.choices?.[0]?.message?.content ?? null;
}
