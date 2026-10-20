/** Fluxdo NSH 匿名阅读数据层。认证/写操作将由未来的受控 Rust Host 实现。 */
export type FeedKind = "latest" | "top";
export interface Category { id: number; name: string; slug: string; topicCount: number; }
export interface Tag { id: number; name: string; slug: string; topicCount: number; description: string; }
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
export interface PublicUserProfile {
  id: number;
  username: string;
  name: string;
  title: string;
  bio: string;
  trustLevel: number;
  postCount: number;
}
export interface BoardSummary {
  id: number;
  name: string;
  slug: string;
  anonymousCanRead: boolean;
  columnCount: number;
}
export interface BoardCard {
  id: number;
  kind: "topic" | "note";
  title: string;
  notes: string;
  topic: Topic | null;
}
export interface BoardColumn { id: number; title: string; cards: BoardCard[]; }
export interface BoardDetail {
  board: BoardSummary;
  columns: BoardColumn[];
  truncated: boolean;
}
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
/** Discourse /tags.json returns a flat array with localized tag names and synonyms. */
export function parseTags(payload: unknown): Tag[] {
  const root = record(payload, "标签目录");
  if (!Array.isArray(root.tags)) throw new Error("标签目录字段缺失");
  const seen = new Set<number>();
  const tags: Tag[] = [];
  for (const item of root.tags) {
    const t = record(item, "标签");
    const target = t.target_tag && typeof t.target_tag === "object" && !Array.isArray(t.target_tag);
    if (target) continue; // Do not expose non-canonical synonym links.
    const id = positiveId(t.id);
    const name = decodeEntities(asString(t.text) || asString(t.name)).trim();
    const slug = asString(t.slug);
    if (!id || !name || !slug || slug === "." || slug === ".." ||
        seen.has(id) || slug.length > 120 || /[\\/\u0000-\u001f\u007f]/.test(slug)) continue;
    seen.add(id);
    tags.push({
      id, name: name.slice(0, 120), slug,
      topicCount: Math.max(0, asNumber(t.count)),
      description: cookedToText(asString(t.description)).slice(0, 300),
    });
    if (tags.length >= 1000) break;
  }
  return tags.sort((a,b) => b.topicCount - a.topicCount || a.name.localeCompare(b.name));
}

/** Canonical Discourse /tag/:slug/:id.json, scoped to an explicit tag. */
export function tagPath(tag: Tag, page: number): string {
  if (!Number.isSafeInteger(tag.id) || tag.id <= 0 ||
      !tag.slug || tag.slug === "." || tag.slug === ".." ||
      tag.slug.length > 120 || /[\\/\u0000-\u001f\u007f]/.test(tag.slug)) {
    throw new Error("标签 ID 或 slug 无效");
  }
  if (!Number.isSafeInteger(page) || page < 0 || page > 1000) throw new Error("页码超出允许范围");
  return "/tag/" + encodeURIComponent(tag.slug) + "/" + tag.id + ".json?page=" + page;
}
export function tagCursorForContext(value: unknown, tag: Tag): string | null {
  const candidate = normalizeFeedCursor(value);
  if (!candidate) return null;
  const expected = tagPath(tag, 0).split("?")[0];
  return candidate.slice(0, candidate.indexOf("?")) === expected ? candidate : null;
}

/**
 * Official Discourse category + tag route:
 * GET /tags/c/:category_slug/:category_id/:tag_slug/:tag_id.json
 * All identifiers come from public index entries and are validated before IO.
 * Nested category slug paths are not supported by the current flat Category model.
 */
export function categoryTagPath(category: Category, tag: Tag, page: number): string {
  if (!category.slug || category.slug === "." || category.slug === ".." ||
      category.slug.length > 120 || /[\\/\u0000-\u001f\u007f]/.test(category.slug)) {
    throw new Error("分类 slug 无效");
  }
  const categoryPath = feedPath("latest", category, page).split("?")[0];
  const tagRoute = tagPath(tag, page).slice("/tag/".length);
  return "/tags" + categoryPath.slice(0, -".json".length) + "/" + tagRoute;
}

