import { Input, mount, Scroll, signal, Text, View } from "nsh";
import { colorScheme, Platform, windowSize } from "nsh/device";
import { List } from "nsh/list";
import { createNavigator, SafeAreaView, Screen, Stack, StatusBar } from "nsh/ui/mobile";
import {
  compactCount, dedupeTopics, mergePosts, mergeSearchHits, POSTS_PER_BATCH, publicReader,
  type Category, type FeedKind, type Post, type SearchHit, type Topic,
} from "./data";
import { RequestGate } from "./request_gate";

/**
 * Native Shell 正式迁移目录的第一个独立入口。
 * 当前只读、匿名，不使用 Flutter Cookie 或 JS 凭据。
 */
type Tab = "latest" | "top" | "categories" | "search" | "about";
type Route = { name: "home" } | { name: "topic" };
const nav = createNavigator<Route>({ name: "home" });

const palette = {
  get background() { return colorScheme() === "dark" ? "#111722" : "#f4f7fc"; },
  get surface() { return colorScheme() === "dark" ? "#1b2535" : "#ffffff"; },
  get raised() { return colorScheme() === "dark" ? "#283650" : "#e8edff"; },
  get border() { return colorScheme() === "dark" ? "#35435a" : "#e3eaf4"; },
  get text() { return colorScheme() === "dark" ? "#edf2ff" : "#1f293f"; },
  get muted() { return colorScheme() === "dark" ? "#9baac0" : "#6f7e97"; },
  get accent() { return colorScheme() === "dark" ? "#9badff" : "#5269d8"; },
  get onAccent() { return colorScheme() === "dark" ? "#111722" : "#ffffff"; },
  get danger() { return colorScheme() === "dark" ? "#ffacb0" : "#b5474e"; },
};
const cardStyle = () => ({
  backgroundColor: palette.surface, borderWidth: 1, borderColor: palette.border,
  borderRadius: 16, padding: 15, gap: 9,
});

function Chip(props: { label: string; onPress: () => void; active?: () => boolean }) {
  const selected = () => props.active?.() ?? false;
  return (
    <View
      accessibilityRole="button"
      accessibilityLabel={props.label}
      accessibilityState={{ selected: selected() }}
      onPress={props.onPress}
      activeOpacity={0.7}
      style={{
        minHeight: 40, justifyContent: "center", alignItems: "center",
        borderRadius: 11, paddingHorizontal: 13, paddingVertical: 9,
        backgroundColor: selected() ? palette.accent : palette.raised,
      }}
    >
      <Text style={{
        fontSize: 13, fontWeight: "600",
        color: selected() ? palette.onAccent : palette.accent,
      }}>{props.label}</Text>
    </View>
  );
}

function ErrorView(props: { message: () => string; retry: () => void }) {
  return (
    <If when={props.message().length > 0}>
      <View style={{ ...cardStyle(), backgroundColor: palette.surface, marginHorizontal: 14 }}>
        <Text style={{ color: palette.danger, fontSize: 13 }}>{props.message()}</Text>
        <Text onPress={props.retry} accessibilityRole="button"
          style={{ color: palette.accent, fontSize: 13, fontWeight: "600" }}>重试加载</Text>
      </View>
    </If>
  );
}

function TopicRow(props: { topic: () => Topic; onOpen: (topic: Topic) => void }) {
  return (
    <View
      accessibilityRole="button"
      accessibilityLabel={props.topic().title}
      onPress={() => props.onOpen(props.topic())}
      activeOpacity={0.7}
      style={cardStyle()}
    >
      <Text style={{ color: palette.text, fontWeight: "600", fontSize: 16, lineHeight: 24 }}
        numberOfLines={2}>{props.topic().title}</Text>
      <If when={props.topic().tags.length > 0}>
        <Text style={{ color: palette.accent, fontSize: 12 }} numberOfLines={1}>
          {props.topic().tags.slice(0, 4).map((t) => "#" + t).join("  ")}
        </Text>
      </If>
      <View style={{ flexDirection: "row", gap: 14, alignItems: "center" }}>
        <Text style={{ color: palette.muted, fontSize: 12 }}>
          浏览 {compactCount(props.topic().views)}
        </Text>
        <Text style={{ color: palette.muted, fontSize: 12 }}>
          回复 {Math.max(0, props.topic().postsCount - 1)}
        </Text>
        <Text style={{ color: palette.muted, fontSize: 12 }}>
          赞 {compactCount(props.topic().likeCount)}
        </Text>
      </View>
    </View>
  );
}

