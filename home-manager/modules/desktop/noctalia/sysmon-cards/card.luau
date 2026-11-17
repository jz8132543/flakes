local group = noctalia.getConfig("group")
local titles = { network = "网络", cpu = "CPU", gpu = "GPU", memory = "内存与交换空间", vram = "显存" }
local history = {}
local lastLabels = {}
local gpuFrequency = nil
local frequencyPending = false
local nextFrequencyAt = 0

noctalia.setUpdateInterval(2000)

local function percent(used, total)
  if used == nil or total == nil then return nil end
  return total > 0 and used / total * 100 or 0
end

local function formatted(value, format)
  if value == nil then return "不可用" end
  return string.format(format, value)
end

local function rate(value)
  if value == nil then return "不可用" end
  if value >= 1000000 then return string.format("%.1f MB/s", value / 1000000) end
  if value >= 1000 then return string.format("%.1f kB/s", value / 1000) end
  return string.format("%.0f B/s", value)
end

function update()
  local stats = noctalia.systemStats()
  local gpuPoll = noctalia.getSetting("system.monitor.gpu_poll_seconds")
  noctalia.setGpuMonitoring(stats ~= nil and (group == "gpu" or group == "vram") and gpuPoll > 0)

  if group == "gpu" then
    local command = noctalia.getConfig("gpu_frequency_command")
    local now = noctalia.nowMs()
    if stats == nil or gpuPoll <= 0 then
      gpuFrequency = nil
    elseif #command > 0 and not frequencyPending and now >= nextFrequencyAt then
      frequencyPending = true
      nextFrequencyAt = now + math.max(5000, gpuPoll * 1000)
      local accepted = noctalia.runAsync(command, function(result)
        gpuFrequency = result.exitCode == 0 and tonumber(result.stdout) or nil
        frequencyPending = false
      end)
      if not accepted then
        gpuFrequency = nil
        frequencyPending = false
      end
    end
  end

  local cpu = stats and stats.cpu or {}
  local gpu = stats and stats.gpu or {}
  local ram = stats and stats.ram or {}
  local swap = stats and stats.swap or {}
  local net = stats and stats.net or {}
  local metrics
  if group == "network" then
    metrics = {
      { "下载", net.rxBytesPerSec, rate(net.rxBytesPerSec), 10000000 },
      { "上传", net.txBytesPerSec, rate(net.txBytesPerSec), 10000000 },
    }
  elseif group == "cpu" then
    metrics = {
      { "使用率", cpu.usagePercent, formatted(cpu.usagePercent, "%.0f%%"), 100 },
      { "频率", cpu.freqMhz, formatted(cpu.freqMhz and cpu.freqMhz / 1000, "%.2f GHz"), cpu.maxFreqMhz or 5000 },
      { "温度", cpu.tempC, formatted(cpu.tempC, "%.0f °C"), 100 },
    }
  elseif group == "gpu" then
    metrics = {
      { "使用率", gpu.usagePercent, formatted(gpu.usagePercent, "%.0f%%"), 100 },
      { "频率", gpuFrequency, formatted(gpuFrequency, "%.0f MHz"), 3000 },
      { "温度", gpu.tempC, formatted(gpu.tempC, "%.0f °C"), 100 },
    }
  elseif group == "memory" then
    local swapPercent = percent(swap.usedMb, swap.totalMb)
    metrics = {
      { "内存使用率", ram.usagePercent, formatted(ram.usagePercent, "%.0f%%"), 100 },
      { "交换空间使用率", swapPercent, formatted(swapPercent, "%.0f%%"), 100 },
    }
  else
    local vramPercent = percent(gpu.vramUsedBytes, gpu.vramTotalBytes)
    metrics = {
      { "使用率", vramPercent, formatted(vramPercent, "%.0f%%"), 100 },
      { "已用容量", gpu.vramUsedBytes, formatted(gpu.vramUsedBytes and gpu.vramUsedBytes / 1073741824, "%.2f GiB"), gpu.vramTotalBytes or 1 },
    }
  end

  local children = { ui.label({ text = titles[group], fontSize = 16, fontWeight = "bold" }) }
  lastLabels = { titles[group] }
  for index, metric in ipairs(metrics) do
    local samples = history[index] or {}
    history[index] = samples
    if metric[2] == nil then
      -- Missing sensors must not leave a stale graph looking like a live reading.
      samples = {}
      history[index] = samples
    else
      table.insert(samples, math.max(0, math.min(1, metric[2] / math.max(1, metric[4]))))
      if #samples > 60 then table.remove(samples, 1) end
    end
    local color = index == 1 and "primary" or (index == 2 and "secondary" or "tertiary")
    local text = metric[1] .. ": " .. metric[3]
    table.insert(lastLabels, text)
    table.insert(children, ui.column({ gap = 2, width = 232 }, {
      ui.label({ text = text, fontSize = 13, color = "on_surface", maxLines = 1 }),
      ui.graph({ values = samples, color = color, width = 232, height = 14, lineWidth = 1, fillOpacity = 0.2 }),
    }))
  end
  desktopWidget.render(ui.column({ gap = 4, width = 232 }, children))
end

function onIpc(event)
  if event == "inspect" then noctalia.log(table.concat(lastLabels, " | ")) end
end

function onExit()
  noctalia.setGpuMonitoring(false)
end
