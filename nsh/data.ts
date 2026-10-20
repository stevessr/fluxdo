/** Fluxdo NSH 匿名阅读数据层。认证/写操作将由未来的受控 Rust Host 实现。 */
export type FeedKind = "latest" | "top";
export interface Category { id: number; name: string; slug: string; topicCount: number; }
export interface Topic {
  id: number;
  slug: string;
  title: string;
  categoryId: number | null;
  views: number;
  postsCount: number;
  likeCount: number;
  tags: string[];
}
export interface Post { id: number; number: number; author: string; text: string; }
export interface TopicPage { items: Topic[]; hasMore: boolean; nextCursor: string | null; }
export interface TopicDetail { posts: Post[]; remainingIds: number[]; }
export interface SearchHit { topic: Topic; postNumber: number | null; excerpt: string; }
export interface SearchPage { items: SearchHit[]; hasMore: boolean; }
export const POSTS_PER_BATCH = 20;

const ORIGIN = "https://linux.do";
type JsonRecord = Record<string, unknown>;

function record(value: unknown, description: string): JsonRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(description + " 数据格式不正确");
  }
  return value as JsonRecord;
}
function asNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
function positiveId(value: unknown): number {
  const n = asNumber(value);
  return Number.isSafeInteger(n) && n > 0 ? n : 0;
}
function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}
export function decodeEntities(value: string): string {
  const known: Record<string,string> = {amp:"&",lt:"<",gt:">",quot:'"',apos:"'",nbsp:" "};
  return value.replace(/&(#(?:x[0-9a-f]+|[0-9]+)|[a-z]+);/gi, (source, raw: string) => {
    if (!raw.startsWith("#")) return known[raw.toLowerCase()] ?? source;
    const hex = raw[1]?.toLowerCase() === "x";
    const numeric = Number.parseInt(raw.slice(hex ? 2 : 1), hex ? 16 : 10);
    if (!Number.isInteger(numeric) || numeric < 0 || numeric > 0x10ffff ||
        (numeric >= 0xd800 && numeric <= 0xdfff)) return source;
    return String.fromCodePoint(numeric);
  });
}
/** 纯文本预览，禁止在 TSX 直接解析并执行 cooked HTML。 */
export function cookedToText(html: string): string {
  return decodeEntities(
    html.replace(/<(script|style|svg|iframe|object|template)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, "")
      .replace(/<br\s*\/?\s*>/gi, "\n")
      .replace(/<\/(?:p|div|li|blockquote|h[1-6])\s*>/gi, "\n")
      .replace(/<[^>]*>/g, "")
  ).replace(/\n{3,}/g, "\n\n").trim();
}
export function parseCategories(payload: unknown): Category[] {
  const root = record(payload, "分类");
  const group = record(root.category_list, "分类列表");
  if (!Array.isArray(group.categories)) throw new Error("分类列表字段缺失");
  return group.categories.map((item: unknown) => {
    const c = record(item, "分类");
    return {id: positiveId(c.id),name:decodeEntities(asString(c.name)),
      slug:asString(c.slug),topicCount:asNumber(c.topic_count)};
  }).filter((x: Category) => x.id > 0 && x.name.length > 0 && x.slug.length > 0);
}
/**
 * Discourse more_topics_url is the server's cursor (often without .json).
 * Strictly restrict it to known read-only feed routes on linux.do.
 * Never fetch a server-provided absolute URL from an arbitrary host.
 */
