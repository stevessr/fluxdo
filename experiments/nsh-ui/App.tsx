import { Input, mount, Scroll, signal, Text, View } from "nsh";
import { List } from "nsh/list";
import { SafeAreaView } from "nsh/ui/mobile";
import { compactCount, fetchPosts, fetchTopics, type FeedMode, type Post, type Topic } from "./discourse";

// UI 原型独立于 Flutter：不能在这里读取 Flutter Cookie、Riverpod 或安全存储。
const ui = {
  page: "#f4f7fc",
  card: "#ffffff",
  accent: "#5269d8",
  pale: "#e9eeff",
  text: "#1f293f",
  muted: "#7c879c",
  line: "#e8edf4",
  danger: "#b5474e",
};

function Action(props: {
  label: string;
  onPress: () => void;
  selected?: () => boolean;
}) {
  return (
    <View
      onPress={props.onPress}
      accessibilityRole="button"
      accessibilityLabel={props.label}
      activeOpacity={0.65}
      style={{
        backgroundColor: props.selected?.() ? ui.accent : ui.pale,
        borderRadius: 12,
        paddingHorizontal: 14,
        paddingVertical: 10,
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <Text style={{ color: props.selected?.() ? "#ffffff" : ui.accent, fontSize: 13, fontWeight: "600" }}>
        {props.label}
      </Text>
    </View>
  );
}

function TopicRow(props: { topic: () => Topic; onOpen: (value: Topic) => void }) {
  return (
    <View
      onPress={() => props.onOpen(props.topic())}
      accessibilityRole="button"
      activeOpacity={0.75}
      style={{
        backgroundColor: ui.card,
        borderRadius: 17,
        paddingHorizontal: 16,
        paddingVertical: 15,
        gap: 10,
        borderWidth: 1,
        borderColor: ui.line,
      }}
    >
      <Text numberOfLines={2} style={{ color: ui.text, fontSize: 16, fontWeight: "600", lineHeight: 24 }}>
        {props.topic().title}
      </Text>
      <If when={props.topic().tags.length > 0}>
        <Text numberOfLines={1} style={{ color: ui.accent, fontSize: 12 }}>
          {props.topic().tags.slice(0, 3).map((tag) => "#" + tag).join("  ")}
        </Text>
      </If>
      <View style={{ flexDirection: "row", gap: 14, alignItems: "center" }}>
        <Text style={{ color: ui.muted, fontSize: 12 }}>浏览 {compactCount(props.topic().views)}</Text>
        <Text style={{ color: ui.muted, fontSize: 12 }}>回复 {Math.max(0, props.topic().postsCount - 1)}</Text>
        <Text style={{ color: ui.muted, fontSize: 12 }}>赞 {compactCount(props.topic().likeCount)}</Text>
        <View style={{ flex: 1 }} />
        <Text style={{ color: ui.accent, fontSize: 12 }}>查看 ›</Text>
      </View>
    </View>
  );
}

function Feed(props: {
  mode: () => FeedMode;
  topics: () => Topic[];
  query: () => string;
  setQuery: (value: string) => void;
  loading: () => boolean;
  error: () => string;
  setMode: (value: FeedMode) => void;
  refresh: () => void;
  open: (value: Topic) => void;
}) {
  return (
    <View style={{ flex: 1, gap: 12 }}>
      <View style={{ paddingHorizontal: 18, paddingTop: 14, gap: 13 }}>
        <View style={{ flexDirection: "row", gap: 8, alignItems: "center" }}>
          <Action label="最新话题" selected={() => props.mode() === "latest"} onPress={() => props.setMode("latest")} />
          <Action label="本周热门" selected={() => props.mode() === "top"} onPress={() => props.setMode("top")} />
          <View style={{ flex: 1 }} />
          <Action label="刷新 ↻" onPress={props.refresh} />
        </View>
        <Input
          value={props.query()}
          onChangeText={props.setQuery}
          placeholder="搜索当前列表中的话题"
          returnKeyType="search"
          style={{
            backgroundColor: ui.card,
            color: ui.text,
            borderWidth: 1,
            borderColor: ui.line,
            borderRadius: 13,
            paddingHorizontal: 15,
            paddingVertical: 11,
            fontSize: 14,
          }}
        />
        <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
          <Text style={{ color: ui.muted, fontSize: 12 }}>
            {props.loading() ? "正在读取公开话题…" : `已加载 ${props.topics().length} 个公开话题`}
          </Text>
          <View style={{ flex: 1 }} />
          <Text style={{ color: ui.muted, fontSize: 11 }}>仅预览 · 不会修改账户</Text>
        </View>
        <If when={props.error().length > 0}>
          <View style={{ backgroundColor: "#fff0ef", borderRadius: 12, padding: 12, gap: 6 }}>
            <Text style={{ color: ui.danger, fontSize: 13 }}>{props.error()}</Text>
            <Text onPress={props.refresh} style={{ color: ui.accent, fontSize: 13 }}>重新尝试</Text>
          </View>
        </If>
      </View>
      <List
        each={props.topics().filter((topic) => {
          const query = props.query().trim().toLowerCase();
          return !query || topic.title.toLowerCase().includes(query) ||
            topic.tags.some((tag) => tag.toLowerCase().includes(query));
        })}
        keyExtractor={(topic) => String(topic.id)}
        estimatedItemSize={126}
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: 15, paddingVertical: 10, gap: 10 }}
        refreshing={props.loading()}
        onRefresh={props.refresh}
        ListEmptyComponent={
          <View style={{ padding: 28, alignItems: "center", gap: 8 }}>
            <Text style={{ fontSize: 16, fontWeight: "600", color: ui.text }}>
              {props.loading() ? "加载中…" : "暂无匹配的话题"}
            </Text>
            <Text style={{ color: ui.muted, fontSize: 13 }}>尝试切换列表、清空搜索词或刷新</Text>
          </View>
        }
      >
        {(topic) => <TopicRow topic={topic} onOpen={props.open} />}
      </List>
    </View>
  );
}

