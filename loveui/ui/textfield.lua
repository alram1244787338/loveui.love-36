--- loveui is a love2d library to provide resuable GUI widgets to love2d 
-- developers.
module ("ui", package.seeall)

require "loveui/util/test"
require "loveui/util/class"
require "loveui/ui/widget"
require "loveui/ui/context"

textfield = class(widget)

--- Encode a Unicode codepoint into a UTF-8 byte string.
-- Handles codepoints from U+0000 to U+10FFFF.
-- @param codepoint Integer Unicode codepoint.
-- @return A UTF-8 encoded string.
local function utf8_encode(codepoint)
  if codepoint < 0x80 then
    return string.char(codepoint)
  elseif codepoint < 0x800 then
    return string.char(
      0xC0 + math.floor(codepoint / 0x40),
      0x80 + (codepoint % 0x40))
  elseif codepoint < 0x10000 then
    return string.char(
      0xE0 + math.floor(codepoint / 0x1000),
      0x80 + (math.floor(codepoint / 0x40) % 0x40),
      0x80 + (codepoint % 0x40))
  else
    return string.char(
      0xF0 + math.floor(codepoint / 0x40000),
      0x80 + (math.floor(codepoint / 0x1000) % 0x40),
      0x80 + (math.floor(codepoint / 0x40) % 0x40),
      0x80 + (codepoint % 0x40))
  end
end

--- Returns the byte position of the start of the UTF-8 character
-- immediately before the cursor position.
-- The cursor sits at a byte boundary (gap model); this finds the
-- start of the character that ends at that boundary.
-- @param str The UTF-8 string.
-- @param pos The cursor byte position (0-based gap).
-- @return The byte position (1-based) of the character start.
local function utf8_prev(str, pos)
  if pos <= 0 then return 0 end
  -- pos is the last byte of the character before the cursor
  local b = string.byte(str, pos)
  if b < 0x80 or b >= 0xC0 then
    return pos  -- single-byte char or lead byte right before cursor
  end
  -- Walk backward over continuation bytes (10xxxxxx = 0x80..0xBF)
  pos = pos - 1
  while pos > 1 do
    b = string.byte(str, pos)
    if b < 0x80 or b >= 0xC0 then break end
    pos = pos - 1
  end
  return pos
end

--- Returns the byte offset of the last byte of the next UTF-8 character.
-- From pos (cursor before the character), skips the lead byte and any
-- continuation bytes, returning the position of the last byte.
-- @param str The UTF-8 string.
-- @param pos The current byte position (cursor, before the character).
-- @return The byte position of the last byte of the character.
local function utf8_next(str, pos)
  local len = #str
  if pos >= len then return len end
  pos = pos + 1  -- move to lead byte
  -- Skip continuation bytes (10xxxxxx = 0x80..0xBF)
  while pos < len do
    local b = string.byte(str, pos + 1)
    if b < 0x80 or b >= 0xC0 then break end
    pos = pos + 1
  end
  return pos
end

function shifton()
  return keyheld("lshift") or keyheld("rshift")
end
--- A textbox that the user can enter text into, select text, etc.
-- @param tags A string of whitespaced separated tags
-- @param args A table of key-value object attributes
function textfield:init(tags, args)
  textfield.__super.init(self, tags, args)
  
  -- Add textfield tag.
  self:add("ui.textfield")
  
  local text = self.attributes.value
  
  self.selectionstart = 0
  self.selectionlength = 0
  self.anchor = 0
  self.cursor = true
  self.cushion = 4
  self.offset = 0
  self.mouseheldloc = nil
  
  self:onmousedown(function(self, x, y, button)
    local value = tostring(self.attributes.value)
    if button=="r" then
      self.selectionstart=0
      self.selectionlength=#value
      self.anchor=0
      return true;
    end
    if button=="l" then
        self.selectionstart=self:textlocation(x)
          --put cursor to position of mouse click
        self.selectionlength=0
        self.anchor=self.selectionstart
        self.mouseheldloc = x
    end
  end)
  self:onclick(function(self, x, y, button)
    self.mouseheldloc = nil
  end)
  self:onkeydown(function(self, key, unicode)
    if #key == 1 and type(unicode) == "number" and unicode > 0 then
      self:inserttext(utf8_encode(unicode))
    elseif key == "left" then
      if shifton() then
        -- Move cursor (active end) left, anchor stays fixed
        local cursor = self.selectionstart + self.selectionlength
        cursor = cursor - 1
        if cursor < 0 then cursor = 0 end
        self.selectionstart = math.min(self.anchor, cursor)
        self.selectionlength = cursor - self.selectionstart
      elseif self.selectionlength == 0 then
          self.selectionstart = self.selectionstart - 1
          self.anchor = self.selectionstart
      else
        -- Collapse cursor to left edge, anchor follows
        if self.selectionlength > 0 then
          -- cursor was at right end, collapse to left edge
        else
          self.selectionstart = self.selectionstart + self.selectionlength
        end
        self.selectionlength = 0
        self.anchor = self.selectionstart
      end
    elseif key == "right" then
      if shifton() then
        -- Move cursor (active end) right, anchor stays fixed
        local cursor = self.selectionstart + self.selectionlength
        cursor = cursor + 1
        self.selectionstart = math.min(self.anchor, cursor)
        self.selectionlength = cursor - self.selectionstart
      elseif self.selectionlength == 0 then
        self.selectionstart = self.selectionstart + 1
        self.anchor = self.selectionstart
      else
        -- Collapse cursor to right edge, anchor follows
        if self.selectionlength > 0 then
          self.selectionstart = self.selectionstart + self.selectionlength
        end
        self.selectionlength = 0
        self.anchor = self.selectionstart
      end
    elseif key =="backspace" then
      self:backward_delete()

    elseif key == "delete" then
      self:forward_delete()
    end
    self:normalize()
  end)
