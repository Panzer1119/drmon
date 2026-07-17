
-- peripheral identification
--
function periphSearch(type)
   local names = peripheral.getNames()
   local i, name
   for i, name in pairs(names) do
      if peripheral.getType(name) == type then
         return peripheral.wrap(name)
      end
   end
   return null
end

-- formatting

function format_int(number, decimals)

  if number == nil then number = 0 end
  decimals = decimals or 0

  -- Round and format to the requested number of decimal places
  local str = string.format("%." .. decimals .. "f", number)

  local minus, int, fraction = str:match("([-]?)(%d+)(%.?%d*)")

  -- Add commas every 3 digits
  int = int:reverse():gsub("(%d%d%d)", "%1,")
  int = int:reverse():gsub("^,", "")

  return minus .. int .. fraction
end

-- monitor related

--display text text on monitor, "mon" peripheral
function draw_text(mon, x, y, text, text_color, bg_color)
  mon.monitor.setBackgroundColor(bg_color)
  mon.monitor.setTextColor(text_color)
  mon.monitor.setCursorPos(x,y)
  mon.monitor.write(text)
end

function draw_text_right(mon, offset, y, text, text_color, bg_color)
  mon.monitor.setBackgroundColor(bg_color)
  mon.monitor.setTextColor(text_color)
  mon.monitor.setCursorPos(mon.X-string.len(tostring(text))-offset,y)
  mon.monitor.write(text)
end

function draw_text_lr(mon, x, y, offset, text1, text2, text1_color, text2_color, bg_color)
	draw_text(mon, x, y, text1, text1_color, bg_color)
	draw_text_right(mon, offset, y, text2, text2_color, bg_color)
end

--draw line on computer terminal
function draw_line(mon, x, y, length, color)
    if length < 0 then
      length = 0
    end
    mon.monitor.setBackgroundColor(color)
    mon.monitor.setCursorPos(x,y)
    mon.monitor.write(string.rep(" ", length))
end

--create progress bar
--draws two overlapping lines
--background line of bg_color
--main line of bar_color as a percentage of minVal/maxVal
function progress_bar(mon, x, y, length, minVal, maxVal, bar_color, bg_color)
  draw_line(mon, x, y, length, bg_color) --backgoround bar
  local barSize = math.floor((minVal/maxVal) * length)
  draw_line(mon, x, y, barSize, bar_color) --progress so far
end

--create dual marker progress bar
--shows current value and target value on the same bar
--
--current_color = current value position
--target_color  = target value position
--bg_color      = unused area
--
--If current == target, target_color is used
--
function progress_bar_dual(mon, x, y, length, current, target, current_color, target_color, bg_color, maxVal)

  -- avoid division problems
  if maxVal == nil then
    maxVal = math.max(current, target)
  end

  if maxVal <= 0 then
    draw_line(mon, x, y, length, bg_color)
    return
  end

  -- clear bar
  draw_line(mon, x, y, length, bg_color)


  -- calculate positions
  local currentPos = math.floor((current / maxVal) * length)
  local targetPos  = math.floor((target / maxVal) * length)


  -- clamp positions
  currentPos = math.max(0, math.min(length, currentPos))
  targetPos  = math.max(0, math.min(length, targetPos))


  -- draw target first
  if targetPos > 0 then
    draw_line(mon, x, y, targetPos, target_color)
  end


  -- draw current marker
  -- current overwrites target except when equal
  if current == target then
    draw_line(mon, x + targetPos - 1, y, 1, target_color)
  else
    draw_line(mon, x + currentPos - 1, y, 1, current_color)
  end


  -- redraw target marker if current overwrote it and they are different
  if current ~= target then
    draw_line(mon, x + targetPos - 1, y, 1, target_color)
    draw_line(mon, x + currentPos - 1, y, 1, current_color)
  end
end


function clear(mon)
  term.clear()
  term.setCursorPos(1,1)
  mon.monitor.setBackgroundColor(colors.black)
  mon.monitor.clear()
  mon.monitor.setCursorPos(1,1)
end

