-- One private, time-seeded DFHack RNG shared across GUI/console invocations.
--@ module = true
local rng = dfhack.random.new()
function index(limit) return rng:random(limit) + 1 end