export function categoryTagCursorForContext(
  value: unknown, category: Category, tag: Tag,
): string | null {
  const cursor = normalizeFeedCursor(value);
  if (!cursor) return null;
  const pathname = cursor.slice(0, cursor.indexOf("?"));
  return pathname === categoryTagPath(category, tag, 0).split("?")[0] ? cursor : null;
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
      !/^\/c\/[^/?#\\]+\/[1-9]\d*(?:\/l\/latest)?(?:\.json)?$/.test(pathname) &&
      !/^\/tag\/[^/?#\\]+\/[1-9]\d*(?:\.json)?$/.test(pathname) &&
      !/^\/tags\/c\/[^/?#\\]+\/[1-9]\d*\/[^/?#\\]+\/[1-9]\d*(?:\.json)?$/.test(pathname)) return null;
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

/** Only explicit public fields are exposed to the view layer. */
export function parseUserProfile(payload: unknown): PublicUserProfile {
  const root = record(payload, "用户资料");
  const user = record(root.user, "用户资料");
  const id = positiveId(user.id);
  const username = asString(user.username);
  if (!id || !username) throw new Error("用户资料字段缺失");
  const trustLevel = asNumber(user.trust_level);
  return {
    id, username,
    name: decodeEntities(asString(user.name)),
    title: decodeEntities(asString(user.title)),
    bio: cookedToText(asString(user.bio_cooked) || asString(user.bio_excerpt)).slice(0, 2000),
    trustLevel: Number.isSafeInteger(trustLevel) && trustLevel >= 0 ? trustLevel : 0,
    postCount: Math.max(0, asNumber(user.post_count)),
  };
}
/** Restrict public profile lookup to a single username segment. */
export function userProfilePath(value: string): string {
  const username = value.trim().replace(/^@/, "");
  if (!/^[a-zA-Z0-9_.-]{1,60}$/.test(username) ||
      username === "." || username === "..") {
    throw new Error("用户名格式无效（仅支持 1–60 位字母、数字、下划线、点或连字符）");
  }
  return "/u/" + encodeURIComponent(username) + ".json";
}

/** Discourse Boards official index; only public metadata is projected. */
export function parseBoards(payload: unknown): BoardSummary[] {
  const root = record(payload, "看板目录");
  if (!Array.isArray(root.boards)) throw new Error("看板目录字段缺失");
  const ids = new Set<number>();
  const boards: BoardSummary[] = [];
  for (const raw of root.boards) {
    const b = record(raw, "看板");
    const id = positiveId(b.id);
    const name = decodeEntities(asString(b.unicode_name) || asString(b.name));
    if (!id || !name || b.archived === true || ids.has(id)) continue;
    ids.add(id);
    boards.push({
      id, name: name.slice(0, 160), slug: asString(b.slug),
      anonymousCanRead: b.anonymous_can_read === true,
      columnCount: Array.isArray(b.columns) ? b.columns.length : 0,
    });
    // Keep a finite in-memory index until the native virtualized directory ships.
    if (boards.length >= 100) break;
  }
  return boards;
}

/** Parse GET /boards/api/boards/:id.json (columns are a top-level sibling).
 * Limit untrusted payload size at the view-model boundary. */
export function parseBoardDetail(payload: unknown, expectedId: number): BoardDetail {
  if (!Number.isSafeInteger(expectedId) || expectedId <= 0) throw new Error("看板 ID 无效");
  const root = record(payload, "看板详情");
  const rawBoard = record(root.board, "看板详情");
  if (positiveId(rawBoard.id) !== expectedId || rawBoard.anonymous_can_read !== true) {
    throw new Error("看板不可公开访问");
  }
  if (!Array.isArray(root.columns)) throw new Error("看板栏目字段缺失");
  const board = parseBoards({boards: [rawBoard]})[0];
  if (!board) throw new Error("看板数据无效");
  const columns: BoardColumn[] = [];
  const columnIds = new Set<number>();
  const cardIds = new Set<number>();
  let cardBudget = 500;
  let truncated = root.columns.length > 30;
  for (const value of root.columns.slice(0, 30)) {
    const column = record(value, "看板栏目");
    const id = positiveId(column.id);
    if (!id || columnIds.has(id)) continue;
    columnIds.add(id);
    const rawCards = Array.isArray(column.cards) ? column.cards : [];
    const cards: BoardCard[] = [];
    for (const value of rawCards) {
      if (cardBudget <= 0) { truncated = true; break; }
      const card = record(value, "看板卡片");
      const cardId = positiveId(card.id);
      if (!cardId || cardIds.has(cardId)) continue;
      const kind = asString(card.card_type);
      if (kind !== "topic" && kind !== "floater") continue;
      let topic: Topic | null = null;
      if (kind === "topic") {
        if (!card.topic || typeof card.topic !== "object" || Array.isArray(card.topic)) continue;
        const t = card.topic as JsonRecord;
        const topicId = positiveId(t.id);
        const slug = asString(t.slug);
        if (!topicId || !slug) continue;
        topic = {
          id: topicId, slug,
          title: decodeEntities(asString(t.unicode_title) || asString(t.title)).slice(0, 250),
          categoryId: positiveId(t.category_id) || null,
          views: 0, likeCount: 0, postsCount: Math.max(0, asNumber(t.posts_count)),
          tags: Array.isArray(t.tags)
            ? t.tags.filter((x): x is string => typeof x === "string").slice(0, 10) : [],
        };
      }
      cardIds.add(cardId);
      cardBudget--;
      cards.push({
        id: cardId, kind: kind === "topic" ? "topic" : "note",
        title: topic?.title || decodeEntities(asString(card.unicode_title) || asString(card.title)).slice(0, 250),
        notes: cookedToText(asString(card.notes)).slice(0, 1200),
        topic,
      });
    }
    columns.push({
      id, title: decodeEntities(asString(column.unicode_title) || asString(column.title)).slice(0, 160),
      cards,
    });
  }
  return {board, columns, truncated};
}

/** Only numeric IDs may be used to build Boards detail paths. */
export function boardDetailPath(id: number): string {
  if (!Number.isSafeInteger(id) || id <= 0) throw new Error("看板 ID 无效");
  return "/boards/api/boards/" + id + ".json";
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
  tags(): Promise<Tag[]>;
  tagTopics(tag: Tag, pageOrCursor: number | string): Promise<TopicPage>;
  categoryTagTopics(category: Category, tag: Tag, pageOrCursor: number | string): Promise<TopicPage>;
  topics(kind: FeedKind, category: Category | null, pageOrCursor: number | string): Promise<TopicPage>;
  posts(topic: Topic): Promise<Post[]>;
  detail(topic: Topic, postNumber?: number | null): Promise<TopicDetail>;
  morePosts(topic: Topic, ids: number[]): Promise<Post[]>;
  search(query: string, page: number): Promise<SearchPage>;
  profile(username: string): Promise<PublicUserProfile>;
  boards(): Promise<BoardSummary[]>;
  board(board: BoardSummary): Promise<BoardDetail>;
}
export function createPublicReader(
  get: (path: string) => Promise<unknown>,
): PublicReader {
  return {
    async categories() { return parseCategories(await get("/categories.json")); },
    async tags() { return parseTags(await get("/tags.json")); },
    async categoryTagTopics(category, tag, pageOrCursor) {
      const path = typeof pageOrCursor === "number"
        ? categoryTagPath(category, tag, pageOrCursor)
        : categoryTagCursorForContext(pageOrCursor, category, tag);
      if (!path) throw new Error("分类标签分页游标无效");
      const result = parseTopics(await get(path));
      const nextCursor = categoryTagCursorForContext(result.nextCursor, category, tag);
      return {...result, nextCursor, hasMore: nextCursor !== null};
    },
    async tagTopics(tag, pageOrCursor) {
      const path = typeof pageOrCursor === "number"
        ? tagPath(tag,pageOrCursor) : tagCursorForContext(pageOrCursor,tag);
      if (!path) throw new Error("标签分页游标无效");
      const result = parseTopics(await get(path));
      const nextCursor = tagCursorForContext(result.nextCursor,tag);
      return {...result,nextCursor,hasMore:nextCursor !== null};
    },
    async topics(kind, category, pageOrCursor) {
      const path = typeof pageOrCursor === "number"
        ? feedPath(kind, category, pageOrCursor)
        : feedCursorForContext(pageOrCursor, kind, category);
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
    async profile(username) { return parseUserProfile(await get(userProfilePath(username))); },
    async boards() { return parseBoards(await get("/boards/api/boards.json")); },
    async board(board) {
      if (!board.anonymousCanRead) throw new Error("当前看板需要登录后访问");
      return parseBoardDetail(await get(boardDetailPath(board.id)), board.id);
    },
  };
}
export type PublicReadErrorCode =
  "challenge" | "forbidden" | "not_found" | "http" | "network" | "invalid_content";
/**
 * Present only stable, credential-free error codes/messages to NSH TSX.
 * In particular, a 403 here is NOT evidence that any stored account is invalid.
 */
export class PublicReadError extends Error {
  readonly code: PublicReadErrorCode;
  readonly status: number | null;
  constructor(code: PublicReadErrorCode, message: string, status: number | null = null) {
    super(message);
    this.name = "PublicReadError";
    this.code = code;
    this.status = status;
  }
}
async function getPublicJson(path: string): Promise<unknown> {
  // Only code-generated root-relative API URLs may reach the anonymous adapter.
  if (!path.startsWith("/") || path.startsWith("//") ||
      /[\\\r\n#]/.test(path)) throw new Error("请求路径无效");
  let response: Response;
  try {
    response = await fetch(ORIGIN + path, {
      headers: { Accept: "application/json" },
      credentials: "omit",
      redirect: "error",
    });
  } catch {
    // Do not leak untrusted native/network exceptions or cookie-bearing URLs to UI.
    throw new PublicReadError("network", "公开请求网络连接失败或访问受到限制");
  }
  const challenge = response.headers?.get("cf-mitigated")?.toLowerCase() === "challenge";
  const contentType = response.headers?.get("content-type")?.toLowerCase() ?? "";
  if (challenge || (response.status === 403 && contentType.includes("text/html"))) {
    throw new PublicReadError(
      "challenge", "公开接口触发访问验证，请在浏览器完成验证后再重试", response.status,
    );
  }
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      throw new PublicReadError(
        "forbidden", "当前内容需要登录或没有匿名访问权限", response.status,
      );
    }
    if (response.status === 404) {
      throw new PublicReadError("not_found", "公开接口或内容不存在", response.status);
    }
    throw new PublicReadError("http", "公开接口暂时不可用（HTTP " + response.status + "）", response.status);
  }
  if (contentType && !contentType.includes("application/json") &&
      !contentType.includes("+json")) {
    throw new PublicReadError("invalid_content", "公开接口未返回 JSON 数据");
  }
  try {
    return await response.json();
  } catch {
    throw new PublicReadError("invalid_content", "公开接口返回的数据不是有效 JSON");
  }
}
export const publicReader = createPublicReader(getPublicJson);