function Detail(props: {
  topic: () => Topic | null;
  posts: () => Post[];
  loading: () => boolean;
  error: () => string;
  back: () => void;
  retry: () => void;
}) {
  return (
    <View style={{ flex: 1, gap: 10 }}>
      <View style={{ paddingHorizontal: 18, paddingTop: 12, flexDirection: "row", gap: 14, alignItems: "center" }}>
        <Action label="‹ 返回" onPress={props.back} />
        <Text style={{ flex: 1, color: ui.muted, fontSize: 13 }}>公开话题 · 原生界面实验</Text>
      </View>
      <Scroll style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 16, paddingVertical: 12, gap: 12 }}>
        <View style={{ backgroundColor: ui.card, padding: 18, borderRadius: 17, gap: 12 }}>
          <Text style={{ color: ui.text, fontSize: 22, fontWeight: "700", lineHeight: 31 }}>
            {props.topic()?.title ?? ""}
          </Text>
          <Text style={{ fontSize: 12, color: ui.muted }}>
            {props.topic() ? `浏览 ${compactCount(props.topic()!.views)} · 共 ${props.topic()!.postsCount} 帖` : ""}
          </Text>
        </View>
        <If when={props.loading()}>
          <Text style={{ color: ui.muted, fontSize: 14, padding: 12 }}>正在加载帖子正文…</Text>
        </If>
        <If when={props.error().length > 0}>
          <View style={{ padding: 14, gap: 10, borderRadius: 12, backgroundColor: "#fff0ef" }}>
            <Text style={{ color: ui.danger }}>{props.error()}</Text>
            <Text onPress={props.retry} style={{ color: ui.accent }}>重新加载</Text>
          </View>
        </If>
        <Each of={props.posts()}>
          {(post) => (
            <View style={{ backgroundColor: ui.card, borderRadius: 17, padding: 18, gap: 12 }}>
              <View style={{ flexDirection: "row", alignItems: "center" }}>
                <Text style={{ flex: 1, color: ui.accent, fontSize: 13, fontWeight: "600" }}>
                  @{post().author}
                </Text>
                <Text style={{ color: ui.muted, fontSize: 12 }}>#{post().postNumber}</Text>
              </View>
              <Text style={{ color: ui.text, fontSize: 14, lineHeight: 23 }}>
                {post().body || "（该帖子没有可显示的纯文本）"}
              </Text>
            </View>
          )}
        </Each>
        <If when={props.posts().length > 0}>
          <Text style={{ color: ui.muted, fontSize: 12, textAlign: "center", padding: 12 }}>
            当前只展示前 12 帖的纯文本。完整富文本、回复和登录仍由 Flutter 正式版提供。
          </Text>
        </If>
      </Scroll>
    </View>
  );
}

