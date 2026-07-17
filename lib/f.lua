-- math

function sign(number)
    if number > 0 then
        return 1
    elseif number < 0 then
        return -1
    else
        return 0
    end
end

function approach(current, target, speed, minValue)
    minValue = minValue or 1

    local distance = target - current
    local absDistance = math.abs(distance)

    -- Prevent tiny floating point oscillations
    if absDistance <= minValue then
        return target
    end

    local magnitude = math.max(math.log10(absDistance) - 1, 4)
    local step = sign(distance) * math.min(math.pow(10, math.floor(magnitude)) * speed, absDistance)

    if current < target then
        return math.min(current + step, target)
    elseif current > target then
        return math.max(current + step, target)
    else
        return target
    end
end

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
   return nil
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

function centerPad(str, length)
    str = tostring(str)

    local padding = length - string.len(str)
    if padding <= 0 then
        return str
    end

    local left = math.floor(padding / 2)
    local right = math.ceil(padding / 2)

    return string.rep(" ", left) .. str .. string.rep(" ", right)
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

function draw_text_llr(mon, x, y, offset, textl1, textl2, textr1, textl1_color, textl2_color, textr1_color, bg_color)
	draw_text(mon, x, y, textl1, textl1_color, bg_color)
	draw_text(mon, x + 1 + string.len(tostring(textl1)), y, textl2, textl2_color, bg_color)
	draw_text_right(mon, offset, y, textr1, textr1_color, bg_color)
end

function draw_text_lmr(mon, x, y, offset, textl1, textm1, textr1, textl1_color, textm1_color, textr1_color, bg_color)
	draw_text(mon, x, y, textl1, textl1_color, bg_color)
	local width = mon.X
	draw_text(mon, math.ceil((width - string.len(tostring(textm1)))/2) + 1, y, textm1, textm1_color, bg_color)
	draw_text_right(mon, offset, y, textr1, textr1_color, bg_color)
end

--draw line on computer terminal
function draw_line(mon, x, y, length, color, symbol, symbol_color)
    symbol = symbol or " "
    symbol_color = symbol_color or color
    if length < 0 then
      length = 0
    end
    mon.monitor.setBackgroundColor(color)
    mon.monitor.setTextColor(symbol_color)
    mon.monitor.setCursorPos(x,y)
    mon.monitor.write(string.rep(symbol, length))
end

--create progress bar
--draws two overlapping lines
--background line of bg_color
--main line of bar_color as a percentage of minVal/maxVal
function progress_bar(mon, x, y, length, minVal, maxVal, bar_color, bg_color)
  draw_line(mon, x, y, length, bg_color) --backgoround bar
  local barSize = math.floor((minVal/maxVal) * length)
  barSize  = math.max(0, math.min(length, barSize))
  draw_line(mon, x, y, barSize, bar_color) --progress so far
end

-- layered dual progress bar
--
-- background -> longer value -> shorter value
--
-- current and target are drawn as overlapping bars
-- the longer value determines the base color
-- the shorter value overlays it
-- equal values use target color
--
function progress_bar_dual(mon, x, y, length, current, target, current_color, target_color, bg_color, maxVal)

  -- automatic scale
  if maxVal == nil then
    maxVal = math.max(current, target)
  end

  if maxVal <= 0 then
    draw_line(mon, x, y, length, bg_color)
    return
  end


  -- calculate sizes
  local currentSize = math.floor((current / maxVal) * length)
  local targetSize  = math.floor((target / maxVal) * length)


  -- clamp
  currentSize = math.max(0, math.min(length, currentSize))
  targetSize  = math.max(0, math.min(length, targetSize))


  -- layer 1: background
  draw_line(mon, x, y, length, bg_color)


  -- layer 2: longer bar
  if currentSize > targetSize then
    draw_line(mon, x, y, currentSize, current_color)
  else
    draw_line(mon, x, y, targetSize, target_color)
  end


  -- layer 3: shorter bar
  if current == target then
    -- target wins when equal
    draw_line(mon, x, y, targetSize, target_color)

  elseif currentSize < targetSize then
    -- current is shorter
    draw_line(mon, x, y, currentSize, current_color)

  else
    -- target is shorter
    draw_line(mon, x, y, targetSize, target_color)
  end

end

---Draws an overlapping progress bar.
---@param mon table Monitor or terminal object.
---@param x integer Left position.
---@param y integer Top position.
---@param width integer Width of the bar in characters.
---@param values table Array of { value = number, color = color }.
function draw_layered_progress_bar(mon, x, y, width, values, bg_color)
    bg_color = bg_color or colors.gray

    -- Find maximum
    local max = 0
    for _, v in ipairs(values) do
        if v.value > max then
            max = v.value
        end
    end

    if max == 0 then
        --mon.setBackgroundColor(colors.black)
        --mon.setCursorPos(x, y)
        --mon.write(string.rep(" ", width))
        draw_line(mon, x, y, width, bg_color)
        return
    end

    -- Copy so we don't modify the caller's table
    local bars = {}
    for i, v in ipairs(values) do
        bars[i] = {
            value = v.value,
            color = v.color,
            symbol = v.symbol,
            symbol_color = v.symbol_color,
        }
    end

    -- Largest first
    table.sort(bars, function(a, b)
        return a.value > b.value
    end)

    -- Draw from largest to smallest
    for _, bar in ipairs(bars) do
        local w = math.floor(bar.value / max * width + 0.5)

        --mon.setBackgroundColor(bar.color)
        --mon.setCursorPos(x, y)
        --mon.write(string.rep(" ", w))
        draw_line(mon, x, y, w, bar.color, bar.symbol, bar.symbol_color)
    end
end


function clear(mon)
  term.clear()
  term.setCursorPos(1,1)
  mon.monitor.setBackgroundColor(colors.black)
  mon.monitor.clear()
  mon.monitor.setCursorPos(1,1)
end

