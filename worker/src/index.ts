/**
 * Yaven Proxy Worker
 *
 * Proxies requests to Claude and ElevenLabs APIs so the app never
 * ships with raw API keys. Keys are stored as Cloudflare secrets.
 *
 * Routes:
 *   POST /chat  → Anthropic Messages API (streaming)
 *   POST /tts   → ElevenLabs TTS API
 */

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  COMPOSIO_API_KEY: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    try {
      if (url.pathname === "/tools" && request.method === "GET") {
        return await handleTools(env);
      }

      if (url.pathname === "/connection-status" && request.method === "GET") {
        return await handleConnectionStatus(url, env);
      }

      if (request.method !== "POST") {
        return new Response("Method not allowed", { status: 405 });
      }

      if (url.pathname === "/connect") {
        return await handleConnect(request, env);
      }

      if (url.pathname === "/chat") {
        return await handleChat(request, env);
      }

      if (url.pathname === "/tts") {
        return await handleTTS(request, env);
      }

      if (url.pathname === "/transcribe-token") {
        return await handleTranscribeToken(env);
      }

      if (url.pathname === "/execute") {
        return await handleExecute(request, env);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return new Response(
        JSON.stringify({ error: String(error) }),
        { status: 500, headers: { "content-type": "application/json" } }
      );
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleTools(env: Env): Promise<Response> {
  const response = await fetch("https://backend.composio.dev/api/v1/apps", {
    headers: { "x-api-key": env.COMPOSIO_API_KEY },
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tools] Composio API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.json() as { items: Array<{
    key: string;
    displayName: string;
    logo: string;
    enabled: boolean;
  }> };

  const tools = data.items
    .filter(app => app.enabled)
    .map(app => ({ key: app.key, name: app.displayName, logo: app.logo }));

  return new Response(JSON.stringify({ tools }), {
    status: 200,
    headers: {
      "content-type": "application/json",
      "cache-control": "public, max-age=86400",
    },
  });
}

async function handleChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function handleTranscribeToken(env: Env): Promise<Response> {
  const response = await fetch(
    "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480",
    {
      method: "GET",
      headers: {
        authorization: env.ASSEMBLYAI_API_KEY,
      },
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe-token] AssemblyAI token error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleConnect(request: Request, env: Env): Promise<Response> {
  const { appKey, entityId } = await request.json() as { appKey: string; entityId: string };

  // Step 1: find an existing integration for this app.
  let integrationId: string | undefined;
  const intResp = await fetch(
    "https://backend.composio.dev/api/v1/integrations?showDisabled=false&pageSize=100",
    { headers: { "x-api-key": env.COMPOSIO_API_KEY } }
  );
  if (intResp.ok) {
    const intData = await intResp.json() as { items: Array<{ id: string; appName?: string; name?: string }> };
    const match = intData.items?.find(i =>
      i.appName?.toLowerCase() === appKey.toLowerCase() ||
      i.name?.toLowerCase().includes(appKey.toLowerCase())
    );
    integrationId = match?.id;
    console.log(`[/connect] ${intData.items?.length ?? 0} integrations. Match for "${appKey}": ${integrationId ?? "none"}`);
  }

  // Step 2: if no integration exists, create one using Composio's shared OAuth credentials.
  if (!integrationId) {
    const appResp = await fetch(
      `https://backend.composio.dev/api/v1/apps/${encodeURIComponent(appKey.toLowerCase())}`,
      { headers: { "x-api-key": env.COMPOSIO_API_KEY } }
    );
    if (!appResp.ok) {
      const err = await appResp.text();
      console.error(`[/connect] Could not fetch app "${appKey}": ${err}`);
      return new Response(JSON.stringify({ error: `Unknown app: ${appKey}` }), {
        status: 400,
        headers: { "content-type": "application/json" },
      });
    }
    const appData = await appResp.json() as { appId: string; auth_schemes?: Array<{ mode: string }> };
    // Use the app's declared auth scheme (e.g. DCR_OAUTH for Granola), fall back to OAUTH2.
    const authScheme = appData.auth_schemes?.[0]?.mode ?? "OAUTH2";
    // useComposioAuth only applies to OAUTH2 apps. DCR_OAUTH (e.g. Granola) registers dynamically.
    const useComposioAuth = authScheme === "OAUTH2";
    console.log(`[/connect] Creating integration for "${appKey}" authScheme=${authScheme} useComposioAuth=${useComposioAuth}`);

    const createResp = await fetch("https://backend.composio.dev/api/v1/integrations", {
      method: "POST",
      headers: { "x-api-key": env.COMPOSIO_API_KEY, "content-type": "application/json" },
      body: JSON.stringify({ appId: appData.appId, authScheme, name: appKey, useComposioAuth }),
    });
    if (!createResp.ok) {
      const err = await createResp.text();
      console.error(`[/connect] Could not create integration for "${appKey}": ${err}`);
      // 306 = Composio has no managed credentials for this toolkit.
      // Return unsupported so the app can skip it gracefully.
      let errCode: number | undefined;
      try { errCode = (JSON.parse(err) as { details?: { error?: { code?: number } } })?.details?.error?.code; } catch {}
      if (errCode === 306) {
        return new Response(JSON.stringify({ unsupported: true }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }
      return new Response(err, { status: createResp.status, headers: { "content-type": "application/json" } });
    }
    const created = await createResp.json() as { id: string };
    integrationId = created.id;
    console.log(`[/connect] Created integration for "${appKey}": ${integrationId}`);
  }

  // Step 3: initiate the OAuth connection (v1 with integrationId).
  const response = await fetch("https://backend.composio.dev/api/v1/connectedAccounts", {
    method: "POST",
    headers: {
      "x-api-key": env.COMPOSIO_API_KEY,
      "content-type": "application/json",
    },
    body: JSON.stringify({ integrationId, entityId, data: {} }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/connect] Composio error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const raw = await response.json() as Record<string, unknown>;
  const normalised = {
    connectedAccountId: raw.connectedAccountId ?? raw.id,
    redirectUrl: raw.redirectUrl ?? raw.redirectUri,
    connectionStatus: raw.connectionStatus ?? raw.status,
  };
  return new Response(JSON.stringify(normalised), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleConnectionStatus(url: URL, env: Env): Promise<Response> {
  const id = url.searchParams.get("id");
  if (!id) {
    return new Response(JSON.stringify({ error: "Missing id" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const response = await fetch(
    `https://backend.composio.dev/api/v1/connectedAccounts/${encodeURIComponent(id)}`,
    { headers: { "x-api-key": env.COMPOSIO_API_KEY } }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/connection-status] Composio error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.json();
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleExecute(request: Request, env: Env): Promise<Response> {
  const { actionSlug, entityId, arguments: args } = await request.json() as {
    actionSlug: string;
    entityId: string;
    arguments: Record<string, unknown>;
  };

  const response = await fetch(
    `https://backend.composio.dev/api/v3/tools/execute/${encodeURIComponent(actionSlug)}`,
    {
      method: "POST",
      headers: { "x-api-key": env.COMPOSIO_API_KEY, "content-type": "application/json" },
      body: JSON.stringify({ entity_id: entityId, arguments: args ?? {} }),
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/execute] Composio error ${response.status} for ${actionSlug}: ${errorBody}`);
    return new Response(errorBody, { status: response.status, headers: { "content-type": "application/json" } });
  }

  const data = await response.text();
  return new Response(data, { status: 200, headers: { "content-type": "application/json" } });
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const voiceId = env.ELEVENLABS_VOICE_ID;

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body,
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] ElevenLabs API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}

async function handleComposioAction(request: Request, env: Env): Promise<Response> {
  const { action, entityId, input } = await request.json() as {
    action: string;
    entityId: string;
    input: Record<string, unknown>;
  };

  const response = await fetch(
    `https://backend.composio.dev/api/v2/actions/${encodeURIComponent(action)}/execute`,
    {
      method: "POST",
      headers: {
        "x-api-key": env.COMPOSIO_API_KEY,
        "content-type": "application/json",
      },
      body: JSON.stringify({ entityId, input }),
    }
  );

  const data = await response.text();
  if (!response.ok) {
    console.error(`[/composio-action] ${action} failed ${response.status}: ${data}`);
  }
  return new Response(data, {
    status: response.status,
    headers: { "content-type": "application/json" },
  });
}
