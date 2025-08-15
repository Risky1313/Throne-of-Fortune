-- Global event modifiers; other systems read from here.
local EventService = {}

EventService.State = {
	Active = false,
	EndsAt = 0,
	Modifiers = {
		PrinterPPS = 1.0,
		ChairMultiplier = 1.0,
		CoinFlipPayout = 1.0,
		WheelPayout = 1.0,
	},
	Name = "Idle",
}

-- Example: start a 30-min Double Mint Hour on server start
task.delay(5, function()
	EventService.State.Active = true
	EventService.State.EndsAt = os.time() + 30*60
	EventService.State.Modifiers.PrinterPPS = 2.0
	EventService.State.Name = "Double Mint Hour"
end)

return EventService
