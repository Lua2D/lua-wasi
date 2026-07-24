-- Data-plane aggregate benchmark: a stand-in for the compute-in-engine
-- database shape (e.g. TallyDB), where Lua runs aggregations over data
-- already resident in memory so compute skips copy/serialization. Build
-- two numeric columns once, then run N filtered scan/aggregate passes:
-- SUM(value) WHERE value >= threshold, a COUNT, and an 8-way GROUP BY
-- tally. The hot passes are array-part integer indexing plus integer
-- arithmetic with no allocation, so this probes the arithmetic-bound
-- region AOT can help -- unlike the table/GC-bound game set (issue #10).
-- Columns are held as integer arrays (not a packed string read through
-- string.unpack) on purpose: it keeps the hot loop in the VM's own
-- arithmetic rather than in per-element C library calls, which is the
-- work AOT actually compiles.
--
-- Deterministic: an inline LCG fills the columns; no math.random.
-- Expected output (N = 2000): checksum: 30019646000

return function (N)
  N = N or 500
  local ROWS = 20000
  local GROUPS = 8
  local THRESHOLD = 500

  local value = {}
  local group = {}
  local lcg = 2463534242
  for i = 1, ROWS do
    lcg = (lcg * 1103515245 + 12345) % 2147483648
    value[i] = lcg % 1000
    group[i] = lcg % GROUPS
  end

  local gsum = {}
  for g = 0, GROUPS - 1 do gsum[g] = 0 end
  local total = 0
  for _ = 1, N do
    local s, c = 0, 0
    for i = 1, ROWS do
      local v = value[i]
      if v >= THRESHOLD then
        s = s + v
        c = c + 1
        local g = group[i]
        gsum[g] = gsum[g] + v
      end
    end
    total = total + s + c
  end

  local checksum = total
  for g = 0, GROUPS - 1 do checksum = checksum + gsum[g] end
  print(string.format("checksum: %.0f", checksum))
  return checksum
end
