-- modifiable variables
local reactorSide = "back"
local outputFluxgateSide = "right"

local targetStrength = 20
local maxTemperature = 8000
local safeTemperature = 3000
local lowestFieldPercent = 3

local activateOnCharged = 1

local inputRampRate = 0.1
local outputRampRate = 0.2

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

    -- output gate controls
    -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
    -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000
    if yPos == 8 then
      if xPos >= 2 and xPos <= 4 then
        targetOutputGate = targetOutputGate-1000
      elseif xPos >= 6 and xPos <= 9 then
        targetOutputGate = targetOutputGate-10000
      elseif xPos >= 10 and xPos <= 12 then
        targetOutputGate = targetOutputGate-100000
      elseif xPos >= 17 and xPos <= 19 then
        targetOutputGate = targetOutputGate+100000
      elseif xPos >= 21 and xPos <= 23 then
        targetOutputGate = targetOutputGate+10000
      elseif xPos >= 25 and xPos <= 27 then
        targetOutputGate = targetOutputGate+1000
      end
      save_config()
    end

    -- input gate controls
    -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
    -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000
    if yPos == 10 and autoInputGate == 0 and xPos ~= 14 and xPos ~= 15 then
      if xPos >= 2 and xPos <= 4 then
        targetInputGate = targetInputGate-1000
      elseif xPos >= 6 and xPos <= 9 then
        targetInputGate = targetInputGate-10000
      elseif xPos >= 10 and xPos <= 12 then
        targetInputGate = targetInputGate-100000
      elseif xPos >= 17 and xPos <= 19 then
        targetInputGate = targetInputGate+100000
      elseif xPos >= 21 and xPos <= 23 then
        targetInputGate = targetInputGate+10000
      elseif xPos >= 25 and xPos <= 27 then
        targetInputGate = targetInputGate+1000
      end
      save_config()
    end

    -- input gate toggle
    if yPos == 10 and ( xPos == 14 or xPos == 15) then
      if autoInputGate == 1 then
        autoInputGate = 0
      else
        autoInputGate = 1
      end
      save_config()
    end

  end
end

function drawButtons(y)

  -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
  -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000

  f.draw_text(mon, 2, y, " < ", colors.white, colors.gray)
  f.draw_text(mon, 6, y, " <<", colors.white, colors.gray)
  f.draw_text(mon, 10, y, "<<<", colors.white, colors.gray)

  f.draw_text(mon, 17, y, ">>>", colors.white, colors.gray)
  f.draw_text(mon, 21, y, ">> ", colors.white, colors.gray)
  f.draw_text(mon, 25, y, " > ", colors.white, colors.gray)
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
        currentInputGate = f.approachLog(
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
        currentOutputGate = f.approachLog(
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
    f.progress_bar_dual(mon, 2, 5, mon.X-2, ri.generationRate, currentOutputGate, colors.lime, colors.blue, colors.gray, targetOutputGate)

    local tempColor = colors.red
    if ri.temperature <= 5000 then tempColor = colors.green end
    if ri.temperature >= 5000 and ri.temperature <= 6500 then tempColor = colors.orange end
    f.draw_text_lr(mon, 2, 6, 1, "Temperature", f.format_int(ri.temperature, 2) .. " C", colors.white, tempColor, colors.black)

    f.draw_text_lr(mon, 2, 7, 1, "Output Gate", f.format_int(currentOutputGate) .. " rf/t", colors.white, colors.blue, colors.black)

    -- buttons
    drawButtons(8)

    f.draw_text_lr(mon, 2, 9, 1, "Input Gate", f.format_int(currentInputGate) .. " rf/t", colors.white, colors.blue, colors.black)

    if autoInputGate == 1 then
      f.draw_text(mon, 14, 10, "AU", colors.white, colors.gray)
    else
      f.draw_text(mon, 14, 10, "MA", colors.white, colors.gray)
      drawButtons(10)
    end

    local satPercent
    satPercent = math.ceil(ri.energySaturation / ri.maxEnergySaturation * 10000)*.01

    f.draw_text_lr(mon, 2, 11, 1, "Energy Saturation", string.format("%.2f%%", satPercent), colors.white, colors.white, colors.black)
    f.progress_bar(mon, 2, 12, mon.X-2, satPercent, 100, colors.blue, colors.gray)

    local fieldPercent, fieldColor
    fieldPercent = math.ceil(ri.fieldStrength / ri.maxFieldStrength * 10000)*.01

    fieldColor = colors.red
    if fieldPercent >= 50 then fieldColor = colors.green end
    if fieldPercent < 50 and fieldPercent > 30 then fieldColor = colors.orange end
    targetFieldColor = colors.magenta
    if targetStrength >= 50 then targetFieldColor = colors.lime end
    if targetStrength < 50 and targetStrength > 30 then targetFieldColor = colors.yellow end

    if autoInputGate == 1 then 
      f.draw_text_llr(mon, 2, 14, 1, "Field Strength", "T:" .. targetStrength, string.format("%.2f%%", fieldPercent), colors.white, targetFieldColor, fieldColor, colors.black)
	  f.progress_bar_dual(mon, 2, 15, mon.X-2, fieldPercent, targetStrength, fieldColor, targetFieldColor, colors.gray, 100)
    else
      f.draw_text_lr(mon, 2, 14, 1, "Field Strength", string.format("%.2f%%", fieldPercent), colors.white, fieldColor, colors.black)
	  f.progress_bar(mon, 2, 15, mon.X-2, fieldPercent, 100, fieldColor, colors.gray)
    end

    local fuelPercent, fuelColor

    fuelPercent = 100 - math.ceil(ri.fuelConversion / ri.maxFuelConversion * 10000)*.01

    fuelColor = colors.red

    if fuelPercent >= 70 then fuelColor = colors.green end
    if fuelPercent < 70 and fuelPercent > 30 then fuelColor = colors.orange end

    f.draw_text_lr(mon, 2, 17, 1, "Fuel ", string.format("%.2f%%", fuelPercent), colors.white, fuelColor, colors.black)
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
