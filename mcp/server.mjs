#!/usr/bin/env node
// A small MCP endpoint for the self-hosted Supermemory server.
//
// The self-hosted binary serves the REST API but not the hosted product's MCP
// endpoint, which coding-agent plugins use for their memory tools. This speaks
// MCP over HTTP and answers each tool call from the REST API. It holds no
// credentials: the caller's bearer token is passed straight through.
import http from "node:http";

const API_URL = (process.env.SUPERMEMORY_API_URL || "http://127.0.0.1:6767").replace(/\/+$/, "");
const HOST = process.env.SUPERMEMORY_MCP_HOST || "0.0.0.0";
const PORT = Number(process.env.SUPERMEMORY_MCP_PORT || 6768);
const DEFAULT_CONTAINER = process.env.SUPERMEMORY_MCP_DEFAULT_CONTAINER || "default";
// The server's own default cut-off drops paraphrased and cross-language
// matches, so ask for looser ones and let the caller judge by the score.
const SEARCH_THRESHOLD = Number(process.env.SUPERMEMORY_MCP_SEARCH_THRESHOLD || 0.3);
const MAX_BODY_BYTES = 1024 * 1024;

const containerTag = {
  type: "string",
  description: "Space to use, such as a project's container tag. Omit for the default space.",
};

const TOOLS = [
  {
    name: "search_memory",
    description: "Search stored memories in one space with a natural-language query.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "What to look for." },
        containerTag,
        limit: { type: "integer", minimum: 1, maximum: 50, description: "Most results to return (default 10)." },
      },
      required: ["query"],
    },
    annotations: { readOnlyHint: true },
  },
  {
    name: "add_memory",
    description: "Save a memory to a space. The server extracts facts from it in the background.",
    inputSchema: {
      type: "object",
      properties: {
        content: { type: "string", description: "The text to remember." },
        containerTag,
      },
      required: ["content"],
    },
  },
  {
    name: "listDocuments",
    description: "List the most recent documents saved in a space, with their processing status.",
    inputSchema: {
      type: "object",
      properties: {
        containerTag,
        limit: { type: "integer", minimum: 1, maximum: 100, description: "Most documents to return (default 20)." },
      },
    },
    annotations: { readOnlyHint: true },
  },
  {
    name: "listSpaces",
    description: "List every space (one per project) with its memory and document counts.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true },
  },
  {
    name: "listMemories",
    description:
      "List the memories learned in a space, newest first, one page at a time. Pass ids instead to get those " +
      "memories in full: their earlier and later versions and the document they came from.",
    inputSchema: {
      type: "object",
      properties: {
        containerTag,
        page: { type: "integer", minimum: 1, description: "Page to return (default 1)." },
        limit: { type: "integer", minimum: 1, maximum: 100, description: "Memories per page (default 100)." },
        ids: { type: "array", items: { type: "string" }, maxItems: 20, description: "Memory IDs to show in full." },
      },
    },
    annotations: { readOnlyHint: true },
  },
  {
    name: "whoAmI",
    description: "Show which Supermemory server these tools talk to and whether the credentials work.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true },
  },
];