function FeedPage(props: {
  kind: () => FeedKind;
  category: () => Category | null;
  clearCategory: () => void;
  topics: () => Topic[];
  loading: () => boolean;
  loadingMore: () => boolean;
  hasMore: () => boolean;
  error: () => string;
  refresh: () => void;
  loadMore: () => void;
  open: (topic: Topic) => void;
}) {
  const search = signal("");
  const rows = () => {
    const term = search().trim().toLocaleLowerCase();
    if (!term) return props.topics();
    return props.topics().filter((t) => t.title.toLocaleLowerCase().includes(term) ||
      t.tags.some((tag) => tag.toLocaleLowerCase().includes(term)));
  };
  return (
    <View style={{ flex: 1, gap: 8 }}>
      <View style={{ paddingHorizontal: 14, paddingTop: 13, gap: 10 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 9 }}>
          <Text style={{ flex: 1, fontSize: 21, fontWeight: "700", color: palette.text }}>
            {props.category()?.name ?? (props.kind() === "latest" ? "最新话题" : "本周热门")}
          </Text>
          <Chip label="刷新 ↻" onPress={props.refresh} />
        </View>
        <If when={props.category() !== null}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 9 }}>
            <Text style={{ flex: 1, color: palette.muted, fontSize: 12 }}>当前正在浏览分类话题</Text>
            <Chip label="全部话题 ×" onPress={props.clearCategory} />
          </View>
        </If>
        <Input
          value={search()}
          onChangeText={(text) => search.set(text)}
          placeholder="在已加载的话题中搜索"
          returnKeyType="search"
          style={{
            fontSize: 14, color: palette.text, backgroundColor: palette.surface,
            borderWidth: 1, borderColor: palette.border,
            borderRadius: 12, paddingHorizontal: 13, paddingVertical: 11,
          }}
        />
        <Text style={{ color: palette.muted, fontSize: 12 }}>
          {props.loading() ? "正在读取公开数据…" : "已加载 " + props.topics().length + " 个话题"}
        </Text>
      </View>
      <ErrorView message={props.error} retry={props.refresh} />
      <List
        each={rows()}
        keyExtractor={(t) => String(t.id)}
        estimatedItemSize={119}
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: 14, paddingBottom: 18, gap: 9 }}
        refreshing={props.loading()}
        onRefresh={props.refresh}
        ListEmptyComponent={
          <View style={{ padding: 25, alignItems: "center", gap: 7 }}>
            <Text style={{ color: palette.text, fontSize: 15 }}>
              {props.loading() ? "正在加载" : "当前没有可显示的话题"}
            </Text>
            <Text style={{ color: palette.muted, fontSize: 12 }}>试试刷新或清空筛选</Text>
          </View>
        }
        ListFooterComponent={
          <If when={!search().trim() && props.topics().length > 0}>
            <View style={{ alignItems: "center", paddingVertical: 12 }}>
              <If when={props.hasMore()} else={
                <Text style={{ color: palette.muted, fontSize: 12 }}>已到达当前列表末尾</Text>
              }>
                <Chip label={props.loadingMore() ? "正在加载…" : "加载更多"}
                  onPress={props.loadMore} />
              </If>
            </View>
          </If>
        }
      >
        {(item) => <TopicRow topic={item} onOpen={props.open} />}
      </List>
    </View>
  );
}

