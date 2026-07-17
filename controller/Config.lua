--[[
Config.lua - Configuration validation and defaults.

Validates user-provided configuration and provides sensible defaults.
]]

local Config = {}

--[[
Creates and validates a configuration table.

Expected fields:
- minimumFieldPercent: minimum safe field strength (e.g., 0.15 = 15%)
- targetFieldPercent: desired field strength (e.g., 0.50 = 50%)
- maximumTemperature: shutdown threshold in degrees Celsius
- targetOutputFlux: desired output RF/t (or nil for manual control)
- targetInputFlux: desired input RF/t (or nil for auto)
- autoInputFlux: if true, automatically calculate input from field error
- outputRampSpeed: maximum output increase per second (0-1 range)
- maximumInputFlux: optional maximum input limit

Returns:
- validated config table, or nil
- error message if validation failed
]]
function Config.new(userConfig)
	if type(userConfig) ~= "table" then
		return nil, "Configuration must be a table"
	end

	-- Make a copy to avoid modifying user's table
	local cfg = {}
	for k, v in pairs(userConfig) do
		cfg[k] = v
	end

	-- Validate and set defaults
	local errors = {}

	-- Field strength percentages
	if cfg.minimumFieldPercent == nil then
		cfg.minimumFieldPercent = 0.15
	end
	if type(cfg.minimumFieldPercent) ~= "number" or cfg.minimumFieldPercent < 0 or cfg.minimumFieldPercent > 1 then
		table.insert(errors, "minimumFieldPercent must be a number between 0 and 1")
	end

	if cfg.targetFieldPercent == nil then
		cfg.targetFieldPercent = 0.50
	end
	if type(cfg.targetFieldPercent) ~= "number" or cfg.targetFieldPercent < 0 or cfg.targetFieldPercent > 1 then
		table.insert(errors, "targetFieldPercent must be a number between 0 and 1")
	end

	if cfg.minimumFieldPercent >= cfg.targetFieldPercent then
		table.insert(errors, "minimumFieldPercent must be less than targetFieldPercent")
	end

	-- Temperature
	if cfg.maximumTemperature == nil then
		cfg.maximumTemperature = 8000
	end
	if type(cfg.maximumTemperature) ~= "number" or cfg.maximumTemperature <= 0 then
		table.insert(errors, "maximumTemperature must be a positive number")
	end

	-- Output flux
	if cfg.targetOutputFlux ~= nil then
		if type(cfg.targetOutputFlux) ~= "number" or cfg.targetOutputFlux < 0 then
			table.insert(errors, "targetOutputFlux must be a non-negative number or nil")
		end
	end

	-- Input flux
	if cfg.targetInputFlux ~= nil then
		if type(cfg.targetInputFlux) ~= "number" or cfg.targetInputFlux < 0 then
			table.insert(errors, "targetInputFlux must be a non-negative number or nil")
		end
	end

	-- Auto input mode
	if cfg.autoInputFlux == nil then
		cfg.autoInputFlux = true
	end
	if type(cfg.autoInputFlux) ~= "boolean" then
		table.insert(errors, "autoInputFlux must be a boolean")
	end

	-- Output ramp speed
	if cfg.outputRampSpeed == nil then
		cfg.outputRampSpeed = 0.05
	end
	if type(cfg.outputRampSpeed) ~= "number" or cfg.outputRampSpeed <= 0 or cfg.outputRampSpeed > 1 then
		table.insert(errors, "outputRampSpeed must be a number between 0 and 1")
	end

	-- Maximum input (optional)
	if cfg.maximumInputFlux ~= nil then
		if type(cfg.maximumInputFlux) ~= "number" or cfg.maximumInputFlux < 0 then
			table.insert(errors, "maximumInputFlux must be a non-negative number or nil")
		end
	end

	if #errors > 0 then
		return nil, table.concat(errors, "; ")
	end

	return cfg
end

return Config

