-- modifiable variables
local reactorSide = "back"
local outputFluxgateSide = "right"

local targetStrength = 20
local maxTemperature = 8000
local safeTemperature = 3000
local lowestFieldPercent = 3

local activateOnCharged = 1

local inputRampRate = 1
local outputRampRate = 2

-- please leave things untouched from here on
os.loadAPI("lib/f")

local version = "0.3"
-- toggleable via the monitor, use our algorithm to achieve our target field strength or let the user tweak it
local autoInputGate = 1
local targetInputGate = 250000
local targetOutputGate = 0

-- monitor 
local mon, monitor, monX, monY

-- peripherals
local reactor
local inputFluxgate
local outputFluxgate

-- reactor information
local ri

-- last performed action
local action = "None since reboot"
local emergencyCharge = false
local emergencyTemp = false

monitor_peripheral = f.periphSearch("monitor")
monitor = window.create(monitor_peripheral, 1, 1, monitor_peripheral.getSize()) -- create a window on the monitor
inputFluxgate = f.periphSearch("flow_gate")
outputFluxgate = peripheral.wrap(outputFluxgateSide)
reactor = peripheral.wrap(reactorSide)

if monitor == null then
	error("No valid monitor was found")
end

if reactor == null then
	error("No valid reactor was found")
end

if inputFluxgate == null then
	error("No valid input flux gate was found")
end

if outputFluxgate == null then
	error("No valid output flux gate was found")
end

monX, monY = monitor.getSize()
mon = {}
mon.monitor,mon.X, mon.Y = monitor, monX, monY

--write settings to config file
function save_config()
  sw = fs.open("config.txt", "w")   
  sw.writeLine(version)
  sw.writeLine(autoInputGate)
  sw.writeLine(targetInputGate)
  sw.writeLine(targetOutputGate)
  sw.close()
end

--read settings from file
function load_config()
  sr = fs.open("config.txt", "r")
  version = sr.readLine()
  autoInputGate = tonumber(sr.readLine())
  targetInputGate = tonumber(sr.readLine())
  targetOutputGate = tonumber(sr.readLine())
  sr.close()
end


-- 1st time? save our settings, if not, load our settings
if fs.exists("config.txt") == false then
  save_config()
else
  load_config()
end

function buttons()

  while true do
    -- button handler
    event, side, xPos, yPos = os.pullEvent("monitor_touch")

    local right = mon.X
    local middle = math.floor(right/2)
    local r = right - 4 + 1 + 4

    local delta = 0
    if xPos >= 2 and xPos <= 6 then
      delta = -1000
    elseif xPos >= 8 and xPos <= 12 then
      delta = -10000
    elseif xPos >= 14 and xPos <= 18 then
      delta = -100000
    elseif xPos >= 20 and xPos <= 24 then
      delta = -1000000
    elseif xPos >= 26 and xPos <= 30 then
      delta = -10000000
    elseif xPos >= r-30 and xPos <= r-26 then
      delta = 10000000
    elseif xPos >= r-24 and xPos <= r-20 then
      delta = 1000000
    elseif xPos >= r-18 and xPos <= r-14 then
      delta = 100000
    elseif xPos >= r-12 and xPos <= r-8 then
      delta = 10000
    elseif xPos >= r-6 and xPos <= r-2 then
      delta = 1000
    end

    -- output gate controls
    -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
    -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000
    if yPos == 8 then
      targetOutputGate = targetOutputGate + delta
      save_config()
    end

    local isXToggleButton = xPos >= middle-1 and xPos <= middle+2

    -- input gate controls
    -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
    -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000
    if yPos == 10 and autoInputGate == 0 and not isXToggleButton then
      targetInputGate = targetInputGate + delta
      save_config()
    end

    -- input gate toggle
    if yPos == 10 and isXToggleButton then
      if autoInputGate == 1 then
        autoInputGate = 0
      else
        autoInputGate = 1
      end
      save_config()
    end

  end
end

function drawFluxGateButtons(y)
  -- Button layout:
  -- left side:  -1k -10k -100k -1M -10M
  -- right side: +10M +1M +100k +10k +1k

  local right = mon.X
  local r = right - 4 + 1

  -- left buttons
  f.draw_text(mon, 2, y,  " -1k ", colors.white, colors.gray)
  f.draw_text(mon, 8, y,  " -10k", colors.white, colors.gray)
  f.draw_text(mon, 14, y, "-100k", colors.white, colors.gray)
  f.draw_text(mon, 20, y, " -1M ", colors.white, colors.gray)
  f.draw_text(mon, 26, y, " -10M", colors.white, colors.gray)

  -- right buttons (anchored from right)
  f.draw_text(mon, r-26, y, " +10M", colors.white, colors.gray)
  f.draw_text(mon, r-20, y, " +1M ", colors.white, colors.gray)
  f.draw_text(mon, r-14, y, "+100k", colors.white, colors.gray)
  f.draw_text(mon, r-8, y,  " +10k", colors.white, colors.gray)
  f.draw_text(mon, r-2, y,  " +1k ", colors.white, colors.gray)