function CategoriesPage(props: {
  categories: () => Category[];
  loading: () => boolean;
  error: () => string;
  refresh: () => void;
  select: (category: Category) => void;
}) {
  return (
    <View style={{ flex: 1, gap: 10 }}>
      <View style={{ flexDirection: "row", paddingHorizontal: 16, paddingTop: 13, alignItems: "center" }}>
        <Text style={{ fontSize: 21, flex: 1, color: palette.text, fontWeight: "700" }}>分类目录</Text>
        <Chip label="刷新 ↻" onPress={props.refresh} />
      </View>
      <ErrorView message={props.error} retry={props.refresh} />
      <List
        each={props.categories()}
        keyExtractor={(c) => String(c.id)}
        estimatedItemSize={75}
        style={{ flex: 1 }}
        refreshing={props.loading()}
        onRefresh={props.refresh}
        contentContainerStyle={{ paddingHorizontal: 14, gap: 8, paddingBottom: 22 }}
        ListEmptyComponent={
          <Text style={{ color: palette.muted, textAlign: "center", padding: 22 }}>
            {props.loading() ? "正在载入分类…" : "没有可显示的分类"}
          </Text>
        }
      >
        {(item) => (
          <View onPress={() => props.select(item())}
            accessibilityRole="button"
            accessibilityLabel={"分类：" + item().name}
            style={{ ...cardStyle(), flexDirection: "row", alignItems: "center" }}
          >
            <View style={{ flex: 1, gap: 5 }}>
              <Text style={{ color: palette.text, fontSize: 16, fontWeight: "600" }}>{item().name}</Text>
              <Text style={{ color: palette.muted, fontSize: 12 }}>
                话题 {compactCount(item().topicCount)}
              </Text>
            </View>
            <Text style={{ color: palette.accent, fontSize: 18 }}>›</Text>
          </View>
        )}
      </List>
    </View>
  );
}

function SearchPage(props: {
  query: () => string;
  changeQuery: (text: string) => void;
  submit: () => void;
  hits: () => SearchHit[];
  submitted: () => boolean;
  loading: () => boolean;
  loadingMore: () => boolean;
  hasMore: () => boolean;
  error: () => string;
  retry: () => void;
  loadMore: () => void;
  open: (topic: Topic, postNumber: number | null) => void;
}) {
  return (
    <View style={{ flex: 1, gap: 9 }}>
      <View style={{ paddingHorizontal: 14, paddingTop: 13, gap: 10 }}>
        <Text style={{ fontSize: 21, fontWeight: "700", color: palette.text }}>全站公开搜索</Text>
        <Input
          value={props.query()}
          onChangeText={props.changeQuery}
          placeholder="搜索公开话题与帖子"
          returnKeyType="search"
          style={{
            fontSize: 14, color: palette.text, backgroundColor: palette.surface,
            borderWidth: 1, borderColor: palette.border, borderRadius: 12,
            paddingHorizontal: 13, paddingVertical: 11,
          }}
        />
        <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
          <Chip label={props.loading() ? "搜索中…" : "搜索"} onPress={props.submit} />
          <Text style={{ color: palette.muted, fontSize: 12, flex: 1 }}>
            {props.submitted() ? "已找到 " + props.hits().length + " 条匹配结果" :
              "输入关键字后点击搜索；仅查询公开内容"}
          </Text>
        </View>
      </View>
      <ErrorView message={props.error} retry={props.retry} />
      <List
        each={props.hits()}
        keyExtractor={(hit) => hit.topic.id + ":" + (hit.postNumber || 0)}
        estimatedItemSize={155}
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: 14, paddingBottom: 20, gap: 9 }}
        refreshing={props.loading()}
        onRefresh={props.submit}
        ListEmptyComponent={
          <View style={{ padding: 28, alignItems: "center", gap: 8 }}>
            <Text style={{ color: palette.text, fontSize: 15 }}>
              {props.loading() ? "正在搜索…" :
                props.submitted() ? "没有找到可公开阅读的匹配结果" : "输入关键字开始搜索"}
            </Text>
            <Text style={{ color: palette.muted, fontSize: 12, textAlign: "center" }}>
              仅搜索 Linux.do 的公开内容，不会发送 Cookie 或 API Key
            </Text>
          </View>
        }
        ListFooterComponent={
          <If when={props.hasMore() && props.hits().length > 0}>
            <View style={{ padding: 12, alignItems: "center" }}>
              <Chip label={props.loadingMore() ? "正在加载…" : "加载更多匹配"}
                onPress={props.loadMore} />
            </View>
          </If>
        }
      >
        {(item) => (
          <View
            onPress={() => props.open(item().topic, item().postNumber)}
            accessibilityRole="button"
            accessibilityLabel={"打开话题：" + item().topic.title}
            style={cardStyle()}
          >
            <Text style={{ fontSize: 16, fontWeight: "600", color: palette.text }}
              numberOfLines={2}>{item().topic.title}</Text>
            <If when={item().postNumber !== null}>
              <Text style={{ color: palette.accent, fontSize: 12 }}>
                匹配帖子 #{item().postNumber}
              </Text>
            </If>
            <If when={item().excerpt.length > 0}>
              <Text style={{ color: palette.muted, fontSize: 13, lineHeight: 20 }}
                numberOfLines={3}>{item().excerpt}</Text>
            </If>
          </View>
        )}
      </List>
    </View>
  );
}

