-- Codec / checksum benchmark: the edge-transform shape an embedder runs
-- in Lua -- hashing and integer decoding over an in-memory byte buffer.
-- Two passes per iteration: an FNV-1a 32-bit hash over the buffer, and a
-- LEB128 varint sum that walks the same bytes as a varint stream. Bytes
-- are held as an integer array (not a string walked with string.byte) so
-- the hot loop is VM integer and bitwise arithmetic -- Lua 5.4 native
-- integers with &, ~, *, % -- rather than per-byte C library calls. That
-- is the AOT-favorable region; a string.byte version would instead be
-- library-bound and is a different measurement.
--
-- Deterministic: an inline LCG fills the buffer; no math.random.
-- Expected output (N = 3000): checksum: 1988952016

local MASK32 = 0xFFFFFFFF

return function (N)
  N = N or 500
  local LEN = 16384

  local buf = {}
  local lcg = 2463534242
  for i = 1, LEN do
    lcg = (lcg * 1103515245 + 12345) % 2147483648
    buf[i] = lcg & 0xFF
  end

  local acc = 0
  for _ = 1, N do
    -- FNV-1a
    local h = 2166136261
    for i = 1, LEN do
      h = (h ~ buf[i]) & MASK32
      h = (h * 16777619) & MASK32
    end
    -- LEB128 varint sum: decode 7 bits per byte, high bit = continue
    local vsum = 0
    local cur, shift = 0, 0
    for i = 1, LEN do
      local b = buf[i]
      cur = cur | ((b & 0x7F) << shift)
      if b & 0x80 == 0 then
        vsum = (vsum + cur) & MASK32
        cur, shift = 0, 0
      else
        shift = (shift + 7) & 31
      end
    end
    acc = (acc + h + vsum) & MASK32
  end

  print(string.format("checksum: %.0f", acc * 1.0))
  return acc
end
