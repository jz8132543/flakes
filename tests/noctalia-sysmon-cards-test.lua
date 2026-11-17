local source = assert(arg[1])
local group, snapshot, tree, requests, pending, now, gpuEnabled, labels
local command = { "gpu-clock" }
local poll = 5

ui = {}
for _, kind in ipairs({ "label", "column", "graph" }) do
   ui[kind] = function(props, children)
      return { kind = kind, props = props, children = children }
   end
end
desktopWidget = {
   render = function(value)
      tree = value
   end,
}
noctalia = {
   getConfig = function(key)
      return key == "group" and group or command
   end,
   getSetting = function()
      return poll
   end,
   setUpdateInterval = function(value)
      assert(value == 2000)
   end,
   systemStats = function()
      return snapshot
   end,
   setGpuMonitoring = function(value)
      gpuEnabled = value
   end,
   nowMs = function()
      return now
   end,
   runAsync = function(argv, callback)
      assert(argv == command)
      requests = requests + 1
      pending = callback
      return true
   end,
   log = function(value)
      labels = value
   end,
}

local function reset(name)
   group, now, requests, pending, tree = name, 0, 0, nil, nil
   poll = 5
   snapshot = {
      cpu = { usagePercent = 25, freqMhz = 3200, maxFreqMhz = 5000, tempC = 55 },
      gpu = { usagePercent = 40, tempC = 65, vramUsedBytes = 2147483648, vramTotalBytes = 8589934592 },
      ram = { usagePercent = 50 },
      swap = { usedMb = 0, totalMb = 0 },
      net = { rxBytesPerSec = 1250000, txBytesPerSec = 250000 },
   }
   assert(loadfile(source))()
end

local expected = {
   network = { "下载: 1.2 MB/s", "上传: 250.0 kB/s" },
   cpu = { "使用率: 25%", "频率: 3.20 GHz", "温度: 55 °C" },
   gpu = { "使用率: 40%", "频率: 不可用", "温度: 65 °C" },
   memory = { "内存使用率: 50%", "交换空间使用率: 0%" },
   vram = { "使用率: 25%", "已用容量: 2.00 GiB" },
}
for name, values in pairs(expected) do
   reset(name)
   update()
   assert(#tree.children == #values + 1)
   for index, value in ipairs(values) do
      assert(tree.children[index + 1].children[1].props.text == value)
   end
   assert(gpuEnabled == (name == "gpu" or name == "vram"))
   onIpc("inspect")
   assert(labels:find(values[1], 1, true))
   onExit()
   assert(not gpuEnabled)
end

reset("gpu")
update()
assert(requests == 1)
now = 6000
update()
assert(requests == 1) -- No second subprocess while the first query is pending.
pending({ exitCode = 0, stdout = "1530\n" })
update()
assert(tree.children[3].children[1].props.text == "频率: 1530 MHz")
pending({ exitCode = 1, stdout = "" })
update()
assert(tree.children[3].children[1].props.text == "频率: 不可用")
assert(#tree.children[3].children[2].props.values == 0)
poll = 0
now = 20000
update()
assert(not gpuEnabled and requests == 2)

reset("cpu")
for _ = 1, 100 do
   update()
end
assert(#tree.children[2].children[2].props.values == 60)
snapshot = nil
update()
assert(tree.children[2].children[1].props.text == "使用率: 不可用")
assert(#tree.children[2].children[2].props.values == 0)
assert(not gpuEnabled)
print("System monitor cards: titles, metric order, units, missing sensors, bounded history and GPU polling passed.")
