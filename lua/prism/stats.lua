--- prism.stats: lightweight timing/emission counters for diagnostics.
---
--- Zero overhead when nothing reads from it — buckets store raw nanosecond
--- aggregates and only convert to microseconds in `snapshot()`. Exposed via
--- prism.stats() / :PrismStats.

local M = {}

---@class prism.stats.Bucket
---@field count    integer  number of samples
---@field total_ns integer  cumulative nanoseconds
---@field min_ns   integer  fastest observed sample (huge until first sample)
---@field max_ns   integer  slowest observed sample
---@field last_ns  integer  most recent sample

---@return prism.stats.Bucket
local function new_bucket()
  return { count = 0, total_ns = 0, min_ns = math.huge, max_ns = 0, last_ns = 0 }
end

local scan = new_bucket()
local reconcile = new_bucket()
local emissions = 0
local last_visible_count = 0
local last_desired_count = 0

---@param bucket prism.stats.Bucket
---@param ns integer
local function record(bucket, ns)
  bucket.count = bucket.count + 1
  bucket.total_ns = bucket.total_ns + ns
  if ns < bucket.min_ns then bucket.min_ns = ns end
  if ns > bucket.max_ns then bucket.max_ns = ns end
  bucket.last_ns = ns
end

---@param ns integer
---@param visible_count integer
function M.record_scan(ns, visible_count)
  record(scan, ns)
  last_visible_count = visible_count
end

---@param ns integer
---@param desired_count integer
---@param emit_count integer
function M.record_reconcile(ns, desired_count, emit_count)
  record(reconcile, ns)
  emissions = emissions + emit_count
  last_desired_count = desired_count
end

---@param b prism.stats.Bucket
local function as_us(b)
  return {
    count = b.count,
    last_us = b.last_ns / 1e3,
    min_us = b.count > 0 and b.min_ns / 1e3 or 0,
    max_us = b.max_ns / 1e3,
    mean_us = b.count > 0 and (b.total_ns / b.count / 1e3) or 0,
  }
end

---@class prism.stats.Snapshot
---@field scan               { count: integer, last_us: number, min_us: number, max_us: number, mean_us: number }
---@field reconcile          { count: integer, last_us: number, min_us: number, max_us: number, mean_us: number }
---@field emissions          integer  total set_slot + clear_slot calls since reset
---@field last_visible_count integer
---@field last_desired_count integer

---@nodiscard
---@return prism.stats.Snapshot
function M.snapshot()
  return {
    scan = as_us(scan),
    reconcile = as_us(reconcile),
    emissions = emissions,
    last_visible_count = last_visible_count,
    last_desired_count = last_desired_count,
  }
end

function M.reset()
  scan = new_bucket()
  reconcile = new_bucket()
  emissions = 0
  last_visible_count = 0
  last_desired_count = 0
end

return M
