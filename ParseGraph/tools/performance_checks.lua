-- Compare the optimized functions against the untouched backup, with no game,
-- saved-data access, UI windows, or chat side effects.
-- OBS supplies LuaJIT's Lua 5.1 API. Disable its JIT for representative Lua
-- interpreter benchmarks, while keeping timings separate from game FPS.
if jit ~= nil then jit.off(); jit.flush(); end
print("Runtime: " .. _VERSION .. (jit and " / " .. jit.version .. " (JIT disabled)" or ""));
local baseline = TEST_ROOT .. "backups/performance-2026-09-13/";
local function read(path)
    local file = assert(io.open(path, "rb"));
    local source = file:read("*a");
    file:close();
    return (string.gsub(source, "\r\n", "\n"));
end

local function equal(a, b, path)
    path = path or "value";
    assert(type(a) == type(b), path .. ": type mismatch");
    if type(a) ~= "table" then
        assert(a == b, path .. ": " .. tostring(a) .. " ~= " .. tostring(b));
        return;
    end
    for key, value in pairs(a) do equal(value, b[key], path .. "." .. tostring(key)); end
    for key in pairs(b) do assert(a[key] ~= nil, path .. ": extra " .. tostring(key)); end
end

local function newEnvironment(directory, lazyIcons)
    local env = setmetatable({}, { __index = _G });
    env._G = env;
    env.import = function() end;
    env.clock = 1000;
    local classes = {};
    for i, name in ipairs({"Burglar", "Brawler", "Captain", "Champion", "Mariner", "Corsair", "Chicken", "Guardian", "Hunter", "LoreMaster", "Minstrel", "RuneKeeper", "Warden", "Beorning", "BlackArrow", "Defiler", "Reaver", "Stalker", "WarLeader", "Weaver"}) do classes[name] = i; end
    env.Turbine = {
        Engine = {
            GetGameTime = function() return env.clock; end,
            GetDate = function() return {Year=2026, Month=9, Day=13, Hour=12, Minute=0, Second=0}; end
        },
        Gameplay = {Class = classes},
        UI = {Color = function(...) return {...}; end, Lotro = {Font = {}}}
    };
    local source = read(directory .. "Main.lua");
    -- Startup begins here; all plugin function definitions needed below precede it.
    local stop = assert(string.find(source, "\nif ParseGraph.Command ~= nil and Turbine.Shell.RemoveCommand", 1, true));
    local chunk = assert(loadstring(string.sub(source, 1, stop - 1), "@" .. directory .. "Main.lua"));
    setfenv(chunk, env)();
    if not lazyIcons then
        for _, name in ipairs({"SkillIcons.lua", "SkillIconLUT.lua"}) do
            local icons = assert(loadstring(read(directory .. name), "@" .. name));
            setfenv(icons, env)();
        end
    end
    env.ParseGraph.PlayerNameLower = "tester";
    env.ParseGraph.GetCurrentCharacterName = function() return "Tester"; end;
    env.ParseGraph.GetPlayerName = function() return "Tester"; end;
    env.ParseGraph.IsPlayerInCombat = function() return false; end;
    return env;
end

local old = newEnvironment(baseline);
local new = newEnvironment(TEST_ROOT);
print("PASS: plugin definitions load in both environments");

local oldIcons, newIcons = old.ParseGraph_GetIcons(), new.ParseGraph_GetIcons();
equal(oldIcons, newIcons, "icons");
local count = 0;
for _ in pairs(newIcons) do count = count + 1; end
for name, classId in pairs(old.Turbine.Gameplay.Class) do
    local player = {GetClass = function() return classId; end};
    old.player, new.player = player, player;
    equal(old.ParseGraph_GetIconLUT(player), new.ParseGraph_GetIconLUT(player), "class icons " .. name);
end
print("PASS: " .. count .. " base icon mappings and every class-specific lookup match");

local lazy = newEnvironment(TEST_ROOT, true);
local imports = {};
lazy.import = function(module)
    imports[#imports + 1] = module;
    local name = assert(string.match(module, "^Arebel%.ParseGraph%.(SkillIcon[^.]+)$"));
    local chunk = assert(loadstring(read(TEST_ROOT .. name .. ".lua"), "@" .. name));
    setfenv(chunk, lazy)();
end
local oldNoPlayer = newEnvironment(baseline);
assert(rawget(lazy, "ParseGraph_GetIcons") == nil and #imports == 0);
equal(oldNoPlayer.ParseGraph.GetSkillIconTable(), lazy.ParseGraph.GetSkillIconTable(), "lazy icon fallback without global player");
assert(#imports == 2, "icon modules should load only on first request");
lazy.ParseGraph.GetSkillIconTable();
assert(#imports == 2, "icon lookup modules were imported again");
for _, env in ipairs({oldNoPlayer, lazy}) do
    env.ParseGraph.SkillIconTable = nil;
    env.player = {GetClass = function() return env.Turbine.Gameplay.Class.Hunter; end};
end
equal(oldNoPlayer.ParseGraph.GetSkillIconTable(), lazy.ParseGraph.GetSkillIconTable(), "lazy class icons");
local broken = newEnvironment(TEST_ROOT, true);
broken.import = function() error("Optional module unavailable") end;
equal(broken.ParseGraph.GetSkillIconTable(), {}, "missing optional icon modules");
print("PASS: lazy icon loading, existing fallback, class overrides and one-time imports");
local startupImports = {};
local startupEnv = {import = function(module) startupImports[#startupImports + 1] = module end};
local init = assert(loadstring(read(TEST_ROOT .. "__init__.lua"), "@__init__.lua"));
setfenv(init, startupEnv)();
equal(startupImports, {"Arebel.ParseGraph.Main"}, "startup imports");

-- Exercise real parsing rules, including pets, reflects, timestamps, power
-- damage, quoted messages, markup inserted inside words, and malformed input.
local lines = {
    "", "Hello fellowship!", "Class Specialization Bonus Trait: The Huntsman",
    "You applied a benefit with Rapid Fire on Tester.",
    "Tester applied a benefit with Aim on Tester.",
    "Another applied a benefit with Aim on Tester.",
    "You applied a benefit with  on Tester.",
    "You scored a hit with Quick Shot on the Training Snowman for 12,345 Beleriand damage to Morale.",
    "Tester scored a critical hit with Heart Seeker on the DPS Target Dummy for 24,000 (common) Light damage to Morale.",
    "You scored a devastating hit with Swift Bow on the Dummy Warg for 123.5 Fire damage to Morale.",
    "Lynx scored a hit with Bite on the Training Snowman for 10 Common damage to Morale.",
    "Training Snowman scored a hit on Tester for 20 Common damage to Morale.",
    "You scored a hit on the Training Snowman for 10 Common damage to Power.",
    "You scored a hit on the Goblin for 100 Common damage to Morale.",
    "You reflected 1,200 Light damage to the Morale of the Training Snowman.",
    "Tester reflected 12 Fire damage to the Power of the Dummy Warg.",
    "Another reflected 100 Light damage to the Morale of the Training Snowman.",
    "You scored a hit on the Training Snowman for broken damage to Morale.",
    "Your mighty blow defeated Goblin.", "Goblin incapacitated you.",
    "Tester defeated Goblin.", "<rgb=#ff00ff>Markup</rgb> <unfinished",
    "You sco<rgb=#123456>red a </rgb>hit on the Training Snowman for 42 Common damage to Morale.",
    "You app<RGB=#123456>lied a benefit with </RGB>Aim on Tester.",
    "You scored a\thit on the Training Snowman for 10 Common damage to Morale.",
    "\tYou scored a hit on the Training Snowman for 10 Common damage to Morale.\n",
    "Grárgh! Training Snowman says, 'Merry Yule!'"
};
local baseCount = #lines;
for i = 1, baseCount do
    local line = lines[i];
    lines[#lines + 1] = "[09/13 12:00:00] " .. line;
    lines[#lines + 1] = "<rgb=#ffee00>" .. line .. "</rgb>";
    lines[#lines + 1] = "You say, '" .. line .. "'";
    lines[#lines + 1] = "[To Fellowship] " .. line;
    lines[#lines + 1] = "Someone says, '" .. line .. "'";
end
for i = 1, 250 do
    local name = i % 2 == 0 and "Dummy Warg" or "Training Snowman";
    lines[#lines + 1] = "You scored a " .. (i % 3 == 0 and "critical " or "") .. "hit with Skill " .. i .. " on the " .. name .. " for " .. i * 97 .. " Fire damage to Morale.";
    lines[#lines + 1] = "Unrelated chat " .. string.rep("data ", i % 40) .. tostring(i);
end
local parseFunctions = {"ParseDummyDamageEvent", "ParseDummyBenefitEvent", "IsPlayerDummyHitText", "ExtractScoreboardDeathVictimName", "ExtractFallbackScoreboardMobFromCombatLine", "ExtractSayInfoText", "GetOwnCombatAnalysisPayload", "GetInstanceDefinitionFromQuestText"};
for _, name in ipairs(parseFunctions) do
    for i, line in ipairs(lines) do
        equal({old.ParseGraph[name](line)}, {new.ParseGraph[name](line)}, name .. " line " .. i);
    end
end
local oldState, newState = {}, {};
for i, line in ipairs(lines) do
    equal(old.ParseGraph.RecordParseCombatEvent(oldState, line), new.ParseGraph.RecordParseCombatEvent(newState, line), "record " .. i);
end
equal(oldState, newState, "combat summary");
print("PASS: " .. #lines .. " chat inputs across eight parsers and complete combat summaries match");

-- Find a local helper through its caller without exporting testing APIs.
local function upvalue(fn, wanted)
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i);
        if name == nil then break end
        if name == wanted then return value end
    end
    error("Missing upvalue " .. wanted);
end
local oldStrip = upvalue(old.ParseGraph.ParseDummyDamageEvent, "StripLotroMarkup");
local newStrip = upvalue(new.ParseGraph.ParseDummyDamageEvent, "StripLotroMarkup");
for _, line in ipairs(lines) do equal(oldStrip(line), newStrip(line), "markup"); end
for _, value in ipairs({false, true, 0, 123.5}) do equal(oldStrip(value), newStrip(value), "markup coercion"); end
equal(oldStrip(nil), newStrip(nil), "nil markup");

local parses = {};
for i = 1, 10000 do
    parses[i] = {
        final = i % 13 == 0 and "invalid" or tostring(100000 + i),
        minutes = {i % 5 == 0 and "invalid" or 90000 + i, 110000 + i},
        time = i > 9500 and "2026-09-13 12:00:00" or "2026-09-12 12:00:00",
        specKey = ({"red", "blue", "yellow"})[i % 3 + 1],
        __sourceKey = "tester", __sourceIndex = i
    };
end
for _, env in ipairs({old, new}) do
    env.ParseGraph.Parses = parses;
    env.ParseGraph.CombineSameClass = false;
    env.ParseGraph.ViewCharacterKey = "tester";
    env.ParseGraph.SessionStartCount = 9700;
    env.ParseGraph.GetCurrentCharacterKey = function() return "tester"; end;
end
for _, mode in ipairs({"all", "today", "session"}) do
    for _, spec in ipairs({"all", "red", "blue", "yellow"}) do
        for _, limit in ipairs({0, 1, 3, 100, 15000}) do
            old.ParseGraph.ShowMode, new.ParseGraph.ShowMode = mode, mode;
            old.ParseGraph.ParseSpecFilterKey, new.ParseGraph.ParseSpecFilterKey = spec, spec;
            equal(old.ParseGraph.GetDisplayedParsePoints(limit), new.ParseGraph.GetDisplayedParsePoints(limit), "display points " .. mode .. "/" .. spec .. "/" .. limit);
            equal(old.ParseGraph.GetParseHistoryPoints(limit), new.ParseGraph.GetParseHistoryPoints(limit), "history points");
        end
        equal(old.ParseGraph.GetAllTimeStats(), new.ParseGraph.GetAllTimeStats(), "filtered stats");
        equal(old.ParseGraph.GetAllTimeStats(true), new.ParseGraph.GetAllTimeStats(true), "all stats");
    end
end
equal(old.ParseGraph.GetDisplayedParsePoints(), new.ParseGraph.GetDisplayedParsePoints(), "unlimited points");
equal(old.ParseGraph.GetParseHistoryPoints(), new.ParseGraph.GetParseHistoryPoints(), "unlimited history");
equal(new.ParseGraph.GetDisplayedParsePoints(100), new.ParseGraph.GetDisplayedParsePoints(100, parses), "shared graph source");
print("PASS: 10,000-record history, ordering, limits, spec/date/session filters and statistics match");

-- Use real combined-character construction too, including duplicate times and
-- source indexes; history rows must still point to the same characters.
for _, env in ipairs({old, new}) do
    local pg = env.ParseGraph;
    pg.CombineSameClass = true;
    pg.GetViewCharacterEntry = function() return {classKey="hunter"}; end;
    pg.ForEachViewClassCharacter = function(visit)
        visit("tester", {name="Tester", parses=parses}, true);
        visit("alt", {name="Alt", parses={
            {final=234567, time="2026-09-13 12:00:00", specKey="red"},
            {final=245678, time="2026-09-13 13:00:00", specKey="blue"}
        }}, false);
    end;
    pg.ShowMode, pg.ParseSpecFilterKey = "all", "all";
end
equal(old.ParseGraph.GetDisplayedParsePoints(100), new.ParseGraph.GetDisplayedParsePoints(100), "combined characters");
equal(old.ParseGraph.GetParseHistoryPoints(100), new.ParseGraph.GetParseHistoryPoints(100), "combined history");
for _, env in ipairs({old, new}) do env.ParseGraph.CombineSameClass = false; end
print("PASS: combined-character history retains ordering and source identity");

-- Mock UI setters to verify visible state and count redundant operations.
local function setupUI(env)
    env.setterCount = 0;
    local function control()
        local obj = {state = {}};
        return setmetatable(obj, {__index = function(_, key)
            if key == "GetLeft" then return function(self) return self.state.position and self.state.position[1] or 0; end end
            if key == "GetTop" then return function(self) return self.state.position and self.state.position[2] or 0; end end
            if key == "SetPosition" then return function(self, x, y) env.setterCount = env.setterCount + 1; self.state.position = {x,y}; end end
            if string.sub(key, 1, 3) == "Set" then
                return function(self, ...)
                    env.setterCount = env.setterCount + 1;
                    if key ~= "SetParent" then self.state[key] = {...}; end
                end;
            end
        end});
    end
    env.Turbine.UI.Control, env.Turbine.UI.Window, env.Turbine.UI.Label = control, control, control;
    env.Turbine.UI.ContentAlignment = {MiddleCenter = 1};
    env.Turbine.UI.Lotro.Font = {TrajanProBold16=16, TrajanPro13=13, TrajanProBold22=22};
    local pg = env.ParseGraph;
    pg.LauncherButton = control();
    pg.LauncherButton:SetPosition(20, 220);
    pg.ShowLauncherButton, pg.ShowLauncherTimer = true, true;
    pg.ActiveParse = {start = 1000};
end
setupUI(old); setupUI(new);
local function compareTimer()
    old.ParseGraph.UpdateLauncherTimerOverlay();
    new.ParseGraph.UpdateLauncherTimerOverlay();
    equal(old.ParseGraph.LauncherTimerBack.state, new.ParseGraph.LauncherTimerBack.state, "timer back");
    equal(old.ParseGraph.LauncherTimerLabel.state, new.ParseGraph.LauncherTimerLabel.state, "timer text");
    for i = 1, 8 do
        equal(old.ParseGraph.LauncherTimerTextShadows[i].state, new.ParseGraph.LauncherTimerTextShadows[i].state, "timer shadow " .. i);
    end
end
compareTimer();
old.setterCount, new.setterCount = 0, 0;
for i = 1, 600 do
    old.clock, new.clock = 1000 + (i - 1) / 60, 1000 + (i - 1) / 60;
    old.ParseGraph.LauncherTimerUpdateControl.Update();
    new.ParseGraph.LauncherTimerUpdateControl.Update();
    equal(old.ParseGraph.LauncherTimerLabel.state, new.ParseGraph.LauncherTimerLabel.state, "frame " .. i);
end
print("BENCH: 600 timer frames, UI setter calls " .. old.setterCount .. " -> " .. new.setterCount);
for _, state in ipairs({"hover", "pressed", "", "active"}) do
    old.ParseGraph.LauncherButtonState, new.ParseGraph.LauncherButtonState = state, state;
    compareTimer();
end
for _, key in ipairs({"small", "large", "medium"}) do
    for _, env in ipairs({old, new}) do
        env.ParseGraph.LauncherButtonSizeKey = key;
        env.ParseGraph.LauncherButtonSize = env.ParseGraph.LauncherButtonSizes[key];
        env.ParseGraph.LauncherButton:SetPosition(300, 420);
    end
    compareTimer();
end
for _, field in ipairs({"GameUiHidden", "ShowLauncherButton", "ShowLauncherTimer"}) do
    for _, value in ipairs({true, false, true}) do
        old.ParseGraph[field], new.ParseGraph[field] = value, value;
        compareTimer();
    end
    old.ParseGraph.GameUiHidden, new.ParseGraph.GameUiHidden = false, false;
end
old.ParseGraph.ActiveParse, new.ParseGraph.ActiveParse = nil, nil;
compareTimer();
old.ParseGraph.ActiveParse, new.ParseGraph.ActiveParse = {start=1009}, {start=1009};
compareTimer();
old.ParseGraph.LauncherTimerTextShadows[3], new.ParseGraph.LauncherTimerTextShadows[3] = nil, nil;
compareTimer();
old.ParseGraph.LauncherTimerLabel, new.ParseGraph.LauncherTimerLabel = nil, nil;
compareTimer();
for _, env in ipairs({old, new}) do
    env.ParseGraph.LauncherButton:SetPosition(420, 420);
    local back = env.ParseGraph.LauncherTimerBack;
    local setBackground = back.SetBackground;
    back.SetBackground = function(self, ...)
        self.SetBackground = setBackground;
        error("temporary texture load failure");
    end;
end
compareTimer();
compareTimer();
print("PASS: timer frames, hover, press, movement, sizes, visibility, restart, replacement and texture retries match");

local clear = upvalue(new.ParseGraph.DrawTrendGraph, "ClearChildren");
local child = {Update = function() end};
function child:SetWantsUpdates(value) self.wantsUpdates = value end
function child:SetParent(value) self.parent = value end
local collection = {GetCount = function() return 1 end, Get = function() return child end};
clear({GetControls = function() return collection end});
assert(child.Update == nil and child.wantsUpdates == false and child.parent == nil, "retired callback retained");
print("PASS: discarded list callbacks are disabled and released");

local function benchmark(label, before, after, repeats)
    local function measure(fn)
        collectgarbage("collect");
        local start = os.clock();
        for i = 1, repeats do fn(i); end
        return os.clock() - start;
    end
    local a, b = measure(before), measure(after);
    print(string.format("BENCH: %s (%d calls): %.4fs -> %.4fs", label, repeats, a, b));
end
benchmark("plain-text markup", function(i) oldStrip(lines[i % #lines + 1]); end, function(i) newStrip(lines[i % #lines + 1]); end, 100000);
benchmark("mixed damage parsing", function(i) old.ParseGraph.ParseDummyDamageEvent(lines[i % #lines + 1]); end, function(i) new.ParseGraph.ParseDummyDamageEvent(lines[i % #lines + 1]); end, 20000);
old.ParseGraph.ShowMode, new.ParseGraph.ShowMode = "all", "all";
old.ParseGraph.ParseSpecFilterKey, new.ParseGraph.ParseSpecFilterKey = "all", "all";
benchmark("latest 3 of 10,000", function() old.ParseGraph.GetDisplayedParsePoints(3); end, function() new.ParseGraph.GetDisplayedParsePoints(3); end, 100);
benchmark("latest 100 history records", function() old.ParseGraph.GetParseHistoryPoints(100); end, function() new.ParseGraph.GetParseHistoryPoints(100); end, 100);
benchmark("base icon table construction", old.ParseGraph_GetIcons, new.ParseGraph_GetIcons, 100);
local function bytecodeSize(fn) return #string.dump(fn); end
print("BENCH: icon function bytecode bytes " .. bytecodeSize(old.ParseGraph_GetIcons) .. " -> " .. bytecodeSize(new.ParseGraph_GetIcons));
local function allocation(fn)
    collectgarbage("collect");
    collectgarbage("stop");
    local before = collectgarbage("count");
    local result = fn();
    local allocated = collectgarbage("count") - before;
    collectgarbage("restart");
    assert(result ~= nil);
    return allocated;
end
print(string.format("BENCH: transient allocation for latest 3 of 10,000: %.1f KiB -> %.1f KiB",
    allocation(function() return old.ParseGraph.GetDisplayedParsePoints(3); end),
    allocation(function() return new.ParseGraph.GetDisplayedParsePoints(3); end)));
print(string.format("BENCH: transient allocation for latest 100 history records: %.1f KiB -> %.1f KiB",
    allocation(function() return old.ParseGraph.GetParseHistoryPoints(100); end),
    allocation(function() return new.ParseGraph.GetParseHistoryPoints(100); end)));
print("All performance regression checks passed.");
