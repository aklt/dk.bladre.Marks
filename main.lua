--[[ dk.bladre.Marks -- Renoise tool to jump around in a song

Marks makes it possible to use letters as markers of different positions
in the renoise GUI. Positions remembered include:

    * Pattern, track, line and note column
    * Selected instrument
    * Selected device
    * Middle panel view
    * Active upper and lower panel

Marks added will be saved in the song and will be restored when the song is
reopened at a later time.

To use this map "Global:Tools:Marks" to a convenient shortcut to open the dialog.

ALT-D works nice for me.

2012-03-10 v1.0.3 Better naming of marks
2012-03-09 v1.0.2 Nicer GUI, jump to mark while playing
2012-03-09 v1.0.0
--]]

local MARKS_VERSION         = '1.03'
local MARKS_FORMAT_VERSION  = 'dk.bladre.Marks/v1'
local MARKS_INSTRUMENT_NAME = '        _______Marks_______'

local preferences = renoise.Document.create("MarksPreferences") {
    autoclose = false
}


renoise.tool().preferences = preferences

-- {{{1 Serialization of marks
function serializeMark(markTable)
    local result = ''
    local patternPos = nil
    for i = 1, 12 do
        local v = markTable[i]
        if type(v) == 'boolean' then
            if v then
                result = result .. 't'
            else
                result = result .. 'f'
            end
        else
            result = result .. v
        end
    end
    for i = 13, #markTable do
        result = result .. ',' .. markTable[i]
    end
    return result
end

function serializeMarksTable(marksTable)
    local result = MARKS_FORMAT_VERSION
    for markName, markData in pairs(marksTable) do
        result =  result .. "\n" .. markName .. markData
    end
    return result
end

function deserializeMark(markString)
    local result = {}
    for i = 1, 12 do
        local val = markString:sub(i, i)
        if  val == 't' then
            result[i] = true
        elseif val == 'f' then
            result[i] = false
        else
            result[i] = val + 0
        end
    end
    markString = markString:sub(14)
    while #markString > 0 do
        local comma = markString:find(',')
        if comma == nil then
            comma = #markString + 1
        end
        local num = markString:sub(1, comma - 1)
        table.insert(result, num + 0)
        markString = markString:sub(comma + 1)
    end
    return result
end

function deserializeMarksString(marksString)
    local result = {}
    local version = marksString:sub(1, #MARKS_FORMAT_VERSION)
    marksString = marksString:sub(#MARKS_FORMAT_VERSION + 2)
    while #marksString > 0 do
        local bar = marksString:find("\n")
        if bar == nil then
            bar = #marksString + 1
        end
        local markData = marksString:sub(1, bar - 1)
        result[markData:sub(1, 1)] = markData:sub(2)
        marksString = marksString:sub(bar + 1)
    end
    return result
end
-- 1}}}

-- {{{1 Gui
function summarizeMarkContent(markTable)
    local a = renoise.ApplicationWindow
    local result = {}
    local upper = ''
    local lower = ''
    if markTable[2] == a.MIDDLE_FRAME_PATTERN_EDITOR then
        local song = renoise.song()
        local seqIndex = markTable[17]
        local patternName = song.patterns[song.sequencer:pattern(seqIndex)].name
        local trackName = song.tracks[markTable[15]].name
        if patternName and patternName ~= '' then
            patternName = ' ' .. patternName
        else
            patternName = ' ' .. seqIndex - 1
        end
        if trackName and trackName ~= '' then
            trackName = ', ' .. trackName
        else
            trackName = ', ' .. markTable[15]
        end
        table.insert(result, 'Sequence:' .. patternName ..
                    trackName ..
                    ', Line ' .. markTable[18] - 1)
    elseif markTable[2] == a.MIDDLE_FRAME_MIXER then
        local song  = renoise.song()
        local track = song.tracks[markTable[15]]
        local trackName = track.name
        local device = ''
        local deviceName = ''
        if markTable[16] ~= 0 then
            device = track:device(markTable[16])
            if device then
                deviceName = ', ' .. device.name
            end
        end
        if trackName then
            trackName = ' ' .. trackName
        else
            trackName = ' ' .. markTable[15]
        end
        table.insert(result, 'Mixer:' .. trackName .. deviceName)
    elseif markTable[2] == a.MIDDLE_FRAME_KEYZONE_EDITOR then
        local instrument
        local instrumentName = ''
        if markTable[13] ~= 0 then
            instrument = renoise.song().instruments[markTable[13]]
            if instrument then
                instrumentName = ' ' .. instrument.name
            else
                instrumentName = ' ' .. markTable[13]
            end
        end
        table.insert(result, 'Keyzones:' .. instrumentName)
    elseif markTable[2] == a.MIDDLE_FRAME_SAMPLE_EDITOR then
        local instrument
        local sample
        local sampleName = ''
        if markTable[13] ~= 0 then
            instrument = renoise.song().instruments[markTable[13]]
        end
        if instrument and markTable[14] ~= 0 then
            sample = instrument.samples[markTable[14]]
        end
        if sample then
            sampleName = sample.name
        else
            sampleName = markTable[14] - 1
        end
        table.insert(result, 'Sample: ' ..  sampleName)
    end
    if markTable[3] ~= 0 then
        if markTable[3] == a.UPPER_FRAME_DISK_BROWSER then
            upper = 'Disk Browser'
        elseif markTable[3] == a.UPPER_FRAME_TRACK_SCOPES then
            upper = 'Track Scopes'
        elseif markTable[3] == a.UPPER_FRAME_MASTER_SCOPES then
            upper = 'Master Scopes'
        elseif markTable[3] == a.UPPER_FRAME_MASTER_SPECTRUM then
            upper = 'Master Spectrum'
        end
        table.insert(result, '↑ ' .. upper)
    end
    if markTable[1] ~= 0 then
        if markTable[1] == a.LOWER_FRAME_TRACK_DSPS then
            lower = 'DSPs'
        elseif markTable[1] == a.LOWER_FRAME_TRACK_AUTOMATION then
            lower = 'Automation'
        elseif markTable[1] == a.LOWER_FRAME_INSTRUMENT_PROPERTIES then
            lower = 'Instrument'
        elseif markTable[1] == a.LOWER_FRAME_SONG_PROPERTIES then
            lower = 'Song'
        end
        table.insert(result, '↓ ' .. lower)
    end
    return table.concat(result, '   ')
end

function marksInstrumentIndex()
    for i, instrument in ripairs(renoise.song().instruments) do
        if instrument.name == MARKS_INSTRUMENT_NAME then
            return i
        end
    end
    return nil
end

function instrumentsChanged()
    local lastIndex = #renoise.song().instruments
    local marksIndex = marksInstrumentIndex()
    if marksIndex ~= lastIndex then
        renoise.song():swap_instruments_at(marksIndex, lastIndex)
    end
end

function addInstrumentsNotifier()
    local iobs = renoise.song().instruments_observable
    if not iobs:has_notifier(instrumentsChanged) then
        iobs:add_notifier(instrumentsChanged)
    end
end

function removeInstrumentsNotifier()
    local iobs = renoise.song().instruments_observable
    if iobs:has_notifier(instrumentsChanged) then
        iobs:remove_notifier(instrumentsChanged)
    end
end

function legalMark(keyTable)
    if keyTable.character then
        local ch = keyTable.character
        if (ch >=  "a" and ch <= "z")  then
            return ch, false
        elseif (ch >= "A" and ch <= "Z") then
            return ch:lower(), true
        end
    end
    return nil
end

function buildRow(ref, key, keyMarkTable)
    local vb = ref.vb
    local markSummary = ''
    if keyMarkTable then
        markSummary = summarizeMarkContent(keyMarkTable)
    end
    local row
    row = vb:row {
            spacing = 4,
            vb:text {
                text = key,
                font = "big",
                align = "center"
            },
        }
    local btnJump = vb:button {
        id = key,
        text = "jump",
        color = {100, 100, 100},
        active = keyMarkTable ~= nil,
        notifier = function ()
            jumpToMark(key)
            if preferences.autoclose.value then
                ref.dialog:close()
            end
        end
    }
    local btnAdd = vb:button {
        text = "add",
        color = {200, 200, 200},
        notifier = function ()
            vb.views['text' .. key].text = addMark(key)
            vb.views[key].active = true
            if preferences.autoclose.value then
                ref.dialog:close()
            end
        end
    }
    local text = vb:text {
        id = 'text' .. key,
        text = markSummary
    }
    row:add_child(btnAdd)
    row:add_child(btnJump)
    row:add_child(text)
    return row
end

function showMarksDialog()
    local vb = renoise.ViewBuilder()
    local ref = {['vb'] = vb}
    local marksTable = loadMarks() or {}
    local margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN
    local spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING
    local content = vb:column {
        id = 'content',
        margin = margin,
        spacing = spacing
    }

    for byte = ("a"):byte(1), ("z"):byte(1) do
        local key = string.char(byte)
        content:add_child(buildRow(ref, key, marksTable[key]))
    end

    local settings = vb:row {
        margin = margin,
        spacing = spacing,
        style = 'group',
        width = "100%",
        vb:column {
            margin = margin,
            spacing = spacing,
            vb:text {
                text = "Click buttons to add or jump to marks.\n" ..
                       "Type a-z to jump to a mark or A-Z (holding shift)\n" ..
                       "to add a mark.",
                align = 'left'
            }
        },
        vb:column {
            margin = margin,
            spacing = spacing,
            vb:button {
                text = "Remove all Marks",
                notifier = function ()
                    removeInstrumentsNotifier()
                    local index = marksInstrumentIndex()
                    if index then
                        renoise.song():delete_instrument_at(index)
                    end
                    for byte = ('a'):byte(1), ('z'):byte(1) do
                        local key = string.char(byte)
                        vb.views['text' .. key].text = ''
                        vb.views[key].active = false
                    end
                end
            },
            vb:row {
                margin = margin,
                spacing = spacing,
                vb:checkbox {
                    bind = preferences.autoclose,
                },
                vb:text {
                    text = 'Auto close'
                }
            }
        }
    }
    local dialogContent = vb:column {
        margin = margin,
        spacing = spacing,
        style = 'border',
        width = 380,
        content,
        settings
    }
    ref.dialog = renoise.app():show_custom_dialog("Marks v" .. MARKS_VERSION, dialogContent, function (dialog, keyObj)
        if keyObj.name == 'esc' then
            dialog:close()
        else
            local key, isUpper = legalMark(keyObj)
            if key then
                local ok = false
                if isUpper and keyObj.modifiers == 'shift' then
                    vb.views['text' .. key].text = addMark(key)
                    vb.views[key].active = true
                    ok = true
                else
                    ok = jumpToMark(key)
                end
                if ok and preferences.autoclose.value then
                    dialog:close()
                end
            end
        end
    end)
end
-- 1}}}

-- {{{1 get And jump to a mark
function getMark()
    local window = renoise.app().window
    local song   = renoise.song()
    local note   = song.selected_note_column_index
    local effect = song.selected_effect_column_index
    -- TODO alias*_index?
    if note == nil then
        note = 0
    end
    if effect == nil then
        effect = 0
    end
    return {window.active_lower_frame,
            window.active_middle_frame,
            window.active_upper_frame,
            window.disk_browser_is_expanded,
            window.lock_keyboard_focus,
            window.lower_frame_is_visible,
            window.mixer_fader_type,
            window.mixer_view_post_fx,
            window.pattern_advanced_edit_is_visible,
            window.pattern_matrix_is_visible,
            window.sample_record_dialog_is_visible,
            window.upper_frame_is_visible,
            song.selected_instrument_index,
            song.selected_sample_index,
            song.selected_track_index,
            song.selected_device_index,
            song.selected_sequence_index,
            song.selected_line_index,
            note,
            effect}
end

function jumpToMark(markName)
    local mark   = loadMarks(markName)
    if not mark then
        return nil
    end
    local window = renoise.app().window
    local song   = renoise.song()
    if mark[1] ~= 0 then
        window.active_lower_frame            = mark[1]
    end
    window.active_middle_frame               = mark[2]
    if mark[3] ~= 0 then
        window.active_upper_frame            = mark[3]
    end
    window.disk_browser_is_expanded          = mark[4]
    window.lock_keyboard_focus               = mark[5]
    window.lower_frame_is_visible            = mark[6]
    window.mixer_fader_type                  = mark[7]
    window.mixer_view_post_fx                = mark[8]
    window.pattern_advanced_edit_is_visible  = mark[9]
    window.pattern_matrix_is_visible         = mark[10]
    window.sample_record_dialog_is_visible   = mark[11]
    window.upper_frame_is_visible            = mark[12]
    song.selected_instrument_index           = mark[13]
    song.selected_sample_index               = mark[14]
    song.selected_track_index                = mark[15]
    song.selected_device_index               = mark[16]
    song.selected_sequence_index             = mark[17]
    song.selected_line_index                 = mark[18]
    song.transport.playback_pos              = renoise.SongPos(mark[17], mark[18])
    local note, effect = mark[19], mark[20]
    if note ~= 0 then
        song.selected_note_column_index = note
    end
    if effect ~= 0 then
        song.selected_effect_column_index = effect
    end
    renoise.app():show_status('Jump to ' .. markName:upper() .. ' : ' .. summarizeMarkContent(mark))
    return mark
end
-- 1}}}

-- {{{1 Saving and loading marks in an instrument
function getMarksInstrumentSample()
    for i, instrument in ripairs(renoise.song().instruments) do
        if instrument.name == MARKS_INSTRUMENT_NAME then
            return instrument.samples[1]
        end
    end
    local index = #renoise.song().instruments + 1
    renoise.song():insert_instrument_at(index)
    local instrument = renoise.song().instruments[index]
    instrument.name = MARKS_INSTRUMENT_NAME
    addInstrumentsNotifier()
    return instrument.samples[1]
end

function loadMarks(markName, dontDeserializeMark)
    local str = getMarksInstrumentSample().name
    if #str == 0 then
        return nil
    end
    local marksTable = deserializeMarksString(str)
    if dontDeserializeMark then
        return marksTable
    end
    if markName then
        local markString = marksTable[markName]
        if not markString then
            return nil
        end
        return deserializeMark(markString)
    end
    local deserializedMarksTable = {}
    for k, v in pairs(marksTable) do
        deserializedMarksTable[k] = deserializeMark(v)
    end
    return deserializedMarksTable
end

function addMark(markName)
    local data = getMark()
    local markData = serializeMark(data)
    local marks = loadMarks(markName, true) or {}
    marks[markName] = markData
    local sample = getMarksInstrumentSample()
    sample.name = serializeMarksTable(marks)
    local summary = summarizeMarkContent(data)
    renoise.app():show_status('Add mark ' .. markName:upper() .. ' : ' .. summary)
    return summary
end
-- 1}}}

-- {{{1 Setup
function MarksShow()
    showMarksDialog()
end

renoise.tool():add_keybinding {
    name = "Global:Tools:Marks",
    invoke = MarksShow
}

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:Marks:Show",
  invoke = MarksShow
}
-- 1}}}