function InfoPage() {
  return (
    <Scroll style={{ flex: 1 }} contentContainerStyle={{ padding: 18, gap: 15 }}>
      <Text style={{ fontSize: 22, fontWeight: "700", color: palette.text }}>Fluxdo · NSH 迁移版</Text>
      <View style={cardStyle()}>
        <Text style={{ fontSize: 16, fontWeight: "600", color: palette.text }}>独立原生 UI 开发预览</Text>
        <Text style={{ fontSize: 14, lineHeight: 21, color: palette.muted }}>
          当前支持 Linux.do 公开信息流、分类、搜索及话题纯文本阅读。
          账户登录、回复、附件上传、Chat 与设置尚未迁移，旧 Flutter 正式版继续提供这些功能。
        </Text>
      </View>
      <View style={cardStyle()}>
        <Text style={{ color: palette.text, fontSize: 15, fontWeight: "600" }}>运行环境</Text>
        <Text style={{ color: palette.muted, fontSize: 13 }}>NSH / {Platform.OS}</Text>
        <Text style={{ color: palette.muted, fontSize: 13 }}>
          视图宽度 {Math.round(windowSize().width)} pt
        </Text>
        <Text style={{ color: palette.muted, fontSize: 13 }}>
          主题：{colorScheme() === "dark" ? "深色" : "浅色 / 系统"}
        </Text>
      </View>
      <View style={cardStyle()}>
        <Text style={{ fontSize: 15, color: palette.text, fontWeight: "600" }}>安全边界</Text>
        <Text style={{ fontSize: 13, lineHeight: 20, color: palette.muted }}>
          TSX 不接收 Cookie / API Key，也不执行 Discourse cooked HTML。
          后续写入与多账户功能必须通过受控 Host Bridge，不直接访问旧 Flutter 的安全存储。
        </Text>
      </View>
    </Scroll>
  );
}

