# Tab 焦点切换 - 交互回归测试说明

本文档覆盖 `widget:keyreleased` 中 Tab 键焦点切换的所有关键场景，
用于手动回归验证。每个场景给出前置条件、操作步骤、预期结果。

---

## 1. 普通顺序切换

**前置条件**

创建一个 `context`，依次添加三个可交互控件（button / textfield / checkbox）。

```lua
local c = context()
local b1 = button("b1", {value = "A"})
local tf = textfield("tf", {value = ""})
local b2 = button("b2", {value = "B"})
c:add(b1, tf, b2)
c:update(0)
```

**操作步骤**

| 步骤 | 动作                  |
|------|-----------------------|
| 1    | 按 Tab                |
| 2    | 再按 Tab              |
| 3    | 再按 Tab              |

**预期结果**

| 步骤 | `c:deepfocused()` | 说明                       |
|------|-------------------|----------------------------|
| 1    | b1                | 焦点落到第一个可交互控件    |
| 2    | tf                | 焦点前进到 textfield        |
| 3    | b2                | 焦点前进到第二个 button     |

**验证点**
- 每次切换，旧控件的 `ui.focus` 标签被移除，新控件获得 `ui.focus` 标签。
- `onblur` 回调在旧控件上触发，`onfocus` 回调在新控件上触发，且顺序为 blur 先于 focus。

---

## 2. 末尾回绕（Wraparound）

**前置条件**

同场景 1，三个控件 b1 → tf → b2。

**操作步骤**

| 步骤 | 动作                                |
|------|-------------------------------------|
| 1    | 按 Tab 三次，焦点到达 b2（最后一个）|
| 2    | 再按 Tab 一次                       |

**预期结果**

| 步骤 | `c:deepfocused()` | 说明                       |
|------|-------------------|----------------------------|
| 2    | b1                | 焦点从末尾回到开头（回绕）  |

**验证点**
- 焦点不会丢失（不会变成 nil）。
- 回绕时 blur/focus 回调正常触发。

---

## 3. 跳过禁用控件（disabled）

**前置条件**

```lua
local c = context()
local b1 = button("b1", {value = "A"})
local b2 = button("b2", {value = "B", disabled = true})
local b3 = button("b3", {value = "C"})
c:add(b1, b2, b3)
c:update(0)
```

**操作步骤**

| 步骤 | 动作     |
|------|----------|
| 1    | 按 Tab   |
| 2    | 再按 Tab |

**预期结果**

| 步骤 | `c:deepfocused()` | 说明                           |
|------|-------------------|--------------------------------|
| 1    | b1                | 焦点落到第一个 button           |
| 2    | b3                | b2 被跳过（disabled=true）     |

**验证点**
- 禁用的 b2 永远不会获得 `ui.focus` 标签。
- b2 的 `onfocus` 回调不会被触发。

---

## 4. 跳过隐藏控件（display = "none"）

**前置条件**

```lua
local c = context()
local b1 = button("b1", {value = "A"})
local b2 = button("b2", {value = "B"})
local b3 = button("b3", {value = "C"})
c:add(b1, b2, b3)
-- 通过 style 隐藏 b2
c:add(style("b2", {display = "none"}))
c:update(0)
```

**操作步骤**

| 步骤 | 动作     |
|------|----------|
| 1    | 按 Tab   |
| 2    | 再按 Tab |

**预期结果**

| 步骤 | `c:deepfocused()` | 说明                           |
|------|-------------------|--------------------------------|
| 1    | b1                | 焦点落到第一个 button           |
| 2    | b3                | b2 被跳过（display=none）      |

**验证点**
- 隐藏的控件不参与焦点流转。
- 如果将 b2 的 style 移除（恢复可见），再次 Tab 时 b2 应该重新加入焦点顺序。

---

## 5. 跳过非交互控件（label、纯容器）

**前置条件**

