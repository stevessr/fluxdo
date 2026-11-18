#!/usr/bin/env python3
"""验证 Android 外部插件注册契约与无桌面启动入口。"""

from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID = "{http://schemas.android.com/apk/res/android}"
ACTION = "com.github.lingyan000.fluxdo.action.PLUGIN"
META_VERSION = "com.github.lingyan000.fluxdo.plugin.API_VERSION"

host = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml").getroot()
plugin = ET.parse(ROOT / "packages/stevessr_generator/example/android/app/src/main/AndroidManifest.xml").getroot()

def attrs(el, key):
    return el.get(ANDROID + key)

def has_action(filter_element, action):
    return any(attrs(a, "name") == action for a in filter_element.findall("action"))

activities = plugin.findall("./application/activity")
matching = [
    activity for activity in activities
    if any(has_action(f, ACTION) for f in activity.findall("intent-filter"))
]
assert len(matching) == 1, "插件必须声明且仅声明一个 Fluxdo 发现入口"
activity = matching[0]
assert attrs(activity, "exported") == "true", "插件入口必须可被宿主启动"
assert any(
    attrs(m, "name") == META_VERSION and attrs(m, "value") == "1"
    for m in activity.findall("meta-data")
), "插件入口缺少 API 版本声明"
assert any(
    attrs(m, "name") == "com.github.lingyan000.fluxdo.plugin.CATEGORY"
    and attrs(m, "value") == "editor"
    for m in activity.findall("meta-data")
), "表情生成器必须声明 editor 插件类型"
assert any(
    any(attrs(c, "name") == "android.intent.category.DEFAULT" for c in f.findall("category"))
    for f in activity.findall("intent-filter") if has_action(f, ACTION)
), "插件发现入口必须声明 DEFAULT 类别"
assert not any(
    has_action(f, "android.intent.action.MAIN")
    and any(attrs(c, "name") == "android.intent.category.LAUNCHER" for c in f.findall("category"))
    for a in plugin.findall("./application/activity") + plugin.findall("./application/activity-alias")
    for f in a.findall("intent-filter")
), "插件不应该产生桌面图标"
assert any(
    has_action(query, ACTION) for query in host.findall("./queries/intent")
), "Fluxdo 必须声明插件可见性查询"
print("Android external plugin manifest contract OK")
