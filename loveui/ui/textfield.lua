--- loveui is a love2d library to provide resuable GUI widgets to love2d 
-- developers.
module ("ui", package.seeall)

require "loveui/util/test"
require "loveui/util/class"
require "loveui/ui/widget"
require "loveui/ui/context"

textfield = class(widget)

function shifton()
  return keyheld("lshift") or keyheld("rshift")
end

-- UTF-8 helpers. The textfield stores its value as a byte string and tracks
-- the cursor/selection as byte offsets, so all movement and deletion has to
-- respect UTF-8 codepoint boundaries (otherwise a multibyte character gets
-- split and produces garbled text or a crash in font:getWidth).

-- Encode a Unicode code point into its UTF-8 byte string.
-- Returns "" for nil / non-numeric / out-of-range inputs so callers never crash
-- (this replaces string.char(unicode), which only handles code points 0-255).
local function utf8char(cp)
  if type(cp) ~= "number" or cp < 0 or cp > 0x10FFFF then
    return ""
  end
  cp = math.floor(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40),
                       0x80 + (cp % 0x40))
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000),
                       0x80 + (math.floor(cp / 0x40) % 0x40),
                       0x80 + (cp % 0x40))
  else
    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + (math.floor(cp / 0x1000) % 0x40),
                       0x80 + (math.floor(cp / 0x40) % 0x40),
                       0x80 + (cp % 0x40))
  end
end

-- Is byte b a UTF-8 continuation byte (10xxxxxx)?
local function iscont(b)
  return b ~= nil and b >= 0x80 and b < 0xC0
end

-- Byte length of the codepoint immediately to the LEFT of byte offset pos
-- (pos = number of bytes before the cursor). 0 if already at the start.
local function prevcharlen(s, pos)
  if pos < 0 then pos = 0 end
  if pos > #s then pos = #s end
  if pos <= 0 then return 0 end
  local i = pos
  while i > 1 and iscont(s:byte(i)) do
    i = i - 1
  end
  return pos - i + 1
end

-- Byte length of the codepoint immediately to the RIGHT of byte offset pos.
-- 0 if already at the end.
local function nextcharlen(s, pos)
  if pos < 0 then pos = 0 end
  if pos > #s then pos = #s end
  if pos >= #s then return 0 end
  local i = pos + 2
  while i <= #s and iscont(s:byte(i)) do
    i = i + 1
  end
  return i - (pos + 1)
end

