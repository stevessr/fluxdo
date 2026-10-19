/**
 * NSH 实验专用的匿名、只读 Discourse API。
 *
 * 刻意不接收 Cookie / API Key，也不提供任何写请求；迁移正式客户端时，
 * 必须改为宿主提供、受权限约束的会话和业务服务，而不是在 TSX 内存储凭据。
 */
const ORIGIN = "https://linux.do";

export type FeedMode = "latest" | "top";

export interface Topic {
  id: number;
  slug: string;
  title: string;
  postsCount: number;
  views: number;
  likeCount: number;
  tags: string[];
}

export interface Post {
  id: number;
  author: string;
  body: string;
  postNumber: number;
}

type JsonObject = Record<string, unknown>;

function object(value: unknown): JsonObject {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Discourse 返回的数据格式不正确");
  }
  return value as JsonObject;
}

function number(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function string(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function decodeEntities(value: string): string {
  const named: Record<string, string> = {
    amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
  };
  return value.replace(/&(#(?:x[0-9a-f]+|[0-9]+)|[a-z]+);/gi, (match, key: string) => {
    if (key[0] !== "#") return named[key.toLowerCase()] ?? match;
    const hex = key[1]?.toLowerCase() === "x";
    const code = Number.parseInt(key.slice(hex ? 2 : 1), hex ? 16 : 10);
    if (!Number.isFinite(code) || code < 0 || code > 0x10ffff) return match;
    try { return String.fromCodePoint(code); } catch { return match; }
  });
}

/** 仅提取可显示的纯文本，不尝试把 Discourse cooked HTML 注入原生控件。 */
export function cookedToText(html: string): string {
  return decodeEntities(
    html
      .replace(/<br\s*\/?\s*>/gi, "\n")
      .replace(/<\/(?:p|div|li|blockquote|h[1-6])\s*>/gi, "\n")
      .replace(/<[^>]+>/g, "")
  ).replace(/\n{3,}/g, "\n\n").trim();
}

async function getJson(path: string): Promise<JsonObject> {
  const response = await fetch(ORIGIN + path, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(12_000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}：公开数据请求失败`);
  return object(await response.json());
}

export async function fetchTopics(mode: FeedMode): Promise<Topic[]> {
  const path = mode === "latest" ? "/latest.json" : "/top.json?period=weekly";
  const payload = await getJson(path);
  const topicList = object(payload.topic_list);
  if (!Array.isArray(topicList.topics)) throw new Error("话题列表字段缺失");
  return topicList.topics.map((value: unknown) => {
    const t = object(value);
    return {
      id: number(t.id),
      slug: string(t.slug),
      title: decodeEntities(string(t.title)),
      postsCount: number(t.posts_count),
      views: number(t.views),
      likeCount: number(t.like_count),
      tags: Array.isArray(t.tags) ? t.tags.filter((x): x is string => typeof x === "string") : [],
    };
  }).filter((topic: Topic) => topic.id > 0 && topic.slug && topic.title);
}

export async function fetchPosts(topic: Topic): Promise<Post[]> {
  // slug 来自 API，但仍转义以防被拼接成新的路径 / 查询参数。
  const payload = await getJson(`/t/${encodeURIComponent(topic.slug)}/${topic.id}.json`);
  const stream = object(payload.post_stream);
  if (!Array.isArray(stream.posts)) throw new Error("帖子内容字段缺失");
  return stream.posts.slice(0, 12).map((value: unknown) => {
    const p = object(value);
    return {
      id: number(p.id),
      postNumber: number(p.post_number),
      author: string(p.username, "匿名用户"),
      body: cookedToText(string(p.cooked)).slice(0, 1800),
    };
  }).filter((post: Post) => post.id > 0);
}

export function compactCount(count: number): string {
  return count >= 10000 ? (count / 10000).toFixed(1) + "万" : String(count);
}
