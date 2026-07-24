-- DSP kernel benchmark: a fixed-point FIR / box-blur filter swept over
-- an in-memory signal array, N passes. A radius-2 five-tap average with
-- edge clamping -- pure integer arithmetic and array-part indexing. This
-- is the tight-numeric-loop shape AOT accelerates, framed as a realistic
-- embedder task (signal/image filtering) rather than a textbook kernel:
-- the point is to confirm the win holds for work an embedder would
-- actually write, not only for mandelbrot-style microbenchmarks.
--
-- Deterministic: an inline LCG fills the signal; no math.random.
-- Expected output (N = 2000): checksum: 493853

return function (N)
  N = N or 500
  local LEN = 16384

  local sig = {}
  local lcg = 2463534242
  for i = 1, LEN do
    lcg = (lcg * 1103515245 + 12345) % 2147483648
    sig[i] = lcg % 256
  end

  local out = {}
  for i = 1, LEN do out[i] = 0 end

  local checksum = 0
  for _ = 1, N do
    for i = 1, LEN do
      local a = sig[i - 2] or sig[1]
      local b = sig[i - 1] or sig[1]
      local c = sig[i]
      local d = sig[i + 1] or sig[LEN]
      local e = sig[i + 2] or sig[LEN]
      out[i] = (a + b + c + d + e) // 5
    end
    -- feed back so successive passes actually depend on prior output
    for i = 1, LEN do sig[i] = out[i] end
    checksum = checksum + out[1] + out[LEN // 2] + out[LEN]
  end

  print(string.format("checksum: %.0f", checksum))
  return checksum
end