end

function textfield:backward_delete()
  local value = self.attributes.value
  if self.selectionlength~=0 then
    self:inserttext("");
    return
  end
  if self.selectionstart>0 then
    local oldvalue = self.attributes.value
    -- Find byte position of the character start before the cursor
    local charstart = utf8_prev(value, self.selectionstart)
    self.attributes.value=string.sub(value, 1, charstart-1)..
                          string.sub(value, self.selectionstart+1)
    self.selectionstart=charstart-1
    self.anchor=self.selectionstart
    self.actions.change(self, oldvalue, self.attributes.value)
  end
end

function textfield:forward_delete()
  local value = self.attributes.value
  if self.selectionlength~=0 then
    self:inserttext("");
    return
  end
  -- Do nothing if cursor is already at the end of text
  if self.selectionstart >= #value then
    return
  end
  local oldvalue = self.attributes.value
  local nxt = utf8_next(value, self.selectionstart)
  self.attributes.value=string.sub(value, 1, self.selectionstart)..
                          string.sub(value, nxt+1)
  self.anchor=self.selectionstart
  self.actions.change(self, oldvalue, self.attributes.value)
end

function textfield:inserttext(str)
  if self.selectionlength < 0 then
    self.selectionstart = self.selectionstart + self.selectionlength
    self.selectionlength = -self.selectionlength
  end
  local value = self.attributes.value
  local oldvalue = value
  value = string.sub(value, 1, self.selectionstart)..str..
          string.sub(value, self.selectionstart+
                            self.selectionlength+1)
  self.attributes.value = value
  self.selectionstart=self.selectionstart+#str
  self.selectionlength=0;
  self.anchor=self.selectionstart
  if oldvalue ~= value then
    self.actions.change(self, oldvalue, self.attributes.value)
  end
end

function textfield:normalize()
  for i=1, 2 do
  local value = tostring(self.attributes.value)
  local bounds = self.bounds
  
	if self.selectionstart<0 then
		self.selectionstart=0
	end
	if self.selectionstart>#value then
		self.selectionstart=#value
	end
	if self.anchor<0 then
		self.anchor=0
	end
	if self.anchor>#value then
		self.anchor=#value
	end
	local font = self.style.styles.font
	local toselectend = font:getWidth(string.sub(value, 1, self.selectionstart+
                                               self.selectionlength))
  local toselectstart = font:getWidth(string.sub(value, 1, self.selectionstart))
  local lastcharloc = self.cushion-self.offset+font:getWidth(value)
  local cursorloc = toselectend - self.offset+self.cushion
  if cursorloc > bounds[3] - self.cushion then
    --if cursor/edge of select rectangle too far right
    --try keep text screen full
	  self.offset = toselectend - bounds[3] + self.cushion*1.5
	elseif cursorloc < self.cushion then 
	  -- if cursor/edge of select rectangle too far left
	  self.offset = toselectend
	elseif font:getWidth(value) < bounds[3] - self.cushion then
	  self.offset = 0
	elseif lastcharloc < bounds[3]-self.cushion and self.offset>self.cushion then
	  self.offset = font:getWidth(value) - bounds[3]
	end
	end
end

function textfield:textlocation(x) 
	local font = self.style.styles.font
  local value = tostring(self.attributes.value)
  --get the nth char, at location of x, relative to left edge
	local loc = x+self.offset-self.cushion
	if loc <= 0 then
		return 0;
	end
	if loc >= font:getWidth(value) then
		return #value;
	end
	for i = 1, #value, 1 do 
		if (font:getWidth(string.sub(value,0,i))>loc) then
		  return i-1
		end 
	end
	return 0