```lua
local c = context()
local lb = label("lb", {value = "Label"})
local b1 = button("b1", {value = "A"})
local b2 = button("b2", {value = "B"})
c:add(lb, b1, b2)
c:update(0)
```

**操作步骤**

| 步骤 | 动作     |
|------|----------|
| 1    | 按 Tab   |

**预期结果**

| 步骤 | `c:deepfocused()` | 说明                       |
|------|-------------------|----------------------------|
| 1    | b1                | label 被跳过（tabstop=false）|

**验证点**
- label 等 `tabstop=false` 的控件不在焦点列表中。
- 纯容器 widget（没有设置 `tabstop=true`）同样被跳过。

---

## 6. 无可用焦点控件时按 Tab

**前置条件**

```lua
local c = context()
local lb = label("lb", {value = "Only label"})
c:add(lb)
c:update(0)
```

**操作步骤**

| 步骤 | 动作     |
|------|----------|
| 1    | 按 Tab   |

**预期结果**

- 无报错。
- `c.focused` 保持原值（nil 或之前的状态），不被破坏。
- 不触发任何 blur/focus 回调。

---

## 7. 嵌套容器中的焦点流转

**前置条件**

```lua
local c = context()
local b1 = button("b1", {value = "Outer"})
local form = widget("form")
local b2 = button("b2", {value = "Inner1"})
local b3 = button("b3", {value = "Inner2"})
form:add(b2, b3)
c:add(b1, form)
c:update(0)
```

**操作步骤**

| 步骤 | 动作     |
|------|----------|
| 1    | 按 Tab   |
| 2    | 再按 Tab |
| 3    | 再按 Tab |
| 4    | 再按 Tab |

**预期结果**

| 步骤 | `c:deepfocused()` | `c.focused` | `form.focused` | 说明                       |
|------|-------------------|-------------|----------------|----------------------------|
| 1    | b1                | b1          | nil            | 焦点在外层 button           |
| 2    | b2                | form        | b2             | 焦点进入嵌套容器的第一个控件|
| 3    | b3                | form        | b3             | 焦点在嵌套容器内前进        |
| 4    | b1                | b1          | nil            | 焦点回绕到外层              |

**验证点**
- `getfocusables()` 深度遍历嵌套容器，返回扁平列表 [b1, b2, b3]。
- `focustarget()` 在切换时正确设置每一层容器的 `focused`。
- 嵌套容器 `form` 本身不获得 `ui.focus` 标签（它不是 tabstop）。

---

## 8. blur/focus 回调触发顺序

**前置条件**

```lua
local c = context()
local b1 = button("b1", {value = "A"})
local b2 = button("b2", {value = "B"})
c:add(b1, b2)
c:update(0)

local log = {}
b1:onblur(function(self)  table.insert(log, "blur-b1")  end)
b1:onfocus(function(self) table.insert(log, "focus-b1") end)
b2:onblur(function(self)  table.insert(log, "blur-b2")  end)
b2:onfocus(function(self) table.insert(log, "focus-b2") end)
```

**操作步骤**

| 步骤 | 动作                   |
|------|------------------------|
| 1    | 按 Tab（焦点到 b1）    |
| 2    | 再按 Tab（焦点到 b2）  |

**预期 log 内容**

```
{"focus-b1", "blur-b1", "focus-b2"}
```

**验证点**
- 第一次 Tab：只有 `focus-b1`（之前无焦点，无 blur）。
- 第二次 Tab：`blur-b1` 先于 `focus-b2`，不会出现标签已切换但回调延迟的情况。

---

## 9. 动态禁用/启用后的焦点行为

**前置条件**

```lua
local c = context()
local b1 = button("b1", {value = "A"})
local b2 = button("b2", {value = "B"})
local b3 = button("b3", {value = "C"})
c:add(b1, b2, b3)
c:update(0)
```

**操作步骤**

