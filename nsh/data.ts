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
export interface TopicPage { items: Topic[]; hasMore: boolean; }

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
  return {items,hasMore:typeof list.more_topics_url === "string" && list.more_topics_url.length > 0};
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
export function topicPath(topic: Topic): string {
  if (!Number.isSafeInteger(topic.id) || topic.id <= 0) throw new Error("话题 ID 无效");
  return "/t/" + encodeURIComponent(topic.slug) + "/" + topic.id + ".json";
}
export interface PublicReader {
  categories(): Promise<Category[]>;
  topics(kind: FeedKind, category: Category | null, page: number): Promise<TopicPage>;
  posts(topic: Topic): Promise<Post[]>;
}
export function createPublicReader(
  get: (path: string) => Promise<unknown>,
): PublicReader {
  return {
    async categories() { return parseCategories(await get("/categories.json")); },
    async topics(kind, category, page) {
      return parseTopics(await get(feedPath(kind, category, page)));
    },
    async posts(topic) { return parsePosts(await get(topicPath(topic))); },
  };
}
async function getPublicJson(path: string): Promise<unknown> {
  // 只接受本代码构造出的站内绝对路径；严禁 JS UI 动态转发凭据。
  if (!path.startsWith("/") || path.startsWith("//")) throw new Error("请求路径无效");
  const response = await fetch(ORIGIN + path, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error("公开接口 HTTP " + response.status);
  return response.json();
}
export const publicReader = createPublicReader(getPublicJson);