function DetailPane(props: {
  topic: () => Topic | null;
  posts: () => Post[];
  targetPostNumber: () => number | null;
  showBeginning: () => void;
  loading: () => boolean;
  loadingMore: () => boolean;
  remaining: () => number;
  loadMore: () => void;
  moreError: () => string;
  error: () => string;
  retry: () => void;
  close?: () => void;
}) {
  return (
    <View style={{ flex: 1 }}>
      <If when={props.topic() !== null} else={
        <View style={{ flex: 1, justifyContent: "center", alignItems: "center", padding: 24, gap: 8 }}>
          <Text style={{ fontSize: 19, color: palette.text, fontWeight: "600" }}>选择一个话题</Text>
          <Text style={{ fontSize: 13, color: palette.muted, textAlign: "center" }}>
            打开左侧列表中的话题，在这里阅读帖子预览
          </Text>
        </View>
      }>
        <List
          each={props.posts()}
          keyExtractor={(p) => String(p.id)}
          estimatedItemSize={190}
          style={{ flex: 1 }}
          contentContainerStyle={{ padding: 16, gap: 11, paddingBottom: 30 }}
          ListHeaderComponent={
            <View style={cardStyle()}>
              <View style={{ flexDirection: "row", gap: 8, alignItems: "center" }}>
                <Text style={{ flex: 1, color: palette.text, fontWeight: "700", fontSize: 20, lineHeight: 28 }}>
                  {props.topic()?.title ?? ""}
                </Text>
                <If when={!!props.close}>
                  <Chip label="关闭 ×" onPress={() => props.close?.()} />
                </If>
              </View>
              <Text style={{ color: palette.muted, fontSize: 12 }}>
                {props.topic() ? "浏览 " + compactCount(props.topic()!.views) +
                  " · " + props.topic()!.postsCount + " 帖" : ""}
              </Text>
              <If when={props.targetPostNumber() !== null}>
                <View style={{ gap: 8 }}>
                  <Text style={{ color: palette.muted, fontSize: 12 }}>
                    来自搜索：请求显示 #{props.targetPostNumber()} 附近的楼层
                  </Text>
                  <Chip label="从话题开头阅读" onPress={props.showBeginning} />
                </View>
              </If>
              <If when={props.loading()}>
                <Text style={{ color: palette.muted, fontSize: 13 }}>正在加载帖子…</Text>
              </If>
              <If when={props.error().length > 0}>
                <Text style={{ color: palette.danger, fontSize: 13 }}>{props.error()}</Text>
                <Text accessibilityRole="button" onPress={props.retry}
                  style={{ color: palette.accent, fontSize: 13 }}>重试加载</Text>
              </If>
            </View>
          }
          ListFooterComponent={
            <View style={{ alignItems: "center", padding: 12, gap: 9 }}>
              <If when={props.moreError().length > 0}>
                <Text style={{ color: palette.danger, fontSize: 13 }}>{props.moreError()}</Text>
              </If>
              <If when={props.remaining() > 0}>
                <Text style={{ color: palette.muted, fontSize: 12 }}>
                  已读取 {props.posts().length} 帖 · 待加载 {props.remaining()} 帖
                </Text>
                <Chip label={props.loadingMore() ? "正在读取楼层…" : "继续加载楼层"}
                  onPress={props.loadMore} />
              </If>
              <If when={props.posts().length > 0 && props.remaining() === 0}>
                <Text style={{ color: palette.muted, fontSize: 12 }}>
                  可访问楼层已加载；富文本、图片与互动功能仍待迁移。
                </Text>
              </If>
            </View>
          }
        >
          {(post) => (
            <View style={cardStyle()}>
              <View style={{ flexDirection: "row", alignItems: "center" }}>
                <Text style={{ flex: 1, fontSize: 13, fontWeight: "600", color: palette.accent }}>
                  @{post().author}
                </Text>
                <Text style={{ color: palette.muted, fontSize: 12 }}>#{post().number}</Text>
              </View>
              <Text style={{ fontSize: 14, lineHeight: 22, color: palette.text }}>
                {post().text || "（该帖没有可显示的纯文本）"}
              </Text>
            </View>
          )}
        </List>
      </If>
    </View>
  );
}

