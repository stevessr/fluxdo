import { Input, mount, Scroll, signal, Text, View } from "nsh";
import { colorScheme, Platform, windowSize } from "nsh/device";
import { List } from "nsh/list";
import { createNavigator, SafeAreaView, Screen, Stack, StatusBar } from "nsh/ui/mobile";
import {
  compactCount, dedupeTopics, mergePosts, mergeSearchHits, POSTS_PER_BATCH, publicReader,
  type Category, type FeedKind, type Post, type SearchHit, type Topic, type PublicUserProfile,
  type BoardSummary, type BoardDetail, type Tag,
} from "./data";
import { RequestGate } from "./request_gate";
import { readNativeBootstrapStatus } from "./host_native_transport";

/**
 * Native Shell 正式迁移目录的第一个独立入口。
 * 当前只读、匿名，不使用 Flutter Cookie 或 JS 凭据。
 */
type Tab = "latest" | "top" | "categories" | "search" | "boards" | "users" | "about";
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
  tag: () => Tag | null;
  clearCategory: () => void;
  clearTag: () => void;
  browseCategories: () => void;
  browseTags: () => void;
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
            {props.category() && props.tag()
              ? (props.category()!.fullName ?? props.category()!.name) + " · #" + props.tag()!.name
              : props.tag() ? "#" + props.tag()!.name
              : props.category()?.fullName ?? props.category()?.name ??
                (props.kind() === "latest" ? "最新话题" : "本周热门")}
          </Text>
          <Chip label="刷新 ↻" onPress={props.refresh} />
        </View>
        <If when={props.category() !== null}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 9 }}>
            <Text style={{ flex: 1, color: palette.muted, fontSize: 12 }}>按分类筛选</Text>
            <Chip label="清除分类 ×" onPress={props.clearCategory} />
          </View>
        </If>
        <If when={props.tag() !== null}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 9 }}>
            <Text style={{ flex: 1, color: palette.muted, fontSize: 12 }}>正在浏览标签话题</Text>
            <Chip label="清除标签 ×" onPress={props.clearTag} />
          </View>
        </If>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 7 }}>
          <Text style={{ flex: 1, color: palette.muted, fontSize: 12 }}>
            服务器组合筛选（仅当前选中条件）
          </Text>
          <Chip label={props.category() ? "更改分类" : "选分类"} onPress={props.browseCategories} />
          <Chip label={props.tag() ? "更改标签" : "选标签"} onPress={props.browseTags} />
        </View>
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
  showTags: () => void;
  filterHint: () => string;
  backToResults: () => void;
}) {
  const query = signal("");
  const displayed = () => {
    const needle = query().trim().toLocaleLowerCase();
    return needle ? props.categories().filter(c =>
      (c.fullName ?? c.name).toLocaleLowerCase().includes(needle)) : props.categories();
  };
  return (
    <View style={{ flex: 1, gap: 10 }}>
      <View style={{ flexDirection: "row", paddingHorizontal: 16, paddingTop: 13, alignItems: "center", gap: 7 }}>
        <Text style={{ fontSize: 21, flex: 1, color: palette.text, fontWeight: "700" }}>分类目录</Text>
        <Chip label="标签 #" onPress={props.showTags} />
        <Chip label="刷新 ↻" onPress={props.refresh} />
      </View>
      <If when={props.filterHint().length > 0}>
        <View style={{ paddingHorizontal: 15, gap: 7 }}>
          <Text style={{ color: palette.muted, fontSize: 12 }}>
            {props.filterHint()} · 选择分类以组合筛选
          </Text>
          <Chip label="返回筛选结果" onPress={props.backToResults} />
        </View>
      </If>
      <View style={{ paddingHorizontal: 14, gap: 7 }}>
        <Input value={query()} onChangeText={(value) => query.set(value)}
          placeholder="筛选分类及其父级路径"
          returnKeyType="search"
          style={{ fontSize: 14, color: palette.text, backgroundColor: palette.surface,
            borderWidth: 1, borderColor: palette.border, borderRadius: 12,
            paddingHorizontal: 13, paddingVertical: 10 }} />
        <Text style={{ color: palette.muted, fontSize: 12 }}>
          {props.loading() ? "读取包含子分类的公开目录…" :
            "已载入 " + props.categories().length + " 个公开分类"}
        </Text>
      </View>
      <ErrorView message={props.error} retry={props.refresh} />
      <List
        each={displayed()}
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
          <View onPress={() => { if (item().slugPath !== null) props.select(item()); }}
            accessibilityRole="button"
            accessibilityLabel={"分类：" + (item().fullName ?? item().name)}
            accessibilityState={{ disabled: item().slugPath === null }}
            style={{
              ...cardStyle(), flexDirection: "row", alignItems: "center",
              marginLeft: Math.min(item().depth ?? 0, 5) * 10,
            }}
          >
            <View style={{ flex: 1, gap: 5 }}>
              <Text style={{ color: palette.text, fontSize: 16, fontWeight: "600" }}>
                {item().depth ? "↳ " : ""}{item().name}
              </Text>
              <If when={(item().depth ?? 0) > 0}>
                <Text style={{ color: palette.muted, fontSize: 12 }} numberOfLines={2}>
                  {item().fullName ?? item().name}
                </Text>
              </If>
              <Text style={{ color: palette.muted, fontSize: 12 }}>
                {item().slugPath === null
                  ? "父级缺失或分类层级异常，暂不可打开"
                  : "话题 " + compactCount(item().topicCount)}
              </Text>
            </View>
            <Text style={{ color: palette.accent, fontSize: 18 }}>
              {item().slugPath === null ? "锁" : "›"}
            </Text>
          </View>
        )}
      </List>
    </View>
  );
}