end

function textfield:update(dt)
  textfield.__super.update(self, dt)
  if math.floor(time()*2) % 2 == 0 then
    self.cursor = false
  else
    self.cursor = true
  end
  if mouseheld("l") and self.mouseheldloc ~= nil and self:match("ui.focus") then
    --dragging the selection
		if mousex() ~= self.mouseheldloc then
      local cursor = self:textlocation(mousex())
      -- Use anchor (set on mousedown) as the fixed endpoint
      if cursor >= self.anchor then
        self.selectionstart = self.anchor
        self.selectionlength = cursor - self.anchor
      else
        self.selectionstart = cursor
        self.selectionlength = self.anchor - cursor
      end
		end
		self:normalize()
	end
end

-- Default size
function textfield:size()
  local value = tostring(self.attributes.value)
  return 100, textheight() + 4
end

function textfield:drawcontent()
  local height = self.style.styles.height
  -- Text
  color(self.style.styles.color)
  text(self.attributes.value, self.cushion - self.offset, height / 2 - 7)
  color(_000)
  local font = self.style.styles.font
  local value = tostring(self.attributes.value)
  local loc = font:getWidth(string.sub(value, 1, self.selectionstart)) - self.offset
  local topmargin = 3
  local lineheight = height - topmargin*2
  if self:match("ui.focus") and self.cursor and self.selectionlength == 0 then
    -- Cursor
    rectangle("fill", self.cushion-1+loc,topmargin,1,height-topmargin*2)
  elseif self:match("ui.focus") then
    color(self.style.styles.selectioncolor)
    -- Selection Rectangle
    if self.selectionlength > 0 then
        rectangle("fill", self.cushion+loc, topmargin, font:getWidth(
                  string.sub(value, self.selectionstart+1,
                                    self.selectionstart+
                                    self.selectionlength)), lineheight)
    else
      local width=font:getWidth(
            string.sub(value,self.selectionstart+
                              self.selectionlength+1, 
                             self.selectionstart))
				rectangle("fill", self.cushion+loc-width, topmargin, width, lineheight)
    end
  end
end

		

test("ui.textfield", function()
    local tx = textfield("mytag", { value = "Okay" })
    
    assert(tx.attributes.value == "Okay", 
      [[tx.attributes.value == "Okay"]])
    
    assert(tx:owns("mytag"), [[tx:owns("mytag")]])
    
    assert(tx:owns("ui.textfield"), [[tx:owns("ui.textfield")]])
    return true
  end)