// A body makes it a POST; without one it is a GET.
async function api(authorization, path, body) {
  const response = await fetch(`${API_URL}${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { Authorization: authorization, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(25000),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Supermemory API ${response.status}: ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : {};
}

const text = (value) => ({ content: [{ type: "text", text: value }] });
const day = (iso) => (iso || "").slice(0, 10);
const oneLine = (value, max = 300) => {
  const flat = (value || "").replace(/\s+/g, " ").trim();
  return flat.length > max ? `${flat.slice(0, max)}…` : flat;
};

// One line per memory: what an agent needs to judge it without opening it.
function memoryLine(memory) {
  const flags = [
    `v${memory.version}`,
    !memory.isLatest && "superseded",
    memory.isStatic && "static",
    memory.isInference && "inferred",
    memory.isForgotten && "forgotten",
  ].filter(Boolean);
  return `- ${memory.id} · ${day(memory.system?.createdAt)} · ${flags.join(" · ")} — ${oneLine(memory.memory, 1000)}`;
}

function memoryDetail(memory) {
  const lines = [`### ${memory.id}`, memoryLine(memory).slice(2)];
  const related = memory.included?.related || {};
  const sections = [
    ["Earlier versions", related.parents],
    ["Later versions", related.children],
    ["Related", related.siblings],
  ];
  for (const [title, items] of sections) {
    if (!items?.length) continue;
    lines.push(`${title}:`);
    for (const item of items) {
      const version = item.version == null ? "" : ` v${item.version}`;
      lines.push(`  - ${item.id}${version} (${item.relation}, ${day(item.system?.updatedAt)}) — ${oneLine(item.memory)}`);
    }
  }
  const doc = memory.included?.document;
  if (doc) {
    const label = oneLine(doc.summary || doc.title, 200);
    lines.push(`Source document: ${doc.id} (${day(doc.system?.createdAt)}) ${label}`);
  }
  return lines.join("\n");
}

const handlers = {
  async search_memory(args, authorization) {
    if (typeof args.query !== "string" || !args.query.trim()) throw new Error("query is required");
    const tag = args.containerTag || DEFAULT_CONTAINER;
    const found = await api(authorization, "/v4/search", {
      q: args.query,
      containerTag: tag,
      limit: args.limit || 10,
      threshold: SEARCH_THRESHOLD,
    });
    const results = found.results || [];
    if (results.length === 0) return text(`No matching memories found in ${tag}.`);
    const lines = results.map((result) => {
      const body = result.memory || result.chunk || result.content || "";
      return `- [${Math.round((result.similarity || 0) * 100)}%] ${body}`;
    });
    return text(`## Matching memories (${tag})\n${lines.join("\n")}`);
  },

  async add_memory(args, authorization) {
    if (typeof args.content !== "string" || !args.content.trim()) throw new Error("content is required");
    const tag = args.containerTag || DEFAULT_CONTAINER;
    const saved = await api(authorization, "/v3/documents", { content: args.content, containerTag: tag });
    return text(`Memory saved (ID: ${saved.id}, space: ${tag}, status: ${saved.status}).`);
  },

  async listDocuments(args, authorization) {
    const tag = args.containerTag || DEFAULT_CONTAINER;
    const listed = await api(authorization, "/v3/documents/list", { containerTags: [tag], limit: args.limit || 20 });
    const documents = listed.memories || [];
    if (documents.length === 0) return text(`No documents in ${tag}.`);
    const lines = documents.map((doc) => {
      const label = (doc.title || doc.summary || "").replace(/\s+/g, " ").slice(0, 100);
      return `- ${doc.id} [${doc.status}] ${doc.createdAt || ""} ${label}`;
    });
    return text(`## Documents (${tag})\n${lines.join("\n")}`);
  },

  async listSpaces(_args, authorization) {
    const spaces = [];
    for (let page = 1; ; page++) {
      const listed = await api(authorization, `/ns?page=${page}&limit=100`);
      spaces.push(...(listed.namespaces || []));
      if ((listed.namespaces || []).length < 100) break;
    }
    if (spaces.length === 0) return text("No spaces yet.");
    spaces.sort((a, b) => b.memoryCount - a.memoryCount);
    const lines = spaces.map(
      (space) =>
        `- ${space.namespace} · ${space.memoryCount} memories · ${space.documentCount} documents · ` +
        `updated ${day(space.system?.updatedAt)}`,
    );
    return text(`## Spaces (${spaces.length})\n${lines.join("\n")}`);
  },

  async listMemories(args, authorization) {
    const tag = encodeURIComponent(args.containerTag || DEFAULT_CONTAINER);
    if (Array.isArray(args.ids) && args.ids.length > 0) {
      const details = await Promise.all(
        args.ids.slice(0, 20).map((id) =>
          api(authorization, `/ns/${tag}/memories/${encodeURIComponent(id)}?include=related,documents`)
            .then(memoryDetail)
            .catch((error) => `### ${id}\n${error.message}`),
        ),
      );
      return text(details.join("\n\n"));
    }
    const page = args.page || 1;
    const query = `page=${page}&limit=${args.limit || 100}&sort=createdAt&order=desc`;
    const listed = await api(authorization, `/ns/${tag}/list/memories?${query}`, {});
    const memories = listed.memories || [];
    if (memories.length === 0) return text(`No memories in ${args.containerTag || DEFAULT_CONTAINER}.`);
    const { totalItems, totalPages } = listed.pagination || {};
    const more = page < totalPages ? ` Call again with page ${page + 1} for more.` : "";
    return text(
      `## Memories (${args.containerTag || DEFAULT_CONTAINER}) · page ${page} of ${totalPages} · ${totalItems} total.${more}\n` +
        memories.map(memoryLine).join("\n"),
    );
  },

  async whoAmI(_args, authorization) {
    const listed = await api(authorization, "/v3/documents/list", { limit: 1 });
    const total = listed.pagination?.totalItems ?? "unknown";
    return text(`Self-hosted Supermemory at ${API_URL}. Credentials accepted. Documents stored: ${total}.`);
  },
};

async function handleMessage(message, authorization) {
  const { id, method, params } = message;
  const reply = (result) => ({ jsonrpc: "2.0", id, result });
  const fail = (code, description) => ({ jsonrpc: "2.0", id, error: { code, message: description } });

  if (id === undefined || id === null) return null; // notifications need no answer
  switch (method) {
    case "initialize":
      return reply({
        protocolVersion: params?.protocolVersion || "2025-03-26",
        capabilities: { tools: {} },
        serverInfo: { name: "supermemory-selfhosted", version: "0.2.0" },
      });
    case "ping":
      return reply({});
    case "tools/list":
      return reply({ tools: TOOLS });
    case "tools/call": {
      const handler = Object.hasOwn(handlers, params?.name) ? handlers[params.name] : null;
      if (!handler) return fail(-32602, `Unknown tool: ${params?.name}`);
      let args = params.arguments ?? {};
      if (typeof args === "string") {
        try {
          args = JSON.parse(args);
        } catch {
          return fail(-32602, "Tool arguments are not valid JSON");
        }
      }
      try {
        return reply(await handler(args, authorization));
      } catch (error) {
        return reply({ ...text(`Error: ${error.message}`), isError: true });
      }
    }
    default:
      return fail(-32601, `Method not found: ${method}`);
  }
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new Error("Request body too large"));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

const server = http.createServer(async (request, response) => {
  const send = (status, body) => {
    response.writeHead(status, body === undefined ? {} : { "Content-Type": "application/json" });
    response.end(body === undefined ? undefined : JSON.stringify(body));
  };

  const path = new URL(request.url, "http://localhost").pathname;
  if (path !== "/mcp") return send(404, { error: "Not found" });
  if (request.method !== "POST") return send(405, { error: "Use POST" });
  const authorization = request.headers.authorization;
  if (!authorization) return send(401, { error: "Missing Authorization header" });

  let message;
  try {
    message = JSON.parse(await readBody(request));
  } catch {
    return send(400, { jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
  }

  const messages = Array.isArray(message) ? message : [message];
  const answers = (await Promise.all(messages.map((entry) => handleMessage(entry, authorization)))).filter(Boolean);
  if (answers.length === 0) return send(202);
  send(200, Array.isArray(message) ? answers : answers[0]);
});

server.listen(PORT, HOST, () => {
  console.log(`supermemory-mcp listening on http://${HOST}:${PORT}/mcp -> ${API_URL}`);
});
