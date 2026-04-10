local Midididi = {}

local reflection = require("reflection")

local patterns = {}
local norns_midi_event
local output_midi_device

-- try adjusting these if you find yourself accidentally clearing loops by bumping knobs
local TOLERANCE_TIME_MS = 200 -- time after recording cc loop stops before it can be cleared
local TOLERANCE_DISTANCE = 0 -- difference between cc values after cc loop stops before it can be cleared

local MIDI_EVENT_CODES = {
    [0x80] = "note_off",
    [0x90] = "note_on",
    [0xB0] = "cc",
}

local on_rec_change
local on_midi_info_change
local enabled_device_id
local initialized = false

local function copy_midi_msg(midi_msg)
    local msg_copy = {}
    for i = 1, #midi_msg do
        msg_copy[i] = midi_msg[i]
    end
    return msg_copy
end

local function send_midi_output(midi_msg)
    if output_midi_device == nil and enabled_device_id ~= nil then
        output_midi_device = midi.connect(enabled_device_id)
    end

    if output_midi_device ~= nil and midi_msg ~= nil then
        output_midi_device:send(midi_msg)
    end
end

local function notify_midi_info(device_id, channel, event_id, rec_state, value, event)
    if on_rec_change ~= nil then
        on_rec_change(device_id, channel, event_id, rec_state, value, event)
    end

    if on_midi_info_change ~= nil then
        on_midi_info_change(device_id, channel, event_id, rec_state, value, event)
    end
end

local function create_pattern(device_id, channel, event_id)
    local pattern = {}
    pattern.device_id = device_id
    pattern.channel = channel
    pattern.event_id = event_id
    pattern.last_value = 0
    pattern.loop = reflection:new()
    pattern.loop:set_loop(1)
    pattern.loop.process = function(event)
        send_midi_output(event.midi_msg)
    end
    table.insert(patterns, pattern)
    return pattern
end

local function get_pattern(device_id, channel, event_id)
    for _, p in pairs(patterns) do
        if p.device_id == device_id and p.channel == channel and p.event_id == event_id then
            return p
        end
    end
end

local function on_midi_event(device_id, midi_msg)
    if device_id ~= enabled_device_id then
        norns_midi_event(device_id, midi_msg)
        return
    end
    local event_code = midi_msg[1] & 0xF0
    local channel = (midi_msg[1] & 0x0F) + 1
    local event_id = midi_msg[2]
    local event = MIDI_EVENT_CODES[event_code]
    local value = midi_msg[3]
    local pattern = get_pattern(device_id, channel, event_id)
    if pattern == nil then
        pattern = create_pattern(device_id, channel, event_id)
    end

    if event == "note_on" then
        pattern.loop:clear()
        pattern.loop:set_rec(1)
        notify_midi_info(device_id, channel, event_id, 1, value, event)
    elseif pattern and event == "note_off" then
        pattern.loop:set_rec(0)
        pattern.tolerance_time_passed = false
        clock.run(function()
            clock.sleep(TOLERANCE_TIME_MS / 1000)
            pattern.tolerance_time_passed = true
        end)
        notify_midi_info(device_id, channel, event_id, 0, value, event)
    elseif pattern and event == "cc" then
        local tolerance_distance = math.abs(pattern.last_value - value) > TOLERANCE_DISTANCE
        if pattern.loop.rec == 0 and tolerance_distance and pattern.tolerance_time_passed then
            pattern.loop:clear()
        end
        pattern.last_value = value
        pattern.loop:watch({
            device_id = device_id,
            channel = channel,
            event_id = event_id,
            value = value,
            midi_msg = copy_midi_msg(midi_msg),
        })
        notify_midi_info(device_id, channel, event_id, pattern.loop.rec, value, event)
    else
        local rec_state = pattern and pattern.loop and pattern.loop.rec or 0
        notify_midi_info(device_id, channel, event_id, rec_state, value, event or string.format("0x%X", event_code))
    end

    norns_midi_event(device_id, midi_msg)
end

function Midididi.init()
    if initialized or _norns.midi.event == on_midi_event then
        return
    end

    norns_midi_event = _norns.midi.event
    _norns.midi.event = on_midi_event
    initialized = true
end

function Midididi.cleanup()
    if initialized and norns_midi_event ~= nil and _norns.midi.event == on_midi_event then
        _norns.midi.event = norns_midi_event
    end

    norns_midi_event = nil
    output_midi_device = nil
    patterns = {}
    initialized = false
end

function Midididi.on_rec_change(callback)
    on_rec_change = callback
end

function Midididi.on_midi_info_change(callback)
    on_midi_info_change = callback
end

function Midididi.set_device(device_id)
    enabled_device_id = device_id
    output_midi_device = device_id ~= nil and midi.connect(device_id) or nil
end

return Midididi
