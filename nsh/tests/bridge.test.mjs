import assert from "node:assert/strict";
import { test } from "node:test";
import {
  HostBridge, HostProtocolError, validateHostCommand, unavailableHostTransport,
  HOST_PROTOCOL_VERSION, MAX_RESPONSE_BYTES,
} from "../host_protocol.ts";

const feedCommand = {method:"feed.list", params:{kind:"latest"}};
function mock(reply) {
  return {async invoke(req){return reply(req);}};
}

test("支持版本化只读请求与严格响应 ID 检查", async () => {
  const commands = [];
  const bridge = new HostBridge(mock(async (req)=>{
    commands.push(req);
    return {protocol:HOST_PROTOCOL_VERSION,id:req.id,ok:true,data:{topics:[]}};
  }));
  assert.deepEqual(await bridge.invoke(feedCommand),{topics:[]});
  assert.deepEqual(await bridge.invoke({method:"capabilities.read",params:{}}),{topics:[]});
  assert.deepEqual(commands.map(c=>c.id),[1,2]);
  assert.equal(commands[0].protocol,1);
  assert.equal(commands[0].method,"feed.list");
});

test("拒绝未列入只读白名单的命令、意外字段和凭据泄漏", () => {
  for (const value of [
    {method:"account.login",params:{password:"secret"}},
    {method:"feed.list",params:{kind:"latest",cookie:"secret"}},
    {method:"topic.read",params:{topicId:-1}},
    {method:"search.query",params:{term:"ok",page:51}},
    {method:"capabilities.read",params:{token:"secret"}},
    {method:"feed.list",params:{kind:"latest",cursor:"https://evil.test/a"}},
    {method:"feed.list",params:{kind:"latest",cursor:"/top/weekly?page=3"}},
    {method:"feed.list",params:{kind:"latest",cursor:"/latest?page=2&api_key=secret"}},
    {method:"feed.list",params:{kind:"top",cursor:"/top?page=2"}},
    {method:"feed.list",params:{kind:"latest",cursor:"/latest?page=2&page=3"}},
    {method:"feed.list",params:{kind:"latest"},cookie:"secret"},
    {method:"search.query",params:{term:"x\nsecret",page:1}},
  ]) {
    assert.throws(()=>validateHostCommand(value),
      (err)=>err instanceof HostProtocolError && err.code==="invalid_command");
  }
});

test("错版本、错误请求 ID、响应过大和错误包装均被拒绝", async () => {
  const cases = [
    [{protocol:2,id:1,ok:true,data:{}}, "invalid_reply"],
    [{protocol:1,id:9,ok:true,data:{}}, "invalid_reply"],
    [{protocol:1,id:1,ok:true}, "invalid_reply"],
    [{protocol:1,id:1,ok:true,data:"x".repeat(MAX_RESPONSE_BYTES)}, "oversized_frame"],
    [{protocol:1,id:1,ok:false,error:{code:"unknown",message:"API_KEY=secret"}}, "internal"],
    [{protocol:1,id:1,ok:false,error:{code:"rate_limited",message:"wait"}}, "rate_limited"],
  ];
  for (const [response, code] of cases) {
    await assert.rejects(new HostBridge(mock(async()=>response)).invoke(feedCommand),
      (err)=>err instanceof HostProtocolError && err.code===code);
  }
});

test("账号或页面切换能废弃未返回的旧结果", async () => {
  let resolve;
  const bridge = new HostBridge(mock(()=>new Promise(r=>{resolve=r;})));
  const pending = bridge.invoke(feedCommand);
  bridge.invalidatePending();
  resolve({protocol:1,id:1,ok:true,data:{account:"old"}});
  await assert.rejects(pending,
    (err)=>err instanceof HostProtocolError && err.code==="superseded");
});

test("native 异常不暴露底层消息；未安装 transport 时关闭操作", async () => {
  const broken = new HostBridge(mock(async()=>{throw Error("token=secret")}));
  await assert.rejects(broken.invoke(feedCommand),
    (err)=>err instanceof HostProtocolError &&
      err.code==="transport_error" && !err.message.includes("secret"));
  const unavailable = new HostBridge(unavailableHostTransport);
  await assert.rejects(unavailable.invoke(feedCommand),
    (err)=>err instanceof HostProtocolError && err.code==="unavailable");
});

test("Host 接受限定信息流的安全分页游标", () => {
  assert.doesNotThrow(() => validateHostCommand(
    {method:"feed.list",params:{kind:"latest",cursor:"/latest.json?page=2"}}));
  assert.doesNotThrow(() => validateHostCommand(
    {method:"feed.list",params:{kind:"top",cursor:"/top/weekly?before=123"}}));
  assert.doesNotThrow(() => validateHostCommand(
    {method:"feed.list",params:{kind:"top",cursor:"/top?period=weekly&page=2"}}));
});