-- Byte offsets (0-based) of every codepoint boundary in s, including 0 and #s.
local function charboundaries(s)
  local b = {0}
  local pos = 0
  while pos < #s do
    pos = pos + nextcharlen(s, pos)
    b[#b + 1] = pos
  end
  return b
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
  self.cursor = true
  self.cushion = 4
  self.offset = 0
  self.mouseheldloc = nil
  
  self:onmousedown(function(self, x, y, button)
    local value = tostring(self.attributes.value)
    if button=="r" then
      self.selectionstart=0
      self.selectionlength=#value
      return true;
    end
    if button=="l" then
        self.selectionstart=self:textlocation(x) 
          --put cursor to position of mouse click
        self.selectionlength=0
        self.mouseheldloc = x
    end
  end)
  self:onclick(function(self, x, y, button)
    self.mouseheldloc = nil
  end)
  self:onkeydown(function(self, key, unicode)
    local value = self.attributes.value
    if key == "left" then
      if shifton() then
        self.selectionlength = self.selectionlength -
                  prevcharlen(value, self.selectionstart + self.selectionlength)
      elseif self.selectionlength ~= 0 then
        -- collapse the selection to its left edge
        local from = self:selectionrange()
        self.selectionstart = from
        self.selectionlength = 0
      else
        self.selectionstart = self.selectionstart -
                              prevcharlen(value, self.selectionstart)
      end
    elseif key == "right" then
      if shifton() then
        self.selectionlength = self.selectionlength +
                  nextcharlen(value, self.selectionstart + self.selectionlength)
      elseif self.selectionlength ~= 0 then
        -- collapse the selection to its right edge
        local from, len = self:selectionrange()
        self.selectionstart = from + len
        self.selectionlength = 0
      else
        self.selectionstart = self.selectionstart +
                              nextcharlen(value, self.selectionstart)
      end
    elseif key == "backspace" then
      self:backward_delete()
    elseif key == "delete" then
      self:forward_delete()
    elseif unicode and unicode >= 32 then
      -- any printable code point becomes text input, UTF-8 encoded
      self:inserttext(utf8char(unicode))
    end
    self:normalize()
  end)
end

-- Collapse a (possibly backward) selection into a forward (from, length) byte
-- range. Every edit operation goes through this so forward and backward
-- selections (e.g. dragged right-to-left) behave identically.
function textfield:selectionrange()
  local from = self.selectionstart
  local len = self.selectionlength
  if len < 0 then
    from = from + len
    len = -len
  end
  return from, len
end

function textfield:backward_delete()
  if self.selectionlength ~= 0 then
    -- a selection (either direction) is removed by replacing it with nothing
    self:inserttext("")
    return
  end
  local value = self.attributes.value
  if self.selectionstart > 0 then
    local n = prevcharlen(value, self.selectionstart)
    local oldvalue = value
    local newvalue = string.sub(value, 1, self.selectionstart - n)..
                     string.sub(value, self.selectionstart + 1)
    self.selectionstart = self.selectionstart - n
    if newvalue ~= oldvalue then
      self.attributes.value = newvalue
      self.actions.change(self, oldvalue, newvalue)
    end
  end
end

function textfield:forward_delete()
  if self.selectionlength ~= 0 then
    self:inserttext("")
    return
  end
  local value = self.attributes.value
  if self.selectionstart >= #value then
    -- cursor is already at the end: nothing to delete, do not fire change
    return
  end
  local n = nextcharlen(value, self.selectionstart)
  local oldvalue = value
  local newvalue = string.sub(value, 1, self.selectionstart)..
                   string.sub(value, self.selectionstart + n + 1)
  if newvalue ~= oldvalue then
    self.attributes.value = newvalue
    self.actions.change(self, oldvalue, newvalue)
  end
end

function textfield:inserttext(str)
  local from, len = self:selectionrange()
  local oldvalue = self.attributes.value
  local newvalue = string.sub(oldvalue, 1, from)..str..
                   string.sub(oldvalue, from + len + 1)
  -- cursor always collapses to just after the inserted text
  self.selectionstart = from + #str
  self.selectionlength = 0
  -- only report a change when the text actually changed
  if newvalue ~= oldvalue then
    self.attributes.value = newvalue
    self.actions.change(self, oldvalue, newvalue)
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
	-- keep the selection end inside the text too, so selectionstart/length
	-- stay consistent after edits and extend-select near the ends
	local selend = self.selectionstart + self.selectionlength
	if selend < 0 then selend = 0 end
	if selend > #value then selend = #value end
	self.selectionlength = selend - self.selectionstart
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
  -- find the codepoint boundary nearest to x, relative to the left edge
  local loc = x + self.offset - self.cushion
  if loc <= 0 then
    return 0
  end
  if loc >= font:getWidth(value) then
    return #value
  end
  local bounds = charboundaries(value)
  for i = 2, #bounds do
    if font:getWidth(string.sub(value, 1, bounds[i])) > loc then
      return bounds[i - 1]
    end
  end
  return #value
end

function textfield:update(dt)
  textfield.__super.update(self, dt)
  if math.floor(time()*2) % 2 == 0 then
    self.cursor = false
  else
    self.cursor = true
  end
  if mouseheld("l") and self.mouseheldloc ~= nil and self:match("ui.focus") then 
    --dragging the rectangle
		if mousex() ~= self.mouseheldloc then
      self.selectionlength = self:textlocation(mousex()) - self.selectionstart
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

-- Counts change events fired by a textfield and records the last old/new pair.
local function changewatch(tx)
  local w = { count = 0 }
  tx:onchange(function(self, old, new)
    w.count = w.count + 1
    w.old = old
    w.new = new
  end)
  return w
end

-- UTF-8 encoding replaces string.char(unicode), which crashed/garbled non-ASCII.
test("ui.textfield.utf8char", function()
    assert(utf8char(65) == "A", "ascii")
    assert(utf8char(0xE9) == "\195\169", "U+00E9 e-acute is 2 bytes")
    assert(utf8char(0x4E2D) == "\228\184\173", "U+4E2D is 3 bytes")
    assert(utf8char(0x1F600) == "\240\159\152\128", "U+1F600 emoji is 4 bytes")
    -- out-of-range / nil never crash, just produce nothing
    assert(utf8char(nil) == "", "nil -> empty")
    assert(utf8char(-1) == "", "negative -> empty")
    assert(utf8char(0x110000) == "", "above max -> empty")
    return true
  end)

-- Codepoint boundary helpers must step over whole multibyte characters.
test("ui.textfield.codepoint_helpers", function()
    local s = "a"..utf8char(0x4E2D).."b" -- 'a' + 3-byte char + 'b' = 5 bytes
    assert(#s == 5, "byte length")
    assert(nextcharlen(s, 0) == 1, "next over 'a'")
    assert(nextcharlen(s, 1) == 3, "next over multibyte")
    assert(nextcharlen(s, 4) == 1, "next over 'b'")
    assert(nextcharlen(s, 5) == 0, "next at end is 0")
    assert(prevcharlen(s, 5) == 1, "prev over 'b'")
    assert(prevcharlen(s, 4) == 3, "prev over multibyte")
    assert(prevcharlen(s, 1) == 1, "prev over 'a'")
    assert(prevcharlen(s, 0) == 0, "prev at start is 0")
    return true
  end)

-- Multibyte input is inserted whole, and backspace deletes it whole.
test("ui.textfield.multibyte_input", function()
    local tx = textfield("t", { value = "ab" })
    local w = changewatch(tx)
    tx.selectionstart = 2 -- cursor at end (after "ab")
    tx.selectionlength = 0
    tx:inserttext(utf8char(0x4E2D))
    assert(tx.attributes.value == "ab"..utf8char(0x4E2D), "char inserted")
    assert(tx.selectionstart == 5, "cursor after 3-byte char")
    assert(tx.selectionlength == 0, "selection collapsed")
    assert(w.count == 1, "one change event")
    tx:backward_delete()
    assert(tx.attributes.value == "ab", "whole multibyte char removed")
    assert(tx.selectionstart == 2, "cursor back to 2")
    assert(w.count == 2, "change fired on delete")
    return true
  end)

-- Delete at end of text must NOT fabricate a change event.
test("ui.textfield.forward_delete_at_end", function()
    local tx = textfield("t", { value = "abc" })
    local w = changewatch(tx)
    tx.selectionstart = 3 -- == #value, cursor at very end
    tx.selectionlength = 0
    tx:forward_delete()
    assert(tx.attributes.value == "abc", "text unchanged at end")
    assert(w.count == 0, "no change event when nothing deleted")
    -- but a Delete in the middle still works and removes a whole codepoint
    tx.selectionstart = 0
    tx.attributes.value = utf8char(0x4E2D).."c"
    tx:forward_delete()
    assert(tx.attributes.value == "c", "forward delete removed multibyte char")
    assert(w.count == 1, "change event fired for real deletion")
    return true
  end)

-- A reverse (right-to-left) selection deletes exactly the selected range.
test("ui.textfield.reverse_selection_delete", function()
    local tx = textfield("t", { value = "hello" })
    local w = changewatch(tx)
    -- anchor at 4, dragged left to 1 -> selects "ell" with negative length
    tx.selectionstart = 4
    tx.selectionlength = -3
    local from, len = tx:selectionrange()
    assert(from == 1 and len == 3, "selectionrange normalizes backward range")
    tx:backward_delete()
    assert(tx.attributes.value == "ho", "reverse selection removed range")
    assert(tx.selectionstart == 1, "cursor at left edge of removed range")
    assert(tx.selectionlength == 0, "selection collapsed")
    assert(w.count == 1, "one change event")
    return true
  end)

-- Drag-selecting then typing replaces the selection, same for both directions.
test("ui.textfield.drag_then_replace", function()
    -- forward selection of "ext"
    local fwd = textfield("t", { value = "text" })
    local wf = changewatch(fwd)
    fwd.selectionstart = 1
    fwd.selectionlength = 3
    fwd:inserttext("X")
    assert(fwd.attributes.value == "tX", "forward selection replaced")
    assert(fwd.selectionstart == 2 and fwd.selectionlength == 0, "cursor after insert")
    assert(wf.count == 1, "one change event")
    -- the same selection made right-to-left must behave identically
    local rev = textfield("t", { value = "text" })
    rev.selectionstart = 4
    rev.selectionlength = -3
    rev:inserttext("X")
    assert(rev.attributes.value == "tX", "reverse selection replaced identically")
    assert(rev.selectionstart == 2, "cursor after insert (reverse)")
    return true
  end)

-- Inserting nothing with no selection changes neither text nor fires a change.
test("ui.textfield.no_spurious_change", function()
    local tx = textfield("t", { value = "abc" })
    local w = changewatch(tx)
    tx.selectionstart = 1
    tx.selectionlength = 0
    tx:inserttext("")
    assert(tx.attributes.value == "abc", "text unchanged")
    assert(w.count == 0, "no change event")
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