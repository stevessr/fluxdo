import assert from "node:assert/strict";
import { test } from "node:test";
import {
  decodeEntities, cookedToText, parseCategories, parseTopics, parsePosts,
  dedupeTopics, feedPath, topicPath, createPublicReader,
  normalizeFeedCursor, parseTopicDetail, postsBatchPath, mergePosts, POSTS_PER_BATCH,
  searchPath, parseSearchResults, mergeSearchHits, feedCursorForContext, publicReader,
  parseUserProfile, userProfilePath, parseBoards, parseBoardDetail, boardDetailPath,
  parseTags, tagPath, tagCursorForContext, categoryTagPath, categoryTagCursorForContext,
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
  assert.equal(result.nextCursor, "/latest.json?page=1");
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

test("只使用同站白名单分页游标并补齐 JSON 后缀", () => {
  assert.equal(normalizeFeedCursor("/top/weekly?page=2"), "/top/weekly.json?page=2");
  assert.equal(normalizeFeedCursor("https://linux.do/c/dev/12/l/latest?page=3"),
    "/c/dev/12/l/latest.json?page=3");
  assert.equal(normalizeFeedCursor("/latest.json?page=4"), "/latest.json?page=4");
  for (const unsafe of [
    "//evil.test/latest?page=1", "https://evil.test/latest?page=1",
    "/admin/users?page=2", "/latest?redirect=https://evil.test&page=2",
    "/latest?\r\npage=2", "/latest/../admin?page=2",
    "/latest?token=abc", "/latest?page=1#fragment",
    "/latest%2fadmin?page=2",
  ]) assert.equal(normalizeFeedCursor(unsafe), null, unsafe);
});

test("Topic stream 为后续楼层提供顺序去重的 ID", () => {
  const response = { post_stream: { posts: [
    {id: 8, post_number: 1, username: "a", cooked: "<p>首帖</p>"},
  ], stream: [8, 9, 9, -1, 10, "bad", 11] } };
  assert.deepEqual(parseTopicDetail(response).remainingIds, [9, 10, 11]);
  const merged = mergePosts(parseTopicDetail(response).posts,
    [{id:10,number:3,author:"b",text:"3"},
     {id:9,number:2,author:"b",text:"2"},
     {id:10,number:3,author:"b",text:"3"}]);
  assert.deepEqual(merged.map((p)=>p.id), [8, 9, 10]);
});

test("帖子流分批读取严格限定 20 个正整数 ID", async () => {
  const item = {id:42,slug:"hello-world",title:"Hi",categoryId:8,views:1,postsCount:41,likeCount:0,tags:[]};
  assert.equal(POSTS_PER_BATCH, 20);
  assert.equal(postsBatchPath(item,[8,9]),"/t/42/posts.json?post_ids%5B%5D=8&post_ids%5B%5D=9");
  assert.throws(()=>postsBatchPath(item,[0]),/无效/);
  assert.throws(()=>postsBatchPath(item,Array.from({length:21},(_,i)=>i+1)),/无效/);
  const paths=[];
  const reader=createPublicReader(async(path)=>{
    paths.push(path);
    if (path.includes("/posts.json?")) return {post_stream:{posts:[{id:9,post_number:2,username:"b",cooked:"<p>ok</p>"}]}};
    if (path.includes(".json")) return {post_stream:{posts:[],stream:[9]}};
    throw Error("unexpected");
  });
  assert.deepEqual((await reader.detail(item)).remainingIds,[9]);
  assert.deepEqual((await reader.morePosts(item,[9])).map(p=>p.id),[9]);
  assert.deepEqual(paths,["/t/hello-world/42.json","/t/42/posts.json?post_ids%5B%5D=9"]);
  await assert.rejects(reader.topics("latest",null,"https://evil.test/latest?page=2"),/游标无效/);
});

test("公开搜索 URL 编码、控制字符、长度和页码约束", () => {
  assert.equal(searchPath("  Rust Flutter  ", 1), "/search.json?q=Rust%20Flutter&page=1");
  assert.equal(searchPath("中文 + #话题", 2),
    "/search.json?q=%E4%B8%AD%E6%96%87%20%2B%20%23%E8%AF%9D%E9%A2%98&page=2");
  for (const input of ["", "a", "x".repeat(121), "hello\nworld", "x\u0000y"]) {
    assert.throws(() => searchPath(input,1), /搜索词/);
  }
  for (const page of [0,-1,1.5,51,Infinity]) {
    assert.throws(() => searchPath("linux",page), /页码/);
  }
});

test("搜索匹配帖子、话题及 HTML 摘要安全解析", () => {
  const data = {
    topics: [
      {...topic, id:42, title:"Hello &amp; NSH"},
      {...topic, id:43, title:"Only title"},
      {id:-4,title:"bad"},
    ],
    posts: [
      {id:98, topic_id:42, post_number:3, blurb:"<strong>匹配</strong> &amp; <script>bad()</script>安全"},
      {id:98, topic_id:42, post_number:3, blurb:"duplicate"},
      {id:99, topic_id:999, post_number:1, blurb:"unknown topic"},
    ],
    grouped_search_result: {more_full_page_results:"/search?q=nsh&page=2"},
  };
  const page = parseSearchResults(data);
  assert.equal(page.hasMore, true);
  assert.deepEqual(page.items.map((h) => [h.topic.id,h.postNumber]), [[42,3],[43,null]]);
  assert.equal(page.items[0].topic.title,"Hello & NSH");
  assert.equal(page.items[0].excerpt,"匹配 & 安全");
  assert.deepEqual(
    mergeSearchHits(page.items,[page.items[0],{topic:page.items[1].topic,postNumber:2,excerpt:"later"}])
      .map(h=>[h.topic.id,h.postNumber]),
    [[42,3],[43,null],[43,2]],
  );
  assert.equal(parseSearchResults({topics:[],posts:[],grouped_search_result:{}}).hasMore,false);
  assert.throws(()=>parseSearchResults({topics:[]}), /字段缺失/);
});

test("公开搜索只使用编码后的站内路径，不含任何身份凭证", async () => {
  const paths = [];
  const reader = createPublicReader(async (path) => {
    paths.push(path);
    return {topics:[topic], posts:[], grouped_search_result:{}};
  });
  const page = await reader.search("nsh 测试",1);
  assert.equal(page.items.length,1);
  assert.deepEqual(paths,["/search.json?q=nsh%20%E6%B5%8B%E8%AF%95&page=1"]);
  await assert.rejects(reader.search("bad\rquery",1),/搜索词/);
  assert.equal(paths.length,1);
});

test("搜索命中的楼层从服务端获取相邻帖子，而非按帖子 ID 猜测", async () => {
  const item = {id:42,slug:"hello-world",title:"Hi",categoryId:8,views:1,postsCount:240,likeCount:0,tags:[]};
  assert.equal(topicPath(item,120),"/t/hello-world/42/120.json");
  assert.equal(topicPath(item,null),"/t/hello-world/42.json");
  for (const n of [0,-1,1.5,Infinity,10000001]) {
    assert.throws(()=>topicPath(item,n),/楼层号无效/);
  }
  const paths=[];
  const reader=createPublicReader(async(path)=>{
    paths.push(path);
    return {post_stream:{posts:[{id:9001,post_number:120,username:"author",cooked:"<p>target</p>"}],stream:[9001]}};
  });
  assert.deepEqual((await reader.detail(item,120)).posts.map(p=>p.number),[120]);
  assert.deepEqual(paths,["/t/hello-world/42/120.json"]);
});

test("分页游标不能跨信息流、跨分类或携带未知查询字段", async () => {
  assert.equal(feedCursorForContext("/latest?page=2", "latest", null), "/latest.json?page=2");
  assert.equal(feedCursorForContext("/top/weekly?before=99", "top", null), "/top/weekly.json?before=99");
  assert.equal(feedCursorForContext("/top?period=weekly&page=2", "top", null),
    "/top.json?period=weekly&page=2");
  assert.equal(feedCursorForContext("/c/development/8/l/latest?page=3", "latest",
    {id:8,slug:"development",name:"开发",topicCount:8}), "/c/development/8/l/latest.json?page=3");
  for (const value of [
    "/latest?page=1&api_key=secret", "/latest?page=1&redirect=evil",
    "/latest?page=1&page=2", "/latest?before=-1", "/latest?before=9007199254740992",
    "/latest?page=1001", "/latest/weekly?page=1", "/latest?page=1;token=x",
    "/latest?page=1&token=abc", "/latest?period=weekly&page=2",
  ]) assert.equal(normalizeFeedCursor(value), null, value);
  assert.equal(feedCursorForContext("/top/weekly?page=2", "latest", null), null);
  assert.equal(feedCursorForContext("/c/other/8?page=2", "latest",
    {id:8,slug:"development",name:"开发",topicCount:8}), null);

  const reader = createPublicReader(async () => ({
    topic_list: {topics:[topic],more_topics_url:"/top/weekly?page=2"},
  }));
  const page = await reader.topics("latest",null,0);
  assert.equal(page.hasMore,false);
  assert.equal(page.nextCursor,null);
  await assert.rejects(reader.topics("latest",null,"/top/weekly?page=2"),/分页游标无效/);
});

test("公开请求明确禁用凭据和重定向", async () => {
  const previous = globalThis.fetch;
  try {
    globalThis.fetch = async (url, options) => {
      assert.equal(url, "https://linux.do/categories.json");
      assert.equal(options.credentials, "omit");
      assert.equal(options.redirect, "error");
      assert.equal(options.headers.Accept, "application/json");
      return {ok:true,json:async()=>({category_list:{categories:[category]}})};
    };
    assert.equal((await publicReader.categories())[0].id,8);
  } finally {
    globalThis.fetch = previous;
  }
});

test("公开个人资料查询只允许单段用户名，不读取隐私属性", async () => {
  assert.equal(userProfilePath(" @steve.ssr "), "/u/steve.ssr.json");
  assert.equal(userProfilePath("steve-1"), "/u/steve-1.json");
  for (const invalid of ["", "@", "..", "../admin", "a/b", "x?api_key=secret",
    "name#hash", "bad\\name", "a".repeat(61)]) {
    assert.throws(() => userProfilePath(invalid), /用户名格式无效/, invalid);
  }
  const user = {id:12,username:"steve.ssr",name:"Steve &amp; SSR",
    title:"开发者",trust_level:3,post_count:91,
    bio_cooked:"<p>Hi &amp; welcome</p><script>alert(1)</script>",
    email:"private@example.com",api_key:"secret"};
  assert.deepEqual(parseUserProfile({user}),{
    id:12,username:"steve.ssr",name:"Steve & SSR",title:"开发者",
    trustLevel:3,postCount:91,bio:"Hi & welcome",
  });
  assert.throws(() => parseUserProfile({user:{username:"invalid"}}),/字段缺失/);
  const paths=[];
  const reader=createPublicReader(async path => {
    paths.push(path);
    return {user};
  });
  assert.equal((await reader.profile("@steve.ssr")).id,12);
  assert.deepEqual(paths,["/u/steve.ssr.json"]);
  await assert.rejects(reader.profile("../admin"),/用户名格式无效/);
  assert.equal(paths.length,1);
});

test("Boards 目录去重、忽略归档并保留匿名访问权限", () => {
  const boards=parseBoards({boards:[
    {id:1,name:"Sprint &amp; Roadmap",slug:"sprint",anonymous_can_read:true,
      columns:[{id:1}],archived:false},
    {id:2,unicode_name:"私有看板",slug:"private",anonymous_can_read:false},
    {id:1,name:"重复",anonymous_can_read:true},
    {id:3,name:"Archived",archived:true},
    {id:-1,name:"Invalid"},
  ]});
  assert.deepEqual(boards,[
    {id:1,name:"Sprint & Roadmap",slug:"sprint",anonymousCanRead:true,columnCount:1},
    {id:2,name:"私有看板",slug:"private",anonymousCanRead:false,columnCount:0},
  ]);
  assert.throws(() => parseBoards({boards:null}),/字段缺失/);
  assert.equal(boardDetailPath(42),"/boards/api/boards/42.json");
  for (const id of [0,-2,1.5,NaN,Number.MAX_SAFE_INTEGER+1]) {
    assert.throws(() => boardDetailPath(id),/看板 ID 无效/);
  }
});

test("Boards 列与 Topic/Floater 卡片安全投影，拒绝越权与错配 ID", async () => {
  const board={id:1,name:"公开",anonymous_can_read:true,slug:"topic"};
  const payload={board,columns:[
    {id:10,title:"待办",cards:[
      {id:100,card_type:"topic",topic:{id:99,slug:"hello-world",title:"Hello &amp; World",
        category_id:12,posts_count:4,tags:["linux","nsh"]},notes:""},
      {id:101,card_type:"floater",title:"提示",notes:"<p>安全</p><script>bad()</script>",
        api_key:"MUST_NOT_LEAK"},
      {id:101,card_type:"floater",title:"重复卡片"},
      {id:102,card_type:"unknown",title:"忽略"},
    ]},
    {id:11,title:"已完成",cards:[]},
  ]};
  const detail=parseBoardDetail(payload,1);
  assert.deepEqual(detail.columns.map(c=>c.title),["待办","已完成"]);
  assert.equal(detail.columns[0].cards.length,2);
  assert.equal(detail.columns[0].cards[0].topic.id,99);
  assert.equal(detail.columns[0].cards[0].topic.title,"Hello & World");
  assert.equal(detail.columns[0].cards[1].notes,"安全");
  assert.equal(JSON.stringify(detail).includes("MUST_NOT_LEAK"),false);
  assert.equal(detail.truncated,false);
  assert.throws(()=>parseBoardDetail(payload,2),/不可公开访问/);
  assert.throws(()=>parseBoardDetail({...payload,board:{...board,anonymous_can_read:false}},1),
    /不可公开访问/);
  assert.throws(()=>parseBoardDetail({board,columns:null},1),/栏目字段缺失/);
  const seen=[];
  const reader=createPublicReader(async path=>{
    seen.push(path);
    if (path==="/boards/api/boards.json") return {boards:[board]};
    if (path==="/boards/api/boards/1.json") return payload;
    throw new Error("unexpected URL "+path);
  });
  const list=await reader.boards();
  assert.equal(list.length,1);
  assert.equal((await reader.board(list[0])).columns.length,2);
  await assert.rejects(reader.board({...list[0],anonymousCanRead:false}),/需要登录/);
  assert.deepEqual(seen,["/boards/api/boards.json","/boards/api/boards/1.json"]);
});

test("Boards 巨量卡片限制为 500，避免超量渲染", () => {
  const cards=Array.from({length:700},(_,i)=>({id:i+1,card_type:"floater",title:"卡片"+i}));
  const detail=parseBoardDetail({
    board:{id:1,name:"Board",anonymous_can_read:true},
    columns:[{id:1,title:"A",cards}],
  },1);
  assert.equal(detail.columns[0].cards.length,500);
  assert.equal(detail.truncated,true);
});

test("Discourse 标签目录使用官方 tags.json 结构与可见 Canonical tag", () => {
  const tags=parseTags({tags:[
    {id:4,text:"Rust &amp; Go",slug:"rust-go",count:20,description:"<p>工具</p>"},
    {id:5,name:"Linux",slug:"linux",count:100},
    {id:6,name:"Synonym",slug:"syn",target_tag:{id:5,name:"Linux"}},
    {id:5,name:"Duplicate",slug:"dup",count:9},
    {id:0,name:"Invalid",slug:"bad"},
  ]});
  assert.deepEqual(tags,[
    {id:5,name:"Linux",slug:"linux",topicCount:100,description:""},
    {id:4,name:"Rust & Go",slug:"rust-go",topicCount:20,description:"工具"},
  ]);
  assert.throws(()=>parseTags({tags:null}),/字段缺失/);
  assert.equal(tagPath(tags[0],0),"/tag/linux/5.json?page=0");
  assert.equal(tagPath({...tags[0],slug:"a+b"},2),"/tag/a%2Bb/5.json?page=2");
  for(const id of [0,-1,1.5,Number.MAX_SAFE_INTEGER+1]){
    assert.throws(()=>tagPath({...tags[0],id},0),/标签 ID/);
  }
  for (const slug of ["../foo",".","..","foo/bar","foo\\bar"]) {
    assert.throws(()=>tagPath({...tags[0],slug},0),/标签 ID/);
  }
  assert.throws(()=>tagPath(tags[0],1001),/页码/);
});

test("标签分页服务端游标只允许当前标签与安全参数", async () => {
  const tag={id:7,name:"NSH",slug:"nsh",topicCount:12,description:""};
  assert.equal(tagCursorForContext("/tag/nsh/7?page=2",tag),"/tag/nsh/7.json?page=2");
  for(const input of [
    "/tag/other/7?page=2","/tag/nsh/8?page=2",
    "/tag/nsh/7?page=2&token=secret",
    "/tag/nsh/7?page=2&page=3",
    "https://attacker.test/tag/nsh/7?page=2",
    "/tag/nsh/7/../admin?page=2",
  ])assert.equal(tagCursorForContext(input,tag),null,input);
  const paths=[];
  const reader=createPublicReader(async path=>{
    paths.push(path);
    return {topic_list:{topics:[topic],more_topics_url:"/tag/nsh/7?page=3"}};
  });
  const result=await reader.tagTopics(tag,0);
  assert.equal(result.hasMore,true);
  assert.equal(result.nextCursor,"/tag/nsh/7.json?page=3");
  assert.equal((await reader.tagTopics(tag,result.nextCursor)).items.length,1);
  assert.deepEqual(paths,["/tag/nsh/7.json?page=0","/tag/nsh/7.json?page=3"]);
  await assert.rejects(reader.tagTopics(tag,"/latest?page=1"),/标签分页游标/);
  assert.equal(paths.length,2);
  const wrong=createPublicReader(async()=>({
    topic_list:{topics:[topic],more_topics_url:"/tag/other/9?page=4"},
  }));
  const last=await wrong.tagTopics(tag,0);
  assert.equal(last.hasMore,false);
});

test("category + tag routes use the canonical Discourse combination endpoint", () => {
  const c={id:8,slug:"development",name:"开发",topicCount:20};
  const tag={id:5,slug:"rust",name:"Rust",topicCount:8,description:""};
  assert.equal(categoryTagPath(c,tag,0),"/tags/c/development/8/rust/5.json?page=0");
  assert.equal(categoryTagPath(c,tag,2),"/tags/c/development/8/rust/5.json?page=2");
  assert.equal(categoryTagCursorForContext("/tags/c/development/8/rust/5?page=3",c,tag),
    "/tags/c/development/8/rust/5.json?page=3");
  assert.equal(categoryTagCursorForContext(
    "https://linux.do/tags/c/development/8/rust/5?page=3",c,tag),
    "/tags/c/development/8/rust/5.json?page=3");
  for(const raw of [
    "/tags/c/development/9/rust/5?page=3",
    "/tags/c/other/8/rust/5?page=3",
    "/tags/c/development/8/go/5?page=3",
    "/tags/c/development/8/rust/6?page=3",
    "/tags/c/development/8/rust/5?page=3&token=private",
    "/tags/c/development/8/rust/5?page=3&page=4",
    "/tags/c/development/8/rust/5?period=weekly",
    "https://attacker.test/tags/c/development/8/rust/5?page=3",
  ]) assert.equal(categoryTagCursorForContext(raw,c,tag),null,raw);
  for (const slug of ["..",".","foo/bar","foo\\bar"]) {
    assert.throws(() => categoryTagPath({...c,slug},tag,0),/分类 slug 无效/);
  }
  assert.throws(() => categoryTagPath({...c,id:-1},tag,0),/分类 ID 无效/);
  assert.throws(() => categoryTagPath(c,tag,1001),/页码/);
});

test("category + tag public reader fetches only scoped GET pages before and after parsing", async () => {
  const c={id:8,slug:"development",name:"开发",topicCount:20};
  const tag={id:5,slug:"rust",name:"Rust",topicCount:8,description:""};
  const paths=[];
  const reader=createPublicReader(async path=>{
    paths.push(path);
    return {topic_list:{topics:[topic],
      more_topics_url:"/tags/c/development/8/rust/5?page=1"}};
  });
  const initial=await reader.categoryTagTopics(c,tag,0);
  assert.equal(initial.items.length,1);
  assert.equal(initial.nextCursor,"/tags/c/development/8/rust/5.json?page=1");
  await reader.categoryTagTopics(c,tag,initial.nextCursor);
  assert.deepEqual(paths,[
    "/tags/c/development/8/rust/5.json?page=0",
    "/tags/c/development/8/rust/5.json?page=1",
  ]);
  for(const injected of [
    "/tags/c/development/8/go/5?page=1",
    "/latest?page=1",
    "/tags/c/development/8/rust/5?page=1&apikey=secret",
  ]) await assert.rejects(reader.categoryTagTopics(c,tag,injected),/分类标签分页游标无效/);
  assert.equal(paths.length,2);
  const wrong=createPublicReader(async()=>({topic_list:{topics:[topic],
    more_topics_url:"/tags/c/development/8/other/5?page=2"}}));
  const last=await wrong.categoryTagTopics(c,tag,0);
  assert.equal(last.hasMore,false);
  assert.equal(last.nextCursor,null);
});
