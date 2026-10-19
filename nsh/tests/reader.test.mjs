import assert from "node:assert/strict";
import { test } from "node:test";
import {
  decodeEntities, cookedToText, parseCategories, parseTopics, parsePosts,
  dedupeTopics, feedPath, topicPath, createPublicReader,
} from "../data.ts";
import { RequestGate } from "../request_gate.ts";

const topic = {
  id: 42, slug: "hello-world", title: "Hello &amp; World",
  category_id: 8, views: 240, posts_count: 3, like_count: 2, tags: ["rust", "nsh"],
};
const category = { id: 8, slug: "development", name: "开发 &amp; 工具", topic_count: 99 };

test("解析公开话题并严格过滤异常 ID", () => {
  const result = parseTopics({
    topic_list: { topics: [topic, { id: -1, title: "无效", slug: "broken" }],
      more_topics_url: "/latest?page=1" },
  });
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].title, "Hello & World");
  assert.equal(result.items[0].categoryId, 8);
  assert.equal(result.hasMore, true);
  assert.equal(parseTopics({ topic_list: { topics: [], more_topics_url: null } }).hasMore, false);
});

test("解析分类与失败数据", () => {
  assert.deepEqual(parseCategories({category_list:{categories:[category]}}),
    [{id:8,slug:"development",name:"开发 & 工具",topicCount:99}]);
  assert.throws(() => parseCategories({foo:1}), /数据格式不正确/);
  assert.throws(() => parseTopics({topic_list:{}}), /字段缺失/);
});

test("处理 cooked HTML 时剥除主动内容、保留换行与实体", () => {
  const input = "<p>你好 &amp; Rust</p><script>alert(1)</script>" +
    "<style>body{}</style><iframe>evil</iframe><p>第二行<br>继续</p>";
  const text = cookedToText(input);
  assert.equal(text, "你好 & Rust\n第二行\n继续");
  assert.equal(decodeEntities("&#x1F431; &lt;"), "🐱 <");
  assert.equal(decodeEntities("&#xD800;"), "&#xD800;");
});

test("帖子纯文本与长度受限", () => {
  const posts = parsePosts({post_stream:{posts:[
    {id:12,post_number:1,username:"alex",cooked:"<p>Hello</p>"},
    {id:0,post_number:2,username:"bot",cooked:"no"},
  ]}});
  assert.deepEqual(posts, [{id:12,number:1,author:"alex",text:"Hello"}]);
});

test("按 ID 合并分页而不重复显示", () => {
  const first = parseTopics({topic_list:{topics:[topic]}}).items;
  const second = parseTopics({topic_list:{topics:[topic,{...topic,id:43}]}}).items;
  assert.deepEqual(dedupeTopics(first,second).map(x=>x.id),[42,43]);
});

test("服务路径严格编码并验证页码", () => {
  assert.equal(feedPath("latest",null,0), "/latest.json?page=0");
  assert.equal(feedPath("top",null,2), "/top.json?period=weekly&page=2");
  assert.equal(feedPath("latest",{...category,slug:"a/b"},1), "/c/a%2Fb/8.json?page=1");
  assert.equal(topicPath({...parseTopics({topic_list:{topics:[topic]}}).items[0],slug:"a/b"}),
    "/t/a%2Fb/42.json");
  assert.throws(()=>feedPath("latest",null,-1), /页码/);
  assert.throws(()=>feedPath("latest",null,1.5), /页码/);
});

test("请求门禁可阻断切换后过期响应", () => {
  const gate = new RequestGate();
  const old = gate.next(), current = gate.next();
  assert.equal(gate.isCurrent(old),false);
  assert.equal(gate.isCurrent(current),true);
  gate.invalidate();
  assert.equal(gate.isCurrent(current),false);
});

test("网络适配器可注入，且只做读取", async () => {
  const paths = [];
  const reader = createPublicReader(async (path) => {
    paths.push(path);
    if (path.startsWith("/categories")) return {category_list:{categories:[category]}};
    if (path.startsWith("/t/")) return {post_stream:{posts:[]}};
    return {topic_list:{topics:[topic]}};
  });
  assert.equal((await reader.categories())[0].id,8);
  assert.equal((await reader.topics("latest",null,0)).items.length,1);
  assert.deepEqual(await reader.posts({
    id:42,slug:"hello-world",title:"Hi",categoryId:8,views:1,postsCount:2,likeCount:0,tags:[],
  }),[]);
  assert.deepEqual(paths, [
    "/categories.json","/latest.json?page=0","/t/hello-world/42.json",
  ]);
});