function TagsPage(props: {
  tags: () => Tag[];
  loading: () => boolean;
  error: () => string;
  refresh: () => void;
  select: (tag: Tag) => void;
  showCategories: () => void;
  filterHint: () => string;
  backToResults: () => void;
}) {
  const filter = signal("");
  const visibleTags = () => {
    const needle = filter().trim().toLocaleLowerCase();
    return needle ? props.tags().filter((tag) =>
      tag.name.toLocaleLowerCase().includes(needle) ||
      tag.description.toLocaleLowerCase().includes(needle)) : props.tags();
  };
  return (
    <View style={{ flex: 1, gap: 9 }}>
      <View style={{ paddingHorizontal: 14, paddingTop: 13, gap: 9 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 7 }}>
          <Text style={{ fontSize: 21, flex: 1, color: palette.text, fontWeight: "700" }}>标签目录</Text>
          <Chip label="分类" onPress={props.showCategories} />
          <Chip label="刷新 ↻" onPress={props.refresh} />
        </View>
        <If when={props.filterHint().length > 0}>
          <Text style={{ color: palette.muted, fontSize: 12 }}>
            {props.filterHint()} · 选择标签以组合筛选
          </Text>
          <Chip label="返回筛选结果" onPress={props.backToResults} />
        </If>
        <Input value={filter()} onChangeText={(value) => filter.set(value)}
          placeholder="筛选已载入的标签"
          returnKeyType="search"
          style={{ fontSize: 14, color: palette.text, backgroundColor: palette.surface,
            borderWidth: 1, borderColor: palette.border, borderRadius: 12,
            paddingHorizontal: 13, paddingVertical: 10 }} />
        <Text style={{ color: palette.muted, fontSize: 12 }}>
          {props.loading() ? "正在读取标签目录…" :
            "当前加载 " + props.tags().length + " 个公开标签"}
        </Text>
      </View>
      <ErrorView message={props.error} retry={props.refresh} />
      <List
        each={visibleTags()}
        keyExtractor={(tag) => String(tag.id)}
        estimatedItemSize={83}
        style={{ flex: 1 }}
        refreshing={props.loading()}
        onRefresh={props.refresh}
        contentContainerStyle={{ paddingHorizontal: 14, paddingBottom: 20, gap: 8 }}
        ListEmptyComponent={
          <Text style={{ color: palette.muted, textAlign: "center", padding: 22 }}>
            {props.loading() ? "正在加载标签…" : "没有匹配的公开标签"}
          </Text>
        }
      >
        {(item) => (
          <View onPress={() => props.select(item())}
            accessibilityRole="button"
            accessibilityLabel={"标签：" + item().name}
            style={{ ...cardStyle(), flexDirection: "row", alignItems: "center" }}>
            <View style={{ flex: 1, gap: 4 }}>
              <Text style={{ color: palette.accent, fontSize: 15, fontWeight: "600" }}>
                #{item().name}
              </Text>
              <If when={!!item().description}>
                <Text style={{ color: palette.muted, fontSize: 12 }}
                  numberOfLines={2}>{item().description}</Text>
              </If>
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

function ProfilePage(props: {
  username: () => string;
  changeUsername: (name: string) => void;
  lookup: () => void;
  loading: () => boolean;
  attempted: () => boolean;
  error: () => string;
  profile: () => PublicUserProfile | null;
}) {
  return (
    <Scroll style={{ flex: 1 }} contentContainerStyle={{ padding: 16, gap: 13 }}>
      <Text style={{ color: palette.text, fontSize: 21, fontWeight: "700" }}>公开用户资料</Text>
      <Text style={{ color: palette.muted, fontSize: 13, lineHeight: 19 }}>
        输入 Linux.do 用户名，仅读取可公开访问的资料；不登录、不获取私人信息。
      </Text>
      <Input
        value={props.username()}
        onChangeText={props.changeUsername}
        placeholder="输入用户名，例如 @steve"
        returnKeyType="search"
        style={{
          fontSize: 14, color: palette.text, backgroundColor: palette.surface,
          borderWidth: 1, borderColor: palette.border, borderRadius: 12,
          paddingHorizontal: 13, paddingVertical: 11,
        }}
      />
      <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
        <Chip label={props.loading() ? "查询中…" : "查询资料"} onPress={props.lookup} />
        <Text style={{ color: palette.muted, fontSize: 12, flex: 1 }}>
          {props.loading() ? "正在读取公开资料…" :
            props.attempted() ? "查询结束" : "可查询公开资料"}
        </Text>
      </View>
      <ErrorView message={props.error} retry={props.lookup} />
      <If when={props.profile() !== null}>
        <View style={cardStyle()}>
          <Text style={{ fontSize: 20, fontWeight: "700", color: palette.text }}>
            {props.profile()?.name || props.profile()?.username || ""}
          </Text>
          <Text style={{ color: palette.accent, fontSize: 14 }}>
            @{props.profile()?.username ?? ""}
          </Text>
          <If when={!!props.profile()?.title}>
            <Text style={{ color: palette.muted, fontSize: 13 }}>{props.profile()?.title ?? ""}</Text>
          </If>
          <Text style={{ color: palette.muted, fontSize: 13 }}>
            信任等级 {props.profile()?.trustLevel ?? 0} · 帖子 {compactCount(props.profile()?.postCount ?? 0)}
          </Text>
        </View>
        <View style={cardStyle()}>
          <Text style={{ fontSize: 15, fontWeight: "600", color: palette.text }}>个人简介</Text>
          <Text style={{ fontSize: 14, color: palette.text, lineHeight: 22 }}>
            {props.profile()?.bio || "该用户没有可公开显示的简介"}
          </Text>
        </View>
      </If>
    </Scroll>
  );
}

function BoardsPage(props: {
  boards: () => BoardSummary[];
  loading: () => boolean;
  error: () => string;
  refresh: () => void;
  active: () => BoardSummary | null;
  detail: () => BoardDetail | null;
  detailLoading: () => boolean;
  detailError: () => string;
  openBoard: (board: BoardSummary) => void;
  retryDetail: () => void;
  openTopic: (topic: Topic) => void;
}) {
  return (
    <Scroll style={{ flex: 1 }} contentContainerStyle={{ padding: 14, gap: 12, paddingBottom: 28 }}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
        <Text style={{ flex: 1, color: palette.text, fontSize: 21, fontWeight: "700" }}>
          看板目录
        </Text>
        <Chip label={props.loading() ? "加载中…" : "刷新 ↻"} onPress={props.refresh} />
      </View>
      <Text style={{ color: palette.muted, fontSize: 12, lineHeight: 18 }}>
        Discourse Boards 只读预览。仅匿名可见的看板可打开；
        私有看板、卡片移动和编辑需要后续 Host 登录集成。
      </Text>
      <ErrorView message={props.error} retry={props.refresh} />
      <If when={props.loading()}>
        <Text style={{ color: palette.muted, fontSize: 13 }}>正在读取看板目录…</Text>
      </If>
      <If when={!props.loading() && !props.error() && props.boards().length === 0}>
        <Text style={{ color: palette.muted, fontSize: 13 }}>
          暂无可公开发现的看板，或当前站点未启用 Boards 插件。
        </Text>
      </If>
      <Each of={props.boards()}>
        {(entry) => (
          <View
            accessibilityRole="button"
            accessibilityLabel={entry().name}
            onPress={() => { if (entry().anonymousCanRead) props.openBoard(entry()); }}
            style={{
              ...cardStyle(), flexDirection: "row", alignItems: "center",
              borderColor: props.active()?.id === entry().id ? palette.accent : palette.border,
            }}
          >
            <View style={{ flex: 1, gap: 4 }}>
              <Text style={{ color: palette.text, fontSize: 15, fontWeight: "600" }}>
                {entry().name}
              </Text>
              <Text style={{ color: palette.muted, fontSize: 12 }}>
                {entry().anonymousCanRead ? "公开可读" : "需要登录"} · {entry().columnCount} 栏
              </Text>
            </View>
            <Text style={{ color: palette.accent, fontSize: 17 }}>
              {entry().anonymousCanRead ? "›" : "锁"}
            </Text>
          </View>
        )}
      </Each>
      <If when={props.active() !== null}>
        <View style={{ paddingTop: 9, gap: 7 }}>
          <Text style={{ color: palette.text, fontWeight: "700", fontSize: 19 }}>
            {props.active()?.name ?? "看板详情"}
          </Text>
          <If when={props.detailLoading()}>
            <Text style={{ color: palette.muted, fontSize: 13 }}>正在读取看板栏目与卡片…</Text>
          </If>
          <ErrorView message={props.detailError} retry={props.retryDetail} />
          <If when={props.detail() !== null}>
            <If when={props.detail()?.truncated ?? false}>
              <Text style={{ color: palette.danger, fontSize: 12 }}>
                卡片较多，当前仅显示前 30 栏 / 500 张卡片。
              </Text>
            </If>
            <If when={props.detail()?.columns.length === 0}>
              <Text style={{ color: palette.muted, fontSize: 13 }}>当前看板没有栏目。</Text>
            </If>
            <Each of={props.detail()?.columns ?? []}>
              {(column) => (
                <View style={{ ...cardStyle(), gap: 10 }}>
                  <Text style={{ color: palette.text, fontSize: 16, fontWeight: "700" }}>
                    {column().title || "未命名栏目"} · {column().cards.length}
                  </Text>
                  <If when={column().cards.length === 0}>
                    <Text style={{ color: palette.muted, fontSize: 12 }}>暂无卡片</Text>
                  </If>
                  <Each of={column().cards}>
                    {(item) => (
                      <View
                        accessibilityRole={item().topic ? "button" : "text"}
                        accessibilityLabel={item().title || "看板卡片"}
                        onPress={() => { const topic = item().topic; if (topic) props.openTopic(topic); }}
                        style={{
                          backgroundColor: palette.raised, borderRadius: 11,
                          padding: 12, gap: 6,
                        }}
                      >
                        <Text style={{ color: palette.text, fontSize: 14, fontWeight: "600" }}>
                          {item().title || "无标题卡片"}
                        </Text>
                        <If when={item().notes.length > 0}>
                          <Text style={{ color: palette.muted, fontSize: 12, lineHeight: 19 }}
                            numberOfLines={5}>{item().notes}</Text>
                        </If>
                        <If when={item().topic !== null}>
                          <Text style={{ color: palette.accent, fontSize: 12 }}>
                            话题卡片 · {item().topic?.postsCount ?? 0} 帖 · 点击阅读 ›
                          </Text>
                        </If>
                      </View>
                    )}
                  </Each>
                </View>
              )}
            </Each>
          </If>
        </View>
      </If>
    </Scroll>
  );
}

function InfoPage(props: {nativeStatus: () => string; retryNative: () => void}) {
  return (
    <Scroll style={{ flex: 1 }} contentContainerStyle={{ padding: 18, gap: 15 }}>
      <Text style={{ fontSize: 22, fontWeight: "700", color: palette.text }}>Fluxdo · NSH 迁移版</Text>
      <View style={cardStyle()}>
        <Text style={{ fontSize: 16, fontWeight: "600", color: palette.text }}>独立原生 UI 开发预览</Text>
        <Text style={{ fontSize: 14, lineHeight: 21, color: palette.muted }}>
          当前支持 Linux.do 公开信息流、分类、搜索、看板、用户资料查询及话题纯文本阅读。
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
        <Text style={{ color: palette.text, fontSize: 15, fontWeight: "600" }}>Rust 原生 Host</Text>
        <Text style={{ color: palette.muted, fontSize: 13 }}>{props.nativeStatus()}</Text>
        <Chip label="检查 Rust Bridge" onPress={props.retryNative} />
        <Text style={{ color: palette.muted, fontSize: 12 }}>
          当前仅版本握手，尚无登录会话、多账户、私有数据或写入能力。
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
  const nativeStatus = signal("尚未检查 Rust Host");
  const nativeGate = new RequestGate();
  const checkNativeHost = async () => {
    const ticket = nativeGate.next();
    nativeStatus.set("正在进行 Rust 原生握手…");
    try {
      const connected = await readNativeBootstrapStatus();
      if (nativeGate.isCurrent(ticket)) {
        nativeStatus.set(connected
          ? "Rust 模块已接通 · 仅能力握手，核心服务未连接"
          : "Rust 模块尚未就绪");
      }
    } catch {
      if (nativeGate.isCurrent(ticket)) {
        nativeStatus.set("Rust 模块不可用；匿名公开阅读不受影响");
      }
    }
  };
  void checkNativeHost();
  const tab = signal<Tab>("latest");
  const category = signal<Category | null>(null);
  const selectedTag = signal<Tag | null>(null);
  const directoryMode = signal<"categories" | "tags">("categories");
  const tags = signal<Tag[]>([]);
  const tagsLoading = signal(false);
  const tagsError = signal("");
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
  const profileName = signal("");
  const userProfile = signal<PublicUserProfile | null>(null);
  const profileLoading = signal(false);
  const profileAttempted = signal(false);
  const profileError = signal("");
  const boards = signal<BoardSummary[]>([]);
  const boardsLoading = signal(false);
  const boardsError = signal("");
  const activeBoard = signal<BoardSummary | null>(null);
  const boardDetail = signal<BoardDetail | null>(null);
  const boardDetailLoading = signal(false);
  const boardDetailError = signal("");
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
  const tagGate = new RequestGate();
  const searchGate = new RequestGate();
  const profileGate = new RequestGate();
  const boardsGate = new RequestGate();
  const boardDetailGate = new RequestGate();
  const detailGate = new RequestGate();
  let nextFeedCursor: string | null = null;
  let visitedFeedCursors = new Set<string>();

  const readKind = (): FeedKind => tab() === "top" ? "top" : "latest";

  const refreshFeed = async () => {
    const ticket = feedGate.next();
    const currentKind = readKind();
    const currentCategory = category();
    const currentTag = selectedTag();
    loading.set(true);
    loadingMore.set(false);
    nextFeedCursor = null;
    visitedFeedCursors = new Set<string>();
    hasMore.set(false);
    feedError.set("");
    try {
      const page = currentCategory && currentTag
        ? await publicReader.categoryTagTopics(currentCategory, currentTag, 0)
        : currentTag ? await publicReader.tagTopics(currentTag, 0)
        : await publicReader.topics(currentKind, currentCategory, 0);
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
      const currentTag = selectedTag();
      const currentCategory = category();
      const page = currentCategory && currentTag
        ? await publicReader.categoryTagTopics(currentCategory, currentTag, cursor)
        : currentTag ? await publicReader.tagTopics(currentTag, cursor)
        : await publicReader.topics(readKind(), currentCategory, cursor);
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

  const refreshTags = async () => {
    const ticket = tagGate.next();
    tagsLoading.set(true);
    tagsError.set("");
    try {
      const result = await publicReader.tags();
      if (tagGate.isCurrent(ticket)) tags.set(result);
    } catch (e) {
      if (tagGate.isCurrent(ticket)) tagsError.set(String(e));
    } finally {
      if (tagGate.isCurrent(ticket)) tagsLoading.set(false);
    }
  };
  const showTagDirectory = () => {
    directoryMode.set("tags");
    if (tags().length === 0 && !tagsLoading()) void refreshTags();
  };
  const showCategoryDirectory = () => {
    directoryMode.set("categories");
    if (categories().length === 0 && !categoriesLoading()) void refreshCategories();
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
    if (searchPage >= 50) { searchHasMore.set(false); return; }
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

  const changeProfileName = (name: string) => {
    profileGate.invalidate();
    profileName.set(name);
    userProfile.set(null);
    profileError.set("");
    profileLoading.set(false);
    profileAttempted.set(false);
  };

  const lookupProfile = async () => {
    if (profileLoading()) return;
    const ticket = profileGate.next();
    profileLoading.set(true);
    profileAttempted.set(false);
    profileError.set("");
    userProfile.set(null);
    try {
      const profile = await publicReader.profile(profileName());
      if (profileGate.isCurrent(ticket)) {
        userProfile.set(profile);
        profileAttempted.set(true);
      }
    } catch (e) {
      if (profileGate.isCurrent(ticket)) {
        profileError.set(String(e));
        profileAttempted.set(true);
      }
    } finally {
      if (profileGate.isCurrent(ticket)) profileLoading.set(false);
    }
  };

  const refreshBoards = async () => {
    const ticket = boardsGate.next();
    boardDetailGate.invalidate();
    activeBoard.set(null);
    boardDetail.set(null);
    boardDetailLoading.set(false);
    boardDetailError.set("");
    boardsLoading.set(true);
    boardsError.set("");
    boards.set([]);
    try {
      const result = await publicReader.boards();
      if (boardsGate.isCurrent(ticket)) boards.set(result);
    } catch (e) {
      if (boardsGate.isCurrent(ticket)) boardsError.set(String(e));
    } finally {
      if (boardsGate.isCurrent(ticket)) boardsLoading.set(false);
    }
  };

  const openBoard = async (board: BoardSummary) => {
    // The index is a capability hint only: the server is still authoritative.
    if (!board.anonymousCanRead ||
        !boards().some((entry) => entry.id === board.id && entry.anonymousCanRead)) return;
    const ticket = boardDetailGate.next();
    activeBoard.set(board);
    boardDetail.set(null);
    boardDetailLoading.set(true);
    boardDetailError.set("");
    try {
      const result = await publicReader.board(board);
      if (boardDetailGate.isCurrent(ticket)) boardDetail.set(result);
    } catch (e) {
      if (boardDetailGate.isCurrent(ticket)) boardDetailError.set(String(e));
    } finally {
      if (boardDetailGate.isCurrent(ticket)) boardDetailLoading.set(false);
    }
  };

  const changeTab = (next: Tab) => {
    if (tab() === next && category() === null && selectedTag() === null) return;
    tab.set(next);
    if (next === "latest" || next === "top") {
      category.set(null);
      selectedTag.set(null);
      topics.set([]);
      hasMore.set(false);
      void refreshFeed();
    } else {
      feedGate.invalidate();
      loading.set(false);
      loadingMore.set(false);
      if (next === "categories") {
        if (directoryMode() === "tags" && tags().length === 0 && !tagsLoading()) void refreshTags();
        if (directoryMode() === "categories" && categories().length === 0 && !categoriesLoading()) {
          void refreshCategories();
        }
      }
      if (next === "boards" && boards().length === 0 && !boardsLoading()) void refreshBoards();
    }
  };

  // Retain the other dimension when selecting a filter, enabling true server-side intersection.
  const browseFilters = (mode: "categories" | "tags") => {
    directoryMode.set(mode);
    tab.set("categories");
    feedGate.invalidate();
    loading.set(false);
    loadingMore.set(false);
    if (mode === "categories" && categories().length === 0 && !categoriesLoading()) {
      void refreshCategories();
    }
    if (mode === "tags" && tags().length === 0 && !tagsLoading()) void refreshTags();
  };
  const backToResults = () => {
    tab.set("latest");
    topics.set([]);
    hasMore.set(false);
    void refreshFeed();
  };
  const openCategory = (next: Category) => {
    if (next.slugPath === null) return;
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
  const openTag = (next: Tag) => {
    tab.set("latest");
    selectedTag.set(next);
    topics.set([]);
    hasMore.set(false);
    void refreshFeed();
  };
  const closeTag = () => {
    selectedTag.set(null);
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
    { key: "boards", label: "看板" }, { key: "users", label: "用户" },
    { key: "about", label: "关于" },
  ];

  function Tabs(props: { vertical: boolean }) {
    return (
      <View style={{
        flexDirection: props.vertical ? "column" : "row",
        padding: props.vertical ? 9 : 4, gap: props.vertical ? 6 : 2,
        backgroundColor: palette.surface, borderColor: palette.border,
        borderRightWidth: props.vertical ? 1 : 0,
        borderTopWidth: props.vertical ? 0 : 1,
      }}>
        <Each of={tabs}>
          {(item) => (
            <View
              accessibilityRole="button"
              accessibilityLabel={item().label}
              accessibilityState={{ selected: tab() === item().key }}
              onPress={() => changeTab(item().key)}
              style={{
                flex: props.vertical ? 0 : 1,
                minWidth: 0, minHeight: 44, borderRadius: 10,
                justifyContent: "center", alignItems: "center",
                paddingHorizontal: 2, paddingVertical: 7,
                backgroundColor: tab() === item().key ? palette.accent : palette.raised,
              }}
            >
              <Text style={{
                fontSize: props.vertical ? 13 : 11, fontWeight: "600",
                color: tab() === item().key ? palette.onAccent : palette.accent,
                textAlign: "center",
              }}>{item().label}</Text>
            </View>
          )}
        </Each>
      </View>
    );
  }

  function Content() {
    return (
      <View style={{ flex: 1 }}>
        <If when={tab() === "boards"} else={
          <If when={tab() === "users"} else={
          <If when={tab() === "categories"} else={
          <If when={tab() === "about"} else={
            <If when={tab() === "search"} else={
              <FeedPage kind={readKind} category={category} tag={selectedTag}
                clearCategory={closeCategory} clearTag={closeTag}
                browseCategories={() => browseFilters("categories")}
                browseTags={() => browseFilters("tags")}
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
            <InfoPage nativeStatus={nativeStatus}
              retryNative={() => {void checkNativeHost();}} />
          </If>
        }>
          <If when={directoryMode() === "tags"} else={
            <CategoriesPage categories={categories} loading={categoriesLoading}
              error={categoriesError} refresh={() => { void refreshCategories(); }}
              select={openCategory} showTags={showTagDirectory}
              filterHint={() => selectedTag() ? "#" + selectedTag()!.name : ""}
              backToResults={backToResults} />
          }>
            <TagsPage tags={tags} loading={tagsLoading} error={tagsError}
              refresh={() => { void refreshTags(); }} select={openTag}
              showCategories={showCategoryDirectory}
              filterHint={() => category()?.name ?? ""}
              backToResults={backToResults} />
          </If>
          </If>
        }>
          <ProfilePage username={profileName} changeUsername={changeProfileName}
            lookup={() => { void lookupProfile(); }} loading={profileLoading}
            attempted={profileAttempted} error={profileError} profile={userProfile} />
          </If>
        }>
          <BoardsPage boards={boards} loading={boardsLoading} error={boardsError}
            refresh={() => { void refreshBoards(); }} active={activeBoard}
            detail={boardDetail} detailLoading={boardDetailLoading}
            detailError={boardDetailError}
            openBoard={(board) => { void openBoard(board); }}
            retryDetail={() => { const board = activeBoard(); if (board) void openBoard(board); }}
            openTopic={openTopic} />
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