end

function updateFluxGates(currentInputGate, currentOutputGate)
    print("Current Input  Gate: ", currentInputGate)
    print("Current Output Gate: ", currentOutputGate)
    print("Target  Input  Gate: ", targetInputGate)
    print("Target  Output Gate: ", targetOutputGate)
    -------------------------------------------------
    -- INPUT
    -- Increasing input = instant
    -- Decreasing input = ramp
    -------------------------------------------------
    if targetInputGate >= currentInputGate then
        currentInputGate = targetInputGate
    else
        currentInputGate = f.approach(
            currentInputGate,
            targetInputGate,
            inputRampRate
        )
    end

    -------------------------------------------------
    -- OUTPUT
    -- Decreasing output = instant
    -- Increasing output = ramp
    -------------------------------------------------

    if targetOutputGate <= currentOutputGate then
        currentOutputGate = targetOutputGate
    else
        currentOutputGate = f.approach(
            currentOutputGate,
            targetOutputGate,
            outputRampRate
        )
    end

    print("New     Input  Gate: ", currentInputGate)
    print("New     Output Gate: ", currentOutputGate)
    inputFluxgate.setSignalLowFlow(currentInputGate)
    outputFluxgate.setSignalLowFlow(currentOutputGate)
end


function update()
  while true do 

    monitor.setVisible(false) -- disable updating the screen.
    f.clear(mon)

    ri = reactor.getReactorInfo()

    -- Read actual gate values
    currentInputGate = inputFluxgate.getSignalLowFlow()
    currentOutputGate = outputFluxgate.getSignalLowFlow()

    -- print out all the infos from .getReactorInfo() to term

    if ri == nil then
      error("reactor has an invalid setup")
    end

    for k, v in pairs (ri) do
      print(k.. ": "..tostring(v))			
    end

    -- monitor output

    local statusColor
    statusColor = colors.red

    if ri.status == "running" or ri.status == "warming_up" and ri.temperature > 2000 then
      statusColor = colors.green
    elseif ri.status == "cold" then
      statusColor = colors.gray
    elseif ri.status == "warming_up" then
      statusColor = colors.orange
    end

    f.draw_text_lr(mon, 2, 2, 1, "Draconic Reactor", string.upper(ri.status), colors.white, statusColor, colors.black)

    f.draw_text_lr(mon, 2, 4, 1, "Generation", f.format_int(ri.generationRate) .. " rf/t", colors.white, colors.lime, colors.black)
    local maxGenerationValue = math.max(ri.generationRate, currentOutputGate, targetOutputGate)
    if maxGenerationValue == targetOutputGate then
      f.progress_bar_dual(mon, 2, 5, mon.X-2, ri.generationRate, currentOutputGate, colors.lime, colors.cyan, colors.blue, targetOutputGate)
    elseif maxGenerationValue == ri.generationRate then
      f.progress_bar_dual(mon, 2, 5, mon.X-2, currentOutputGate, targetOutputGate, colors.cyan, colors.blue, colors.lime, ri.generationRate)
    elseif maxGenerationValue == currentOutputGate then
      f.progress_bar_dual(mon, 2, 5, mon.X-2, ri.generationRate, targetOutputGate, colors.lime, colors.blue, colors.cyan, currentOutputGate)
    end

    local tempColor = colors.red
    if ri.temperature <= 5000 then tempColor = colors.green end
    if ri.temperature >= 5000 and ri.temperature <= 6500 then tempColor = colors.orange end
    f.draw_text_lr(mon, 2, 6, 1, "Temperature", f.format_int(ri.temperature, 2) .. " C", colors.white, tempColor, colors.black)

    f.draw_text_lmr(mon, 2, 7, 1, "Output Gate", f.format_int(currentOutputGate) .. " rf/t", f.format_int(targetOutputGate) .. " rf/t", colors.white, colors.cyan, colors.blue, colors.black)

    -- buttons
    drawFluxGateButtons(8)

    f.draw_text_lmr(mon, 2, 9, 1, "Input Gate", f.format_int(currentInputGate) .. " rf/t", f.format_int(targetInputGate) .. " rf/t", colors.white, colors.cyan, colors.blue, colors.black)

    local width = mon.X
    local middle = math.floor(width/2)
    if autoInputGate == 1 then
      f.draw_text(mon, middle-1, 10, "AUTO", colors.white, colors.gray)
    else
      f.draw_text(mon, middle-1, 10, "MANU", colors.white, colors.gray)
      drawFluxGateButtons(10)
    end

    local satPercent
    satPercent = math.ceil(ri.energySaturation / ri.maxEnergySaturation * 10000)*.01

    f.draw_text_lr(mon, 2, 11, 1, "Energy Saturation", string.format("%.2f %%", satPercent), colors.white, colors.white, colors.black)
    f.progress_bar(mon, 2, 12, mon.X-2, satPercent, 100, colors.blue, colors.gray)

    local fieldPercent, fieldColor
    fieldPercent = math.ceil(ri.fieldStrength / ri.maxFieldStrength * 10000)*.01

    fieldColor = colors.red
    if fieldPercent >= 50 then fieldColor = colors.green end
    if fieldPercent < 50 and fieldPercent > 30 then fieldColor = colors.orange end
    targetFieldColor = colors.magenta
    if targetStrength >= 50 then targetFieldColor = colors.lime end
    if targetStrength < 50 and targetStrength > 30 then targetFieldColor = colors.yellow end

    local lowestFieldCount = math.floor(lowestFieldPercent * (width-2) / 100)
    --TODO Draw that many X at the start of the progress bar to mark the death range?
    if autoInputGate == 1 then 
      f.draw_text_llr(mon, 2, 14, 1, "Field Strength Lowest: " .. lowestFieldPercent, "Target: " .. targetStrength, string.format("%.2f %%", fieldPercent), colors.white, targetFieldColor, fieldColor, colors.black)
	  f.progress_bar_dual(mon, 2, 15, mon.X-2, fieldPercent, targetStrength, fieldColor, targetFieldColor, colors.gray, 100)
    else
      f.draw_text_lr(mon, 2, 14, 1, "Field Strength Lowest: " .. lowestFieldPercent, string.format("%.2f %%", fieldPercent), colors.white, fieldColor, colors.black)
	  f.progress_bar(mon, 2, 15, mon.X-2, fieldPercent, 100, fieldColor, colors.gray)
    end

    local fuelPercent, fuelColor

    fuelPercent = 100 - math.ceil(ri.fuelConversion / ri.maxFuelConversion * 10000)*.01

    fuelColor = colors.red

    if fuelPercent >= 70 then fuelColor = colors.green end
    if fuelPercent < 70 and fuelPercent > 30 then fuelColor = colors.orange end

    f.draw_text_lr(mon, 2, 17, 1, "Fuel ", string.format("%.2f %%", fuelPercent), colors.white, fuelColor, colors.black)
    f.progress_bar(mon, 2, 18, mon.X-2, fuelPercent, 100, fuelColor, colors.gray)

    f.draw_text_lr(mon, 2, 19, 1, "Action ", action, colors.gray, colors.gray, colors.black)

    -- actual reactor interaction
    --
    if emergencyCharge == true then
      reactor.chargeReactor()
    end
    
    -- are we charging? open the floodgates
    if ri.status == "warming_up" and ri.temperature <= 2000 then
	  targetInputGate = 900000
      emergencyCharge = false
    end

    -- are we stopping from a shutdown and our temp is better? activate
    if emergencyTemp == true and ri.status == "stopping" and ri.temperature < safeTemperature then
      reactor.activateReactor()
      emergencyTemp = false
    end

    -- are we charged? lets activate
    if ri.status == "warming_up" and ri.temperature > 2000 and activateOnCharged == 1 then
      reactor.activateReactor()
    end

    -- are we on? regulate the input fludgate to our target field strength
    -- or set it to our saved setting since we are on manual
    if ri.status == "running" then
      if autoInputGate == 1 then 
        targetInputGate = ri.fieldDrainRate / (1 - (targetStrength/100) )
      end
    end

	-- Update the flux gates
	updateFluxGates(currentInputGate, currentOutputGate)

    -- safeguards
    --
    
    -- out of fuel, kill it
    if fuelPercent <= 10 then
      reactor.stopReactor()
      action = "Fuel below 10%, refuel"
    end

    -- field strength is too dangerous, kill and it try and charge it before it blows
    if fieldPercent <= lowestFieldPercent and ri.status == "running" then
      action = "Field Str < " ..lowestFieldPercent.."%"
      reactor.stopReactor()
      reactor.chargeReactor()
      emergencyCharge = true
    end

    -- temperature too high, kill it and activate it when its cool
    if ri.temperature > maxTemperature then
      reactor.stopReactor()
      action = "Temp > " .. maxTemperature
      emergencyTemp = true
    end

    monitor.setVisible(true) -- draw the screen.

    sleep(0)
  end
end

parallel.waitForAny(buttons, update)