-- Regression: UTF-8 encoding handles multi-byte characters
test("ui.textfield.utf8", function()
    local tx = textfield("test", { value = "" })
    -- U+00E0 (à) = 2-byte UTF-8: \195\160
    tx:inserttext(utf8_encode(0x00E0))
    assert(tx.attributes.value == "\195\160",
      "utf8 2-byte: expected à, got " .. tx.attributes.value)
    -- U+4E2D (中) = 3-byte UTF-8: \228\184\173
    tx:inserttext(utf8_encode(0x4E2D))
    assert(tx.attributes.value == "\195\160\228\184\173",
      "utf8 3-byte: expected à中")
    -- U+1F600 (😀) = 4-byte UTF-8: \240\159\152\128
    tx:inserttext(utf8_encode(0x1F600))
    assert(#tx.attributes.value == 4 + 3 + 4,
      "utf8 4-byte: expected 11 bytes total, got " .. #tx.attributes.value)
    return true
  end)

-- Regression: forward_delete at end of text must NOT fire change
test("ui.textfield.forward_delete_at_end", function()
    local tx = textfield("test", { value = "abc" })
    tx.selectionstart = 3
    tx.selectionlength = 0
    local changeCount = 0
    tx.actions.change:add(function() changeCount = changeCount + 1 end)
    tx:forward_delete()
    assert(changeCount == 0,
      "forward_delete at end should not fire change, fired " .. changeCount)
    assert(tx.attributes.value == "abc",
      "forward_delete at end should not modify text")
    return true
  end)

-- Regression: forward_delete in middle of text SHOULD fire change
test("ui.textfield.forward_delete_middle", function()
    local tx = textfield("test", { value = "abc" })
    tx.selectionstart = 1
    tx.selectionlength = 0
    local changeCount = 0
    tx.actions.change:add(function() changeCount = changeCount + 1 end)
    tx:forward_delete()
    assert(changeCount == 1,
      "forward_delete in middle should fire change once")
    assert(tx.attributes.value == "ac",
      "forward_delete at pos 1 should yield 'ac', got '" .. tx.attributes.value .. "'")
    return true
  end)

-- Regression: reverse (right-to-left) selection delete removes correct range
test("ui.textfield.reverse_selection_delete", function()
    local tx = textfield("test", { value = "abcde" })
    -- Simulate selecting from position 4 leftward to position 1
    -- (user clicked at 4, dragged to 1)
    tx.selectionstart = 4
    tx.selectionlength = -3  -- selects indices 1, 2, 3
    tx:backward_delete()
    assert(tx.attributes.value == "ae",
      "reverse selection delete: expected 'ae', got '" .. tx.attributes.value .. "'")
    assert(tx.selectionstart == 1,
      "cursor should be at 1, got " .. tx.selectionstart)
    assert(tx.selectionlength == 0,
      "selection should be cleared")
    return true
  end)

-- Regression: forward selection delete removes correct range
test("ui.textfield.forward_selection_delete", function()
    local tx = textfield("test", { value = "abcde" })
    -- Selecting from position 1 rightward to position 4
    tx.selectionstart = 1
    tx.selectionlength = 3  -- selects indices 1, 2, 3
    tx:backward_delete()
    assert(tx.attributes.value == "ae",
      "forward selection delete: expected 'ae', got '" .. tx.attributes.value .. "'")
    assert(tx.selectionstart == 1,
      "cursor should be at 1, got " .. tx.selectionstart)
    return true
  end)

-- Regression: insert with selection replaces selected text
test("ui.textfield.replace_selection", function()
    local tx = textfield("test", { value = "hello world" })
    tx.selectionstart = 5
    tx.selectionlength = 1  -- select the space
    tx:inserttext("_")
    assert(tx.attributes.value == "hello_world",
      "replace selection: expected 'hello_world', got '" .. tx.attributes.value .. "'")
    assert(tx.selectionstart == 6,
      "cursor should be at 6 after inserting 1 char")
    assert(tx.selectionlength == 0,
      "selection should be cleared after insert")
    return true
  end)

-- Regression: no-op insert (empty string, no selection) does NOT fire change
test("ui.textfield.noop_no_change", function()
    local tx = textfield("test", { value = "abc" })
    tx.selectionstart = 2
    tx.selectionlength = 0
    local changeCount = 0
    tx.actions.change:add(function() changeCount = changeCount + 1 end)
    tx:inserttext("")
    assert(changeCount == 0,
      "inserting empty with no selection should not fire change")
    return true
  end)

-- Regression: backspace with multi-byte UTF-8 character
test("ui.textfield.backspace_utf8", function()
    local zhong = "\228\184\173"  -- U+4E2D (中), 3 bytes
    local tx = textfield("test", { value = "a" .. zhong .. "b" })
    -- "a中b" = 5 bytes: a(1) 中(2,3,4) b(5)
    -- Cursor after 中 = byte position 4
    tx.selectionstart = 4
    tx.selectionlength = 0
    tx:backward_delete()
    assert(tx.attributes.value == "ab",
      "backspace UTF-8: expected 'ab', got '" .. tx.attributes.value .. "'")
    assert(tx.selectionstart == 1,
      "cursor should be at 1, got " .. tx.selectionstart)
    return true
  end)

-- Regression: forward delete with multi-byte UTF-8 character
test("ui.textfield.forward_delete_utf8", function()
    local zhong = "\228\184\173"  -- U+4E2D (中), 3 bytes
    local tx = textfield("test", { value = "a" .. zhong .. "b" })
    -- Cursor before 中 = byte position 1
    tx.selectionstart = 1
    tx.selectionlength = 0
    tx:forward_delete()
    assert(tx.attributes.value == "ab",
      "forward delete UTF-8: expected 'ab', got '" .. tx.attributes.value .. "'")
    assert(tx.selectionstart == 1,
      "cursor should remain at 1, got " .. tx.selectionstart)
    return true
  end)

-- Regression: anchor is initialized and updated correctly
test("ui.textfield.anchor_tracking", function()
    local tx = textfield("test", { value = "abcde" })
    assert(tx.anchor == 0, "initial anchor should be 0")
    tx.selectionstart = 3
    tx.anchor = 3
    tx.selectionlength = 2
    -- Delete selection: should reset anchor
    tx:backward_delete()
    assert(tx.selectionlength == 0, "selection cleared after delete")
    assert(tx.anchor == tx.selectionstart,
      "anchor should track cursor after delete, anchor=" ..
      tx.anchor .. " start=" .. tx.selectionstart)
    return true
  end)

progress = class(widget)

--- A progress bar that displays the progress of an operation.
-- @param tags A string of whitespaced separated tags
-- @param args A table of key-value object attributes
function progress:init(tags, args)
  progress.__super.init(self, tags, args)
  
  -- Add progress tag
  self:add("ui.progress")
  
  local value = self.attributes.value
end

return ui