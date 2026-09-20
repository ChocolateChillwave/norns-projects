-- run-tests.lua -- run every script's off-device suite, from the repo root.
--
--   lua run-tests.lua           all suites
--   lua run-tests.lua cascade   just one script's suites
--
-- Each suite is run with its own test/ folder as the working directory,
-- because they `require` the norns_stub sitting next to them. Exits non-zero
-- if any suite fails, so this is usable as a pre-commit check.
--
-- polyphasic has no test/ folder yet and is skipped with a note -- see
-- ROADMAP.md.

local WINDOWS = package.config:sub(1, 1) == "\\"
local LUA = arg[-1] or "lua"

-- scripts in the order they appear in the README
local SCRIPTS = { "cascade", "polyphasic", "rytmpatch", "segue", "summitpatch" }

local function quote(s)
  return '"' .. s .. '"'
end

-- shell out for the listing: plain Lua can't read a directory
local function suites_in(dir)
  local cmd
  if WINDOWS then
    cmd = "dir /b " .. quote(dir:gsub("/", "\\") .. "\\test_*.lua") .. " 2>nul"
  else
    cmd = "ls -1 " .. quote(dir) .. "/test_*.lua 2>/dev/null"
  end
  local found = {}
  local pipe = io.popen(cmd)
  if not pipe then return found end
  for line in pipe:lines() do
    -- windows `dir /b` gives bare names, `ls` gives paths; we want the name
    local name = line:match("([^/\\]+)%s*$")
    if name and name ~= "" then found[#found + 1] = name end
  end
  pipe:close()
  table.sort(found)
  return found
end

local function run(dir, suite)
  local cd = WINDOWS and ("cd /d " .. quote(dir:gsub("/", "\\"))) or ("cd " .. quote(dir))
  local pipe = io.popen(cd .. " && " .. quote(LUA) .. " " .. quote(suite) .. " 2>&1")
  if not pipe then return false, 1, "" end
  local output = pipe:read("a")
  local ok, _, code = pipe:close()
  return ok, code or 0, output or ""
end

-- the suites print their own tally; pull it out for the one-line summary
local function tally(output)
  local passed, failed = output:match("(%d+)%s+passed,%s+(%d+)%s+failed")
  if passed then return tonumber(passed), tonumber(failed) end
  return nil, nil
end

local only = arg[1]
local total_passed, total_failed, broken = 0, 0, {}

for _, script in ipairs(SCRIPTS) do
  if not only or only == script then
    local dir = script .. "/test"
    local suites = suites_in(dir)
    if #suites == 0 then
      print(string.format("%-12s  (no test/ folder yet)", script))
    end
    for _, suite in ipairs(suites) do
      local ok, code, output = run(dir, suite)
      local passed, failed = tally(output)
      total_passed = total_passed + (passed or 0)
      total_failed = total_failed + (failed or 0)
      if ok and code == 0 then
        print(string.format("  ok    %s/%s  (%s checks)", script, suite, passed or "?"))
      else
        print(string.format("  FAIL  %s/%s  (exit %s)", script, suite, code))
        print((output:gsub("^", "        "):gsub("\n", "\n        ")))
        broken[#broken + 1] = script .. "/" .. suite
      end
    end
  end
end

print()
if #broken == 0 then
  print(string.format("all green -- %d checks passed", total_passed))
  os.exit(0)
else
  print(string.format("%d checks passed, %d failed; %d suite(s) broken:",
    total_passed, total_failed, #broken))
  for _, name in ipairs(broken) do print("  " .. name) end
  os.exit(1)
end