export function normalizeFeedCursor(value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0 || value.length > 2048) return null;
  let candidate = value.trim();
  if (candidate.startsWith(ORIGIN + "/")) candidate = candidate.slice(ORIGIN.length);
  if (!candidate.startsWith("/") || candidate.startsWith("//") ||
      /[\\\r\n#]/.test(candidate) || /%(?:2f|5c|0a|0d|00)/i.test(candidate)) return null;
  const queryAt = candidate.indexOf("?");
  if (queryAt <= 0) return null;
  const pathname = candidate.slice(0, queryAt);
  const query = candidate.slice(queryAt + 1);
  if (!/^(?:\/latest|\/top(?:\/weekly)?)(?:\.json)?$/.test(pathname) &&
      !/^\/c\/[^/?#\\]+\/[1-9]\d*(?:\/l\/latest)?(?:\.json)?$/.test(pathname)) return null;
  // Do not forward arbitrary query parameters supplied by the server: they
  // could alter the endpoint or contain opaque session/credential values.
  const seen = new Set<string>();
  let hasPagination = false;
  for (const segment of query.split("&")) {
    const match = /^(page|before|period)=([a-zA-Z0-9]+)$/.exec(segment);
    if (!match || seen.has(match[1])) return null;
    const [, key, raw] = match;
    seen.add(key);
    if (key === "period") {
      if (raw !== "weekly" || !/^\/top(?:\/weekly)?(?:\.json)?$/.test(pathname)) return null;
    } else {
      const number = Number(raw);
      if (!/^\d+$/.test(raw) || !Number.isSafeInteger(number) ||
          number < (key === "page" ? 0 : 1) ||
          (key === "page" && number > 1000)) return null;
      hasPagination = true;
    }
  }
  if (!hasPagination) return null;
  return (pathname.endsWith(".json") ? pathname : pathname + ".json") + "?" + query;
}

/** A server cursor must stay within the user's current feed and category. */
export function feedCursorForContext(
  value: unknown, kind: FeedKind, category: Category | null,
): string | null {
  const cursor = normalizeFeedCursor(value);
  if (!cursor) return null;
  const path = cursor.slice(0, cursor.indexOf("?"));
  if (category !== null) {
    if (!Number.isSafeInteger(category.id) || category.id <= 0 || !category.slug) return null;
    const prefix = "/c/" + encodeURIComponent(category.slug) + "/" + category.id;
    return path === prefix + ".json" || path === prefix + "/l/latest.json" ? cursor : null;
  }
  if (kind === "latest") return path === "/latest.json" ? cursor : null;
  if (kind === "top") {
    if (path === "/top/weekly.json") return cursor;
    if (path === "/top.json" && /(?:^|&)period=weekly(?:&|$)/.test(cursor.split("?")[1])) {
      return cursor;
    }
  }
  return null;
}

export function parseTopics(payload: unknown): TopicPage {
  const root = record(payload, "话题");
  const list = record(root.topic_list, "话题列表");
  if (!Array.isArray(list.topics)) throw new Error("话题列表字段缺失");
  const items: Topic[] = list.topics.map((item: unknown) => {
    const t = record(item, "话题");
    return {id:positiveId(t.id),slug:asString(t.slug),
      title:decodeEntities(asString(t.title)),
      categoryId: positiveId(t.category_id) || null,
      views:asNumber(t.views),postsCount:asNumber(t.posts_count),
      likeCount:asNumber(t.like_count),
      tags:Array.isArray(t.tags) ? t.tags.filter((x): x is string => typeof x === "string") : []};
  }).filter((t: Topic) => t.id > 0 && t.slug.length > 0 && t.title.length > 0);
  const nextCursor = normalizeFeedCursor(list.more_topics_url);
  return {items, hasMore: nextCursor !== null, nextCursor};
}
/** Search terms are explicit user input, never a server-supplied URL. */
export function searchPath(query: string, page: number): string {
  const cleaned = query.trim();
  if (cleaned.length < 2 || cleaned.length > 120 || /[\u0000-\u001f\u007f]/.test(cleaned)) {
    throw new Error("搜索词需要 2–120 个字符，且不能包含控制字符");
  }
  if (!Number.isSafeInteger(page) || page < 1 || page > 50) {
    throw new Error("搜索页码超出允许范围");
  }
  return "/search.json?q=" + encodeURIComponent(cleaned) + "&page=" + page;
}

/** Discourse search returns distinct topics and matching posts; topic fields are partial. */
export function parseSearchResults(payload: unknown): SearchPage {
  const root = record(payload, "搜索");
  if (!Array.isArray(root.topics) || !Array.isArray(root.posts)) {
    throw new Error("搜索结果字段缺失");
  }
  const topicById = new Map<number, Topic>();
  for (const value of root.topics) {
    const t = record(value, "搜索话题");
    const id = positiveId(t.id);
    if (!id || !asString(t.title)) continue;
    topicById.set(id, {
      id, slug: asString(t.slug) || "topic", title: decodeEntities(asString(t.title)),
      categoryId: positiveId(t.category_id) || null, views: asNumber(t.views),
      postsCount: asNumber(t.posts_count), likeCount: asNumber(t.like_count),
      tags: Array.isArray(t.tags)
        ? t.tags.filter((tag): tag is string => typeof tag === "string") : [],
    });
  }
  const hits: SearchHit[] = [];
  const seen = new Set<string>();
  const referencedTopics = new Set<number>();
  for (const value of root.posts) {
    const post = record(value, "搜索帖子");
    const topic = topicById.get(positiveId(post.topic_id));
    if (!topic) continue;
    const postNumber = positiveId(post.post_number) || null;
    const identity = topic.id + ":" + (positiveId(post.id) || postNumber || 0);
    if (seen.has(identity)) continue;
    seen.add(identity);
    referencedTopics.add(topic.id);
    hits.push({
      topic, postNumber,
      excerpt: cookedToText(asString(post.blurb)).slice(0, 300),
    });
  }
  for (const topic of topicById.values()) {
    if (!referencedTopics.has(topic.id)) hits.push({topic, postNumber: null, excerpt: ""});
  }
  const grouped = root.grouped_search_result;
  const summary = grouped && typeof grouped === "object" && !Array.isArray(grouped)
    ? grouped as JsonRecord : {};
  const more = summary.more_full_page_results;
  return {
    items: hits,
    hasMore: more === true || (typeof more === "string" && more.length > 0),
  };
}

export function mergeSearchHits(existing: SearchHit[], added: SearchHit[]): SearchHit[] {
  const seen = new Set(existing.map((hit) => hit.topic.id + ":" + (hit.postNumber || 0)));
  const result = [...existing];
  for (const hit of added) {
    const key = hit.topic.id + ":" + (hit.postNumber || 0);
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(hit);
  }
  return result;
}

export function parsePosts(payload: unknown): Post[] {
  const root = record(payload, "详情");
  const stream = record(root.post_stream, "帖子流");
  if (!Array.isArray(stream.posts)) throw new Error("帖子流字段缺失");
  return stream.posts.map((item: unknown) => {
    const p = record(item, "帖子");
    return {id:positiveId(p.id),number:positiveId(p.post_number),
      author:asString(p.username) || "匿名用户",
      text:cookedToText(asString(p.cooked)).slice(0, 4000)};
  }).filter((p: Post) => p.id > 0);
}
/** The first response embeds some posts; post_stream.stream contains IDs of the rest. */
export function parseTopicDetail(payload: unknown): TopicDetail {
  const root = record(payload, "详情");
  const stream = record(root.post_stream, "帖子流");
  const posts = parsePosts(payload);
  const loadedIds = new Set(posts.map((p) => p.id));
  const queued = new Set<number>();
  const remainingIds: number[] = [];
  if (Array.isArray(stream.stream)) {
    for (const rawId of stream.stream) {
      const id = positiveId(rawId);
      if (id && !loadedIds.has(id) && !queued.has(id)) {
        queued.add(id);
        remainingIds.push(id);
      }
    }
  }
  return {posts, remainingIds};
}

/** Limit each Discourse request to 20 post IDs; keep identifiers out of URL paths. */
export function postsBatchPath(topic: Topic, ids: number[]): string {
  if (!Number.isSafeInteger(topic.id) || topic.id <= 0) throw new Error("话题 ID 无效");
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > POSTS_PER_BATCH ||
      ids.some((id) => !Number.isSafeInteger(id) || id <= 0)) {
    throw new Error("帖子批次 ID 无效");
  }
  const unique = [...new Set(ids)];
  return "/t/" + topic.id + "/posts.json?" +
    unique.map((id) => "post_ids%5B%5D=" + id).join("&");
}

/** Deduplicate overlapping post batches and restore Discourse post-number order. */
export function mergePosts(existing: Post[], incoming: Post[]): Post[] {
  const merged = new Map(existing.map((post) => [post.id, post]));
  for (const post of incoming) merged.set(post.id, post);
  return [...merged.values()].sort((a, b) => a.number - b.number || a.id - b.id);
}

export function dedupeTopics(existing: Topic[], added: Topic[]): Topic[] {
  const seen = new Set(existing.map((t) => t.id));
  const merged = [...existing];
  for (const topic of added) {
    if (seen.has(topic.id)) continue;
    seen.add(topic.id);
    merged.push(topic);
  }
  return merged;
}
export function compactCount(value: number): string {
  return value >= 10000 ? (value / 10000).toFixed(1) + "万" : String(value);
}
export function feedPath(kind: FeedKind, category: Category | null, page: number): string {
  if (!Number.isSafeInteger(page) || page < 0 || page > 1000) throw new Error("页码超出允许范围");
  if (kind === "top" && category === null) return "/top.json?period=weekly&page=" + page;
  if (category !== null) {
    if (!Number.isSafeInteger(category.id) || category.id <= 0) throw new Error("分类 ID 无效");
    return "/c/" + encodeURIComponent(category.slug) + "/" + category.id + ".json?page=" + page;
  }
  return "/latest.json?page=" + page;
}
/** Optional post_number requests Discourse's reading window near that floor. */
export function topicPath(topic: Topic, postNumber?: number | null): string {
  if (!Number.isSafeInteger(topic.id) || topic.id <= 0) throw new Error("话题 ID 无效");
  if (postNumber != null &&
      (!Number.isSafeInteger(postNumber) || postNumber <= 0 || postNumber > 10000000)) {
    throw new Error("楼层号无效");
  }
  return "/t/" + encodeURIComponent(topic.slug) + "/" + topic.id +
    (postNumber == null ? "" : "/" + postNumber) + ".json";
}
export interface PublicReader {
  categories(): Promise<Category[]>;
  topics(kind: FeedKind, category: Category | null, pageOrCursor: number | string): Promise<TopicPage>;
  posts(topic: Topic): Promise<Post[]>;
  detail(topic: Topic, postNumber?: number | null): Promise<TopicDetail>;
  morePosts(topic: Topic, ids: number[]): Promise<Post[]>;
  search(query: string, page: number): Promise<SearchPage>;
}
export function createPublicReader(
  get: (path: string) => Promise<unknown>,
): PublicReader {
  return {
    async categories() { return parseCategories(await get("/categories.json")); },
    async topics(kind, category, pageOrCursor) {
      const path = typeof pageOrCursor === "number"
        ? feedPath(kind, category, pageOrCursor) : normalizeFeedCursor(pageOrCursor);
      if (!path) throw new Error("分页游标无效");
      const result = parseTopics(await get(path));
      const nextCursor = feedCursorForContext(result.nextCursor, kind, category);
      return { ...result, nextCursor, hasMore: nextCursor !== null };
    },
    async posts(topic) { return parsePosts(await get(topicPath(topic))); },
    async detail(topic, postNumber) {
      return parseTopicDetail(await get(topicPath(topic, postNumber)));
    },
    async morePosts(topic, ids) { return parsePosts(await get(postsBatchPath(topic, ids))); },
    async search(query, page) { return parseSearchResults(await get(searchPath(query, page))); },
  };
}
async function getPublicJson(path: string): Promise<unknown> {
  // 只接受本代码构造出的站内绝对路径；严禁 JS UI 动态转发凭据。
  if (!path.startsWith("/") || path.startsWith("//")) throw new Error("请求路径无效");
  // Public-only transport: never attach ambient cookies or follow cross-origin redirects.
  const response = await fetch(ORIGIN + path, {
    headers: { Accept: "application/json" },
    credentials: "omit",
    redirect: "error",
  });
  if (!response.ok) throw new Error("公开接口 HTTP " + response.status);
  return response.json();
}
export const publicReader = createPublicReader(getPublicJson);