function App() {
  const tab = signal<Tab>("latest");
  const category = signal<Category | null>(null);
  const topics = signal<Topic[]>([]);
  const categories = signal<Category[]>([]);
  const loading = signal(false);
  const loadingMore = signal(false);
  const hasMore = signal(false);
  const feedError = signal("");
  const categoriesLoading = signal(false);
  const categoriesError = signal("");
  const searchQuery = signal("");
  const searchHits = signal<SearchHit[]>([]);
  const searchSubmitted = signal(false);
  const searchLoading = signal(false);
  const searchLoadingMore = signal(false);
  const searchHasMore = signal(false);
  const searchError = signal("");
  const selected = signal<Topic | null>(null);
  const targetPostNumber = signal<number | null>(null);
  const posts = signal<Post[]>([]);
  const pendingPostIds = signal<number[]>([]);
  const detailLoading = signal(false);
  const detailLoadingMore = signal(false);
  const detailMoreError = signal("");
  const detailError = signal("");
  const feedGate = new RequestGate();
  const categoryGate = new RequestGate();
  const searchGate = new RequestGate();
  const detailGate = new RequestGate();
  let nextFeedCursor: string | null = null;
  let visitedFeedCursors = new Set<string>();

  const readKind = (): FeedKind => tab() === "top" ? "top" : "latest";

  const refreshFeed = async () => {
    const ticket = feedGate.next();
    const currentKind = readKind();
    const currentCategory = category();
    loading.set(true);
    loadingMore.set(false);
    nextFeedCursor = null;
    visitedFeedCursors = new Set<string>();
    hasMore.set(false);
    feedError.set("");
    try {
      const page = await publicReader.topics(currentKind, currentCategory, 0);
      if (feedGate.isCurrent(ticket)) {
        topics.set(page.items);
        nextFeedCursor = page.nextCursor;
        hasMore.set(page.hasMore);
      }
    } catch (e) {
      if (feedGate.isCurrent(ticket)) feedError.set(String(e));
    } finally {
      if (feedGate.isCurrent(ticket)) loading.set(false);
    }
  };

  const loadMore = async () => {
    if (loading() || loadingMore() || !hasMore() || !nextFeedCursor) return;
    const cursor = nextFeedCursor;
    if (visitedFeedCursors.has(cursor)) { hasMore.set(false); return; }
    const ticket = feedGate.next();
    loadingMore.set(true);
    feedError.set("");
    try {
      const page = await publicReader.topics(readKind(), category(), cursor);
      if (feedGate.isCurrent(ticket)) {
        visitedFeedCursors.add(cursor);
        topics.set(dedupeTopics(topics(), page.items));
        nextFeedCursor = page.nextCursor;
        hasMore.set(page.items.length > 0 && page.nextCursor !== null &&
          !visitedFeedCursors.has(page.nextCursor));
      }
    } catch (e) {
      if (feedGate.isCurrent(ticket)) feedError.set(String(e));
    } finally {
      if (feedGate.isCurrent(ticket)) loadingMore.set(false);
    }
  };

  const refreshCategories = async () => {
    const ticket = categoryGate.next();
    categoriesLoading.set(true);
    categoriesError.set("");
    try {
      const result = await publicReader.categories();
      if (categoryGate.isCurrent(ticket)) categories.set(result);
    } catch (e) {
      if (categoryGate.isCurrent(ticket)) categoriesError.set(String(e));
    } finally {
      if (categoryGate.isCurrent(ticket)) categoriesLoading.set(false);
    }
  };

  let searchedTerm = "";
  let searchPage = 1;

  const changeSearchQuery = (text: string) => {
    searchGate.invalidate();
    searchQuery.set(text);
    searchHits.set([]);
    searchSubmitted.set(false);
    searchLoading.set(false);
    searchLoadingMore.set(false);
    searchHasMore.set(false);
    searchError.set("");
    searchedTerm = "";
    searchPage = 1;
  };

  const submitSearch = async () => {
    const query = searchQuery().trim();
    const ticket = searchGate.next();
    searchHits.set([]);
    searchSubmitted.set(false);
    searchLoading.set(true);
    searchLoadingMore.set(false);
    searchHasMore.set(false);
    searchError.set("");
    searchPage = 1;
    searchedTerm = query;
    try {
      const results = await publicReader.search(query, 1);
      if (searchGate.isCurrent(ticket)) {
        searchHits.set(results.items);
        searchSubmitted.set(true);
        searchHasMore.set(results.hasMore && results.items.length > 0);
      }
    } catch (e) {
      if (searchGate.isCurrent(ticket)) searchError.set(String(e));
    } finally {
      if (searchGate.isCurrent(ticket)) searchLoading.set(false);
    }
  };

  const loadMoreSearch = async () => {
    if (searchLoading() || searchLoadingMore() || !searchHasMore() || !searchedTerm) return;
    const ticket = searchGate.next();
    const nextPage = searchPage + 1;
    searchLoadingMore.set(true);
    searchError.set("");
    try {
      const results = await publicReader.search(searchedTerm, nextPage);
      if (searchGate.isCurrent(ticket)) {
        searchHits.set(mergeSearchHits(searchHits(), results.items));
        searchHasMore.set(results.hasMore && results.items.length > 0);
        searchPage = nextPage;
      }
    } catch (e) {
      if (searchGate.isCurrent(ticket)) searchError.set(String(e));
    } finally {
      if (searchGate.isCurrent(ticket)) searchLoadingMore.set(false);
    }
  };

  const retrySearch = () => {
    if (searchHits().length > 0 && searchHasMore()) void loadMoreSearch();
    else void submitSearch();
  };

  const changeTab = (next: Tab) => {
    if (tab() === next && category() === null) return;
    tab.set(next);
    if (next === "latest" || next === "top") {
      category.set(null);
      topics.set([]);
      hasMore.set(false);
      void refreshFeed();
    } else {
      feedGate.invalidate();
      loading.set(false);
      loadingMore.set(false);
      if (next === "categories" && categories().length === 0) void refreshCategories();
    }
  };

  const openCategory = (next: Category) => {
    tab.set("latest");
    category.set(next);
    topics.set([]);
    hasMore.set(false);
    void refreshFeed();
  };

  const closeCategory = () => {
    category.set(null);
    topics.set([]);
    hasMore.set(false);
    void refreshFeed();
  };

  const reloadDetail = async (topic: Topic, target?: number | null) => {
    const ticket = detailGate.next();
    posts.set([]);
    pendingPostIds.set([]);
    detailLoading.set(true);
    detailLoadingMore.set(false);
    detailMoreError.set("");
    detailError.set("");
    try {
      const detail = await publicReader.detail(topic, target);
      if (detailGate.isCurrent(ticket)) {
        posts.set(detail.posts);
        pendingPostIds.set(detail.remainingIds);
      }
    } catch (e) {
      if (detailGate.isCurrent(ticket)) detailError.set(String(e));
    } finally {
      if (detailGate.isCurrent(ticket)) detailLoading.set(false);
    }
  };
  const loadMorePosts = async () => {
    if (!selected() || detailLoading() || detailLoadingMore() || pendingPostIds().length === 0) return;
    const topic = selected()!;
    const batch = pendingPostIds().slice(0, POSTS_PER_BATCH);
    const ticket = detailGate.next();
    detailLoadingMore.set(true);
    detailMoreError.set("");
    try {
      const result = await publicReader.morePosts(topic, batch);
      if (detailGate.isCurrent(ticket)) {
        posts.set(mergePosts(posts(), result));
        // A deleted/hidden post might not be returned; still advance past attempted IDs.
        const attempted = new Set(batch);
        pendingPostIds.set(pendingPostIds().filter((id) => !attempted.has(id)));
      }
    } catch (e) {
      if (detailGate.isCurrent(ticket)) detailMoreError.set(String(e));
    } finally {
      if (detailGate.isCurrent(ticket)) detailLoadingMore.set(false);
    }
  };
  const openTopic = (topic: Topic, postNumber?: number | null) => {
    selected.set(topic);
    targetPostNumber.set(postNumber ?? null);
    void reloadDetail(topic, postNumber);
    if (windowSize().width < 900) nav.push({ name: "topic" });
  };
  const showTopicBeginning = () => {
    const topic = selected();
    if (!topic) return;
    targetPostNumber.set(null);
    void reloadDetail(topic);
  };
  const closeDetail = () => {
    detailGate.invalidate();
    selected.set(null);
    targetPostNumber.set(null);
    posts.set([]);
    pendingPostIds.set([]);
    detailLoading.set(false);
    detailLoadingMore.set(false);
    detailMoreError.set("");
    detailError.set("");
  };

  void refreshFeed();

  const isWide = () => windowSize().width >= 900;
  const tabs: { key: Tab; label: string }[] = [
    { key: "latest", label: "最新" }, { key: "top", label: "热门" },
    { key: "categories", label: "分类" }, { key: "search", label: "搜索" },
    { key: "about", label: "关于" },
  ];

  function Tabs(props: { vertical: boolean }) {
    return (
      <View style={{
        flexDirection: props.vertical ? "column" : "row",
        padding: 9, gap: 6,
        backgroundColor: palette.surface,
        borderColor: palette.border,
        borderRightWidth: props.vertical ? 1 : 0,
        borderTopWidth: props.vertical ? 0 : 1,
      }}>
        <Each of={tabs}>
          {(item) => (
            <View style={{ flex: props.vertical ? 0 : 1 }}>
              <Chip label={item().label} onPress={() => changeTab(item().key)}
                active={() => tab() === item().key} />
            </View>
          )}
        </Each>
      </View>
    );
  }

  function Content() {
    return (
      <View style={{ flex: 1 }}>
        <If when={tab() === "categories"} else={
          <If when={tab() === "about"} else={
            <If when={tab() === "search"} else={
              <FeedPage kind={readKind} category={category} clearCategory={closeCategory}
                topics={topics} loading={loading} loadingMore={loadingMore} hasMore={hasMore}
                error={feedError} refresh={() => { void refreshFeed(); }}
                loadMore={() => { void loadMore(); }} open={openTopic} />
            }>
              <SearchPage query={searchQuery} changeQuery={changeSearchQuery}
                submit={() => { void submitSearch(); }}
                hits={searchHits} submitted={searchSubmitted} loading={searchLoading}
                loadingMore={searchLoadingMore} hasMore={searchHasMore}
                error={searchError} retry={retrySearch}
                loadMore={() => { void loadMoreSearch(); }} open={openTopic} />
            </If>
          }>
            <InfoPage />
          </If>
        }>
          <CategoriesPage categories={categories} loading={categoriesLoading}
            error={categoriesError} refresh={() => { void refreshCategories(); }} select={openCategory} />
        </If>
      </View>
    );
  }

  function Root() {
    return (
      <Screen headerShown={false}>
        <SafeAreaView style={{ flex: 1, backgroundColor: palette.background }}>
          <View style={{
            flexDirection: "row", alignItems: "center", gap: 11,
            paddingHorizontal: 17, paddingVertical: 10,
            borderBottomWidth: 1, borderBottomColor: palette.border,
          }}>
            <View style={{
              width: 39, height: 39, borderRadius: 12,
              backgroundColor: palette.accent,
              justifyContent: "center", alignItems: "center",
            }}>
              <Text style={{ color: palette.onAccent, fontWeight: "700", fontSize: 22 }}>F</Text>
            </View>
            <View style={{ flex: 1, gap: 2 }}>
              <Text style={{ color: palette.text, fontSize: 20, fontWeight: "700" }}>Fluxdo</Text>
              <Text style={{ color: palette.muted, fontSize: 11 }}>NATIVE SHELL · MIGRATION PREVIEW</Text>
            </View>
            <View style={{ backgroundColor: palette.raised, borderRadius: 8, padding: 7 }}>
              <Text style={{ color: palette.accent, fontSize: 11 }}>只读</Text>
            </View>
          </View>
          <View style={{ flex: 1, flexDirection: isWide() ? "row" : "column" }}>
            <If when={isWide()}>
              <View style={{ width: 158 }}><Tabs vertical /></View>
            </If>
            <Content />
            <If when={isWide()}>
              <View style={{
                flex: 1, minWidth: 280, borderLeftWidth: 1, borderLeftColor: palette.border,
              }}>
                <DetailPane topic={selected} posts={posts} loading={detailLoading}
                  targetPostNumber={targetPostNumber} showBeginning={showTopicBeginning}
                  loadingMore={detailLoadingMore} remaining={() => pendingPostIds().length}
                  loadMore={() => { void loadMorePosts(); }} moreError={detailMoreError}
                  error={detailError} retry={() => { const t = selected(); if (t) void reloadDetail(t, targetPostNumber()); }}
                  close={closeDetail} />
              </View>
            </If>
          </View>
          <If when={!isWide()}><Tabs vertical={false} /></If>
        </SafeAreaView>
      </Screen>
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: palette.background }}>
      <StatusBar barStyle={colorScheme() === "dark" ? "light-content" : "dark-content"} />
      <Stack navigator={nav} style={{ flex: 1 }}>
        {(route) => route.name === "home"
          ? <Root />
          : (
            <Screen title="话题详情" headerBackgroundColor={palette.background}
              headerTitleColor={palette.text} headerTintColor={palette.accent}>
              <View style={{ flex: 1, backgroundColor: palette.background }}>
                <DetailPane topic={selected} posts={posts} loading={detailLoading}
                  targetPostNumber={targetPostNumber} showBeginning={showTopicBeginning}
                  loadingMore={detailLoadingMore} remaining={() => pendingPostIds().length}
                  loadMore={() => { void loadMorePosts(); }} moreError={detailMoreError}
                  error={detailError}
                  retry={() => { const t = selected(); if (t) void reloadDetail(t, targetPostNumber()); }} />
              </View>
            </Screen>
          )}
      </Stack>
    </View>
  );
}

mount(App);
