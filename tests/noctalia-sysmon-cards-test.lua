local source = assert(arg[1])
local group, snapshot, tree, requests, pending, now, gpuEnabled, labels, layout
local command = { "gpu-clock" }
local poll = 5

ui = {}
for _, kind in ipairs({ "label", "column", "row", "graph" }) do
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
      if key == "group" then
         return group
      end
      if key == "layout" then
         return layout
      end
      return command
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
   diskStats = function()
      error("Desktop monitor must not request filesystem statistics")
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

local function reset(name, style)
   group, now, requests, pending, tree = name, 0, 0, nil, nil
   layout = style or "rows"
   poll = 5
   snapshot = {
      cpu = { usagePercent = 25, freqMhz = 3200, maxFreqMhz = 5000, tempC = 55 },
      gpu = { usagePercent = 40, tempC = 65, vramUsedBytes = 2147483648, vramTotalBytes = 8589934592 },
      ram = { usagePercent = 50, usedMb = 8192, totalMb = 16384 },
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

local function dualGraph()
   assert(#tree.children == 2)
   assert(tree.children[1].kind == "graph")
   assert(tree.children[2].kind == "row" and #tree.children[2].children == (group == "capacity" and 3 or 2))
   return tree.children[1].props, tree.children[2].children
end

reset("processors", "overview")
update()
local graph, columns = dualGraph()
assert(graph.values[1] == 0.25 and graph.values2[1] == 0.4)
assert(columns[1].children[1].props.text == "CPU")
assert(columns[2].children[1].props.text == "GPU")
assert(columns[1].children[3].props.text == "3.20 GHz / 55 °C")
assert(gpuEnabled and requests == 1)
now = 6000
update()
assert(requests == 1)
pending({ exitCode = 0, stdout = "1530\n" })
update()
graph, columns = dualGraph()
assert(columns[2].children[3].props.text == "1.53 GHz / 65 °C")
snapshot.gpu = {}
poll = 0
update()
graph, columns = dualGraph()
assert(#graph.values2 == 0 and #graph.values > 0)
assert(columns[2].children[2].props.text == "不可用")
assert(not gpuEnabled)
onExit()
assert(not gpuEnabled)

reset("capacity", "overview")
snapshot.swap = { usedMb = 1024, totalMb = 4096 }
update()
graph, columns = dualGraph()
assert(graph.values[1] == 0.5 and graph.values2[1] == 0.25)
assert(columns[1].children[3].props.text == "8.0/16.0")
assert(columns[2].children[3].props.text == "2.0/8.0")
assert(columns[3].children[1].props.text == "Swap")
assert(columns[3].children[2].props.text == "25%")
assert(columns[3].children[3].props.text == "1.0/4.0")
for _, column in ipairs(columns) do
   assert(column.props.width == 72)
   assert(#column.children == 3)
end
assert(gpuEnabled and requests == 0)
snapshot.swap = { usedMb = 0, totalMb = 0 }
snapshot.gpu = {}
update()
graph, columns = dualGraph()
assert(columns[3].children[2].props.text == "未启用")
assert(columns[2].children[3].props.text == "不可用")
assert(#graph.values2 == 0)

reset("network", "overview")
update()
graph, columns = dualGraph()
assert(graph.values[1] == 1 and graph.values2[1] == 0.2)
assert(columns[1].children[2].props.text == "1.2 MB/s")
snapshot.net = { rxBytesPerSec = 5000000, txBytesPerSec = 0 }
update()
graph = dualGraph()
assert(graph.values[1] == 0.25 and graph.values[2] == 1)
assert(graph.values2[1] == 0.05 and graph.values2[2] == 0)
for _ = 1, 61 do
   update()
end
graph = dualGraph()
assert(#graph.values == 60 and #graph.values2 == 60)
snapshot = nil
update()
graph, columns = dualGraph()
assert(#graph.values == 0 and #graph.values2 == 0)
assert(columns[1].children[2].props.text == "不可用")
assert(not gpuEnabled and requests == 0)
print("System monitor cards: titles, metric order, units, missing sensors, bounded history and GPU polling passed.")
print("Overview cards: one dual-series graph, paired readings, capacities and shared network scale passed.")