function App() {
  const mode = signal<FeedMode>("latest");
  const query = signal("");
  const topics = signal<Topic[]>([]);
  const loading = signal(false);
  const error = signal("");
  const selected = signal<Topic | null>(null);
  const posts = signal<Post[]>([]);
  const detailLoading = signal(false);
  const detailError = signal("");

  // 请求代数隔离：快速切换 tab 或连续打开话题时，迟到响应不能覆盖新页面。
  let feedGeneration = 0;
  let detailGeneration = 0;

  const refresh = async () => {
    const generation = ++feedGeneration;
    loading.set(true);
    error.set("");
    try {
      const result = await fetchTopics(mode());
      if (generation === feedGeneration) topics.set(result);
    } catch (cause) {
      if (generation === feedGeneration) error.set(String(cause));
    } finally {
      if (generation === feedGeneration) loading.set(false);
    }
  };

  const setMode = (next: FeedMode) => {
    if (mode() === next) return;
    mode.set(next);
    query.set("");
    topics.set([]);
    void refresh();
  };

  const loadDetail = async (topic: Topic) => {
    const generation = ++detailGeneration;
    posts.set([]);
    detailLoading.set(true);
    detailError.set("");
    try {
      const result = await fetchPosts(topic);
      if (generation === detailGeneration) posts.set(result);
    } catch (cause) {
      if (generation === detailGeneration) detailError.set(String(cause));
    } finally {
      if (generation === detailGeneration) detailLoading.set(false);
    }
  };

  const open = (topic: Topic) => {
    selected.set(topic);
    void loadDetail(topic);
  };

  const back = () => {
    ++detailGeneration;
    selected.set(null);
    posts.set([]);
    detailError.set("");
  };

  void refresh();

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: ui.page }}>
      <View style={{ flexDirection: "row", paddingHorizontal: 18, paddingTop: 12, paddingBottom: 13, alignItems: "center", gap: 11 }}>
        <View style={{ width: 42, height: 42, borderRadius: 14, backgroundColor: ui.accent, alignItems: "center", justifyContent: "center" }}>
          <Text style={{ color: "#ffffff", fontSize: 22, fontWeight: "700" }}>F</Text>
        </View>
        <View style={{ flex: 1, gap: 2 }}>
          <Text style={{ color: ui.text, fontSize: 21, fontWeight: "700" }}>Fluxdo</Text>
          <Text style={{ color: ui.muted, fontSize: 11 }}>NATIVE SHELL · UI EXPERIMENT</Text>
        </View>
        <View style={{ borderRadius: 10, backgroundColor: "#e5f6e9", paddingVertical: 7, paddingHorizontal: 9 }}>
          <Text style={{ fontSize: 11, fontWeight: "600", color: "#3b8856" }}>只读原型</Text>
        </View>
      </View>
      <View style={{ height: 1, backgroundColor: ui.line }} />
      <If when={selected() !== null} else={
        <Feed
          mode={mode}
          topics={topics}
          query={query}
          setQuery={(value) => query.set(value)}
          loading={loading}
          error={error}
          setMode={setMode}
          refresh={() => { void refresh(); }}
          open={open}
        />
      }>
        <Detail
          topic={selected}
          posts={posts}
          loading={detailLoading}
          error={detailError}
          back={back}
          retry={() => { const topic = selected(); if (topic) void loadDetail(topic); }}
        />
      </If>
    </SafeAreaView>
  );
}

mount(App);
