local Menu = {}

local mod = require("core/mods")

local data_dir = _path.data .. mod.this_name
local data_file = data_dir .. "/mod.state"

-- default state
local state = {
    selected_device = 1,
}

local midi_info = {
    rec_state = 0,
    device_id = nil,
    channel = nil,
    event_id = nil,
    value = nil,
    event_name = nil,
}

local menu_active = false

local function short_name(name)
    if name == nil or name == "" then
        return "none"
    end
    return string.len(name) <= 6 and name or util.acronym(name)
end

function Menu.key(n, z)
    if n == 2 and z == 1 then
        mod.menu.exit()
    end
end

function Menu.enc(n, d)
    if n == 3 then
        local selected_device = util.clamp(state.selected_device + d, 1, 16)
        state.selected_device = selected_device
        Menu.on_device_change(selected_device)
    end
    mod.menu.redraw()
end

function Menu.redraw()
    screen.clear()

    local vport = midi.vports[state.selected_device]
    local device_name = short_name(vport and vport.name)
    local status = midi_info.rec_state == 1 and "recording" or "idle"
    local device_id_text = midi_info.device_id ~= nil and tostring(midi_info.device_id) or "--"
    local channel_text = midi_info.channel ~= nil and tostring(midi_info.channel) or "--"
    local event_id_text = midi_info.event_id ~= nil and tostring(midi_info.event_id) or "--"
    local value_text = midi_info.value ~= nil and tostring(midi_info.value) or "--"
    local event_name = midi_info.event_name or "--"

    screen.font_face(1)
    screen.font_size(8)
    screen.level(15)

    screen.move(0, 10)
    screen.text("in")
    screen.move(120, 10)
    screen.text_right(string.format("%d %s", state.selected_device, device_name))

    screen.move(0, 22)
    screen.text("st")
    screen.move(120, 22)
    screen.text_right(status)

    screen.move(0, 34)
    screen.text("d/ch")
    screen.move(120, 34)
    screen.text_right(string.format("%s/%s", device_id_text, channel_text))

    screen.move(0, 46)
    screen.text("evt")
    screen.move(120, 46)
    screen.text_right(string.format("%s %s", event_name, event_id_text))

    screen.move(0, 58)
    screen.text("val")
    screen.move(120, 58)
    screen.text_right(value_text)

    screen.update()
end

function Menu.init()
    menu_active = true
    if util.file_exists(data_file) then
        local saved_state = tab.load(data_file)
        if saved_state ~= nil and saved_state.selected_device ~= nil then
            state.selected_device = saved_state.selected_device
        end
    else
        util.make_dir(data_dir)
    end
end

function Menu.deinit()
    menu_active = false
    tab.save(state, data_file)
end

function Menu.set_midi_info(device_id, channel, event_id, rec_state, value, event)
    local event_labels = {
        note_on = "on",
        note_off = "off",
        cc = "cc",
    }

    midi_info.device_id = device_id
    midi_info.channel = channel
    midi_info.event_id = event_id
    midi_info.rec_state = rec_state or 0
    midi_info.value = value
    midi_info.event_name = event_labels[event] or event or "--"

    if menu_active then
        mod.menu.redraw()
    end
end

function Menu.on_device_change(_) end

return Menu
