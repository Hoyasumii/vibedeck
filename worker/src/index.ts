// Serves the VibeDeck JSON Schemas (copied from ../schema into ./public at build time).
interface Env {
  ASSETS: Fetcher;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", { status: 405, headers: CORS });
    }

    const url = new URL(request.url);
    if (url.pathname === "/" || url.pathname === "/v1" || url.pathname === "/v1/") {
      const base = `${url.origin}/v1`;
      return Response.json(
        {
          name: "VibeDeck schemas",
          schemas: {
            project: `${base}/project.schema.json`,
            reviewGroup: `${base}/review-group.schema.json`,
            ruleTopic: `${base}/rule-topic.schema.json`,
            idea: `${base}/idea.schema.json`,
            agent: `${base}/agent.schema.json`,
            command: `${base}/command.schema.json`,
            skill: `${base}/skill.schema.json`,
            workflow: `${base}/workflow.schema.json`,
            workflowRun: `${base}/workflow-run.schema.json`,
            ruleCheck: `${base}/rule-check.schema.json`,
          },
        },
        { headers: CORS },
      );
    }

    const asset = await env.ASSETS.fetch(request);
    if (!asset.ok) return new Response("Not Found", { status: 404, headers: CORS });

    const headers = new Headers(asset.headers);
    for (const [k, v] of Object.entries(CORS)) headers.set(k, v);
    if (url.pathname.endsWith(".schema.json")) {
      headers.set("Content-Type", "application/schema+json; charset=utf-8");
      // Versioned paths are append-only: cache for a day, revalidate in the background.
      headers.set("Cache-Control", "public, max-age=86400, stale-while-revalidate=604800");
    }
    return new Response(asset.body, { status: asset.status, headers });
  },
} satisfies ExportedHandler<Env>;