| 步骤 | 动作                                      |
|------|-------------------------------------------|
| 1    | Tab 到 b2                                 |
| 2    | 动态禁用 b3：`b3.attributes.disabled=true` |
| 3    | 按 Tab                                    |

**预期结果**

| 步骤 | `c:deepfocused()` | 说明                           |
|------|-------------------|--------------------------------|
| 1    | b2                | 正常到达 b2                     |
| 3    | b1                | b3 被跳过，回绕到 b1            |

**验证点**
- `focusable()` 在每次 Tab 时实时计算，不依赖缓存。
- 动态修改 `disabled` 后立即生效。

---

## 10. Shift+Tab 预留（当前未实现）

当前实现仅处理 `"tab"` 键。如果需要 Shift+Tab 反向切换，
可在 `keyreleased` 中增加对 `shifton()` 的判断来反转方向。
此处记录为后续扩展点，不做回归验证。

---

## 自动化测试用例

以下测试可追加到 `widget.lua` 底部的 `test()` 块中：

```lua
test("ui.widget.tab.focusable", function()
    local b = button("b", {value = "x"})
    local l = label("l", {value = "y"})
    assert(b:focusable() == true, "button is focusable")
    assert(l:focusable() == false, "label is not focusable")
    b.attributes.disabled = true
    assert(b:focusable() == false, "disabled button is not focusable")
    return true
  end)

test("ui.widget.tab.getfocusables", function()
    local c = context()
    local b1 = button("b1", {value = "A"})
    local l  = label("l",  {value = "L"})
    local b2 = button("b2", {value = "B"})
    c:add(b1, l, b2)
    c:update(0)
    local f = c:getfocusables()
    assert(#f == 2, "only 2 focusable widgets (label skipped)")
    assert(f[1] == b1 and f[2] == b2, "order is b1, b2")
    return true
  end)

test("ui.widget.tab.wraparound", function()
    local c = context()
    local b1 = button("b1", {value = "A"})
    local b2 = button("b2", {value = "B"})
    c:add(b1, b2)
    c:update(0)
    c:keyreleased("tab")
    assert(c:deepfocused() == b1, "first tab -> b1")
    c:keyreleased("tab")
    assert(c:deepfocused() == b2, "second tab -> b2")
    c:keyreleased("tab")
    assert(c:deepfocused() == b1, "third tab wraps -> b1")
    return true
  end)

test("ui.widget.tab.skip.disabled", function()
    local c = context()
    local b1 = button("b1", {value = "A"})
    local b2 = button("b2", {value = "B", disabled = true})
    local b3 = button("b3", {value = "C"})
    c:add(b1, b2, b3)
    c:update(0)
    c:keyreleased("tab")
    assert(c:deepfocused() == b1, "tab -> b1")
    c:keyreleased("tab")
    assert(c:deepfocused() == b3, "tab skips disabled b2 -> b3")
    return true
  end)

test("ui.widget.tab.empty", function()
    local c = context()
    local l = label("l", {value = "only label"})
    c:add(l)
    c:update(0)
    c:keyreleased("tab")  -- should not error
    assert(c:deepfocused() == nil or c:deepfocused() == c,
           "no crash, focus unchanged")
    return true
  end)

test("ui.widget.tab.nested", function()
    local c = context()
    local b1 = button("b1", {value = "Outer"})
    local form = widget("form")
    local b2 = button("b2", {value = "Inner1"})
    local b3 = button("b3", {value = "Inner2"})
    form:add(b2, b3)
    c:add(b1, form)
    c:update(0)
    c:keyreleased("tab")
    assert(c:deepfocused() == b1, "tab -> b1")
    c:keyreleased("tab")
    assert(c:deepfocused() == b2, "tab -> b2 (inside form)")
    assert(c.focused == form, "c.focused points to form")
    c:keyreleased("tab")
    assert(c:deepfocused() == b3, "tab -> b3")
    c:keyreleased("tab")
    assert(c:deepfocused() == b1, "tab wraps -> b1")
    return true
  end)
```
