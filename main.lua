
MARKS_VERSION         = '1.2.0'
MARKS_FORMAT_VERSION  = 'dk.bladre.Marks/v3'

-- TODO Gui update
local preferences = renoise.Document.create("MarksPreferences") {
    movecursor    = 3,
    jumpaccuracy  = 1,
    miniwindow = false
}

local OnOffLabels         = {'on', 'off'}
-- TODO Better summary
-- TODO Show mark jumps in minified view
-- TODO Bug: Jumping is not quite right
-- TODO If visible, close the dialog with numlock
-- TODO view, pattern, cursor; selection
-- TODO Numpad + to update current view
-- TODO Cursor movements, selection
--
local JumpAccuracyLabels  = {'view', 'pattern', 'cursor'}
local colorDefault        = {200, 200, 220}
local colorMark           = {200, 220, 200}
local colorJump           = {120, 120, 120}
local colorNone           = {100, 100, 100}

local SongMarks      = {}
local SongMarksOrder = {}
local DefaultMarks   = {}
local DefaultMarksFileName = renoise.tool().bundle_path .. 'defaults.xml'
local REF = {}

-- http://stackoverflow.com/questions/1410862/concatenation-of-tables-in-lua
local function array_concat(...)
    local t = {}
    for n = 1,select("#",...) do
        local arg = select(n,...)
        if type(arg)=="table" then
            for _,v in ipairs(arg) do
                t[#t+1] = v
            end
        else
            t[#t+1] = arg
        end
    end
    return t
end

local function renoiseView()
    return REF.vb.views
end

-- Format: [1-16]:chars [17-37]:commas [38-]:chars
local function renoiseMarkData()
    local window = renoise.app().window
    local song = renoise.song()
    local selected_track_index = song.selected_track_index
    local selection = {0, 0, 0, 0, 0, 0}
    local sa = song.selection_in_pattern
    -- TODO selection in phrase
    -- song.selection_in_phrase
    local thisTrack = song.tracks[selected_track_index]
    local view = {
      window.fullscreen,                             --  01
      window.instrument_box_is_visible,              --  02
      window.instrument_editor_is_detached,          --  03
      window.mixer_view_is_detached,                 --  04
      window.active_lower_frame,                     --  05
      window.active_middle_frame,                    --  06
      window.active_upper_frame,                     --  07
      window.disk_browser_is_visible,                --  08
      window.lock_keyboard_focus,                    --  09
      window.lower_frame_is_visible,                 --  10
      window.mixer_fader_type,                       --  11
      window.mixer_view_post_fx,                     --  12
      window.pattern_advanced_edit_is_visible,       --  13
      window.pattern_matrix_is_visible,              --  14
      window.sample_record_dialog_is_visible,        --  15
      window.upper_frame_is_visible                  --  16
    }
    local indexes = {
    -- TODO Remember these too
        song.selected_phrase_index,                  --  17
        song.selected_sample_device_chain_index,     --  18
        song.selected_sample_device_index,           --  19
        song.selected_sample_modulation_set_index,   --  20
        song.selected_track_device_index,            --  21
        song.selected_track_index,                   --  22
        song.selected_instrument_index,              --  23
        song.selected_sample_index,                  --  24
        selected_track_index,                        --  25
        song.selected_device_index,                  --  26
        -- TODO Read only
        song.selected_pattern_index,                 --  27
        song.selected_sequence_index,                --  28
        song.selected_line_index,                    --  29
        song.selected_note_column_index or 0,        --  30
        song.selected_effect_column_index or 0       --  31
    }
    if sa then
        selection[1] = sa.end_column                 -- 32
        selection[2] = sa.end_line                   -- 33
        selection[3] = sa.end_track                  -- 34
        selection[4] = sa.start_column               -- 35
        selection[5] = sa.start_line                 -- 36
        selection[6] = sa.start_track                -- 37
    end
    local trackView = {
        -- New
        thisTrack.sample_effects_column_visible,     -- 38
        thisTrack.solo_state,                        -- 39
        thisTrack.visible_effect_columns,            -- 40
        thisTrack.visible_note_columns,              -- 41
        thisTrack.volume_column_visible,             -- 42
        thisTrack.panning_column_visible,            -- 43
        thisTrack.delay_column_visible}              -- 44
    -- TODO Collapse and track type
    local collapse = {}
    local i = 1
    while i < #song.tracks do
        local t = song.tracks[i]
        table.insert(collapse, t.collapsed)
        i = i + 1
    end
    return array_concat(view, indexes, selection, trackView, collapse)
end

local function stringifyBoolsAndSingleNumbers(marksTable, first, last)
    local result = ''
    for i = first, last do
        local value = marksTable[i]
        local valueT = type(value)
        if valueT == 'number' or valueT == 'string' then
            result = result .. tostring(value)
        elseif  value then
            result = result .. 't'
        else
            result = result .. 'f'
        end
    end
    return result
end

local function stringifyMark(marksTable)
    local result = stringifyBoolsAndSingleNumbers(marksTable, 1, 16)
    for i = 17, 37 do
        result = result .. ',' .. marksTable[i]
    end
    local last = #marksTable
    if last > 37 then
        result = result .. ',' .. stringifyBoolsAndSingleNumbers(marksTable, 38, last)
    end
    --print('Stringify', result)
    return result
end

local function stringifyMarksTable(marksTable, order)
    local result = MARKS_FORMAT_VERSION .. "\n"
    if order then
        for _, markName in ipairs(order) do
            result = result .. markName .. stringifyMark(marksTable[markName]) .. "\n"
        end
    else
        for markName, markData in pairs(marksTable) do
            result =  result .. markName .. stringifyMark(markData) .. "\n"
        end
    end
    return result
end


local function saveMarks()
    print('Save ' .. stringifyMarksTable(SongMarks, SongMarksOrder))
    renoise.song().tool_data = stringifyMarksTable(SongMarks)
end

local function statusMsg(msg)
    renoise.app():show_status('Marks: ' .. msg)
end

local function summarizeMarkContent(markTable)
    if not markTable then
        return nil
    end
    print('---- Summarize')
    rprint(markTable)
    local a = renoise.ApplicationWindow
    local result = {}
    local upper = ''
    local lower = ''
    if markTable[2] == a.MIDDLE_FRAME_PATTERN_EDITOR then
        local song = renoise.song()
        local sequenceName  = markTable[18] .. ''
        local trackName  = markTable[15] .. ''
        if markTable[15] > 0 and markTable[15] <= #song.tracks then
            trackName = song.tracks[markTable[15]].name
        end
        local patternIdx = song.sequencer.pattern_sequence[markTable[18]]
        if patternIdx and markTable[18] <= #song.sequencer.pattern_sequence then
            if patternIdx <= #song.patterns then
                local seqName = song.patterns[patternIdx].name
                if seqName:gsub("%s+", ""):len() > 0 then
                    sequenceName = sequenceName .. ' ' .. seqName
                end
            end
        end
        table.insert(result, 'Sequence ' .. sequenceName:match("^%s*(.-)%s*$") .. ', ' ..
                    trackName:match("^%s*(.-)%s*$") ..
                    ', Line ' .. markTable[19])
    elseif markTable[2] == a.MIDDLE_FRAME_MIXER then
        local song  = renoise.song()
        local track = song.tracks[markTable[15]]
        local trackName = track.name
        local device = ''
        local deviceName = ''
        if markTable[16] > 0 and track and markTable[16] <= #song.tracks[markTable[15]].devices then
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
        table.insert(result, 'Mixer ' .. trackName:match("^%s*(.-)%s*$") .. deviceName:match("^%s*(.-)%s*$"))
    elseif markTable[2] == a.MIDDLE_FRAME_INSTRUMENT_SAMPLE_KEYZONES then
        local instrument
        local instrumentName = ''
        local song = renoise.song()
        if markTable[13] > 0  and markTable[13] <= #song.instruments then
            instrument = song.instruments[markTable[13]]
            if instrument then
                instrumentName = ' ' .. instrument.name
            else
                instrumentName = ' ' .. markTable[13]
            end
        end
        table.insert(result, 'Keyzones ' .. instrumentName:match("^%s*(.-)%s*$"))
    elseif markTable[2] == a.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR then
        local instrument = 'Unknown instrument'
        local sampleName = 'Unknown sample'
        local song = renoise.song()
        if markTable[13] > 0 and markTable[13] <= #song.instruments then
            instrument = song.instruments[markTable[13]]
        end
        if instrument and markTable[14] ~= 0 and markTable[14] <= #instrument.samples then
            sampleName = instrument.samples[markTable[14]].name
        else
            sampleName = markTable[14] - 1
        end
        table.insert(result, 'Sample ' ..  sampleName:match("^%s*(.-)%s*$"))
    end
    if markTable[12] and markTable[3] ~= 0 then
        if markTable[3] == a.UPPER_FRAME_TRACK_SCOPES then
            upper = ' Track Scopes'
        elseif markTable[3] == a.UPPER_FRAME_MASTER_SPECTRUM then
            upper = ' Master Spectrum'
        end
        table.insert(result, upper)
    end
    if markTable[6] and markTable[1] ~= 0 then
        if markTable[1] == a.LOWER_FRAME_TRACK_DSPS then
            lower = ' DSPs'
        elseif markTable[1] == a.LOWER_FRAME_TRACK_AUTOMATION then
            lower = ' Automation'
        end
        table.insert(result, lower)
    end
    local viewChar = "□"
    if markTable[12] and markTable[6] then
            viewChar = "■"
    elseif markTable[6] then
            viewChar = "⬓ "
    elseif markTable[12] then
           viewChar = "⬒ "
    end
    return viewChar .. ' ' .. table.concat(result, '    •   ')
end


local function jumpToMark(markName)
    local mark = SongMarks[markName]
    if not mark then
        return nil
    end
    local window = renoise.app().window
    local song   = renoise.song()
    -- window.fullscreen                       = mark[1]
    window.instrument_box_is_visible        = mark[2]
    window.instrument_editor_is_detached    = mark[3]
    window.mixer_view_is_detached           = mark[4]

    if mark[5] ~= 0 then
        window.active_lower_frame            = mark[5]
    end
    window.active_middle_frame               = mark[6]
    if mark[7] ~= 0 then
        window.active_upper_frame            = mark[7]
    end
    window.disk_browser_is_visible           = mark[8]
    window.lock_keyboard_focus               = mark[9]
    window.lower_frame_is_visible            = mark[10]
    window.mixer_fader_type                  = mark[11]
    window.mixer_view_post_fx                = mark[12]
    window.pattern_advanced_edit_is_visible  = mark[13]
    window.pattern_matrix_is_visible         = mark[14]
    window.sample_record_dialog_is_visible   = mark[15]
    window.upper_frame_is_visible            = mark[16]
    -- TODO Collect errors
    song.selected_phrase_index                = mark[17]
    song.selected_sample_device_chain_index   = mark[18]
    song.selected_sample_device_index         = mark[19]
    song.selected_sample_modulation_set_index = mark[20]
    song.selected_track_device_index          = mark[21]
    song.selected_track_index                 = mark[22]

    if preferences.movecursor.value > 1 then
        if mark[23] <= #song.instruments then
            song.selected_instrument_index       = mark[23]
            if mark[24] > 0 and mark[24] <= #song.instruments[mark[23]].samples then
               song.selected_sample_index       = mark[24]
            end
        end
        if mark[28] > 0 and mark[28] <= #song.sequencer.pattern_sequence then
            song.selected_sequence_index     = mark[28]
            if preferences.movecursor.value > 2 and mark[27] <= #song.patterns and mark[29] <= song.patterns[mark[27]].number_of_lines then
                song.transport.playback_pos  = renoise.SongPos(mark[28], mark[29])
            end
        end

        if mark[25] <= #song.tracks then
            local trackIdx = mark[25]
            song.selected_track_index        = trackIdx
            if mark[26] <= #song.tracks[trackIdx].devices then
                song.selected_device_index       = mark[26]
            end
            local note                           = mark[30]
            local effect                         = mark[31]
            if note > 0 then
                song.selected_note_column_index = note
            end
            if effect > 0 then
                song.selected_effect_column_index = effect
            end
        end
        if mark[32] > 0 then
            song.selection_in_pattern = {
                end_column   = mark[32],
                end_line     = mark[33],
                end_track    = mark[34],
                start_column = mark[35],
                start_line   = mark[36],
                start_track  = mark[37]}
        end
        -- TODO Check for support of columns
        local track = song.tracks[mark[25]]
        track.sample_effects_column_visible = mark[38]
        track.solo_state                    = mark[39]
        track.visible_effect_columns        = mark[40]
        track.visible_note_columns          = mark[41]
        track.volume_column_visible         = mark[42]
        track.panning_column_visible        = mark[43]
        track.delay_column_visible          = mark[44]
    end
    if preferences.movecursor.value > 0 then
        local i = 1
        local last = #song.tracks
        local t = renoise.song().tracks
        while i < last do
            if t then
                 local value = mark[44 + i]
                 if value then
                     value = not(not(value))
                 end
                 if t[i].type == renoise.Track.TRACK_TYPE_GROUP then
                     t[i].group_collapsed = value
                 else
                     t[i].collapsed = value
                 end
            end
            i = i + 1
        end
    end
    -- updateMarksOrder(markName)
    saveMarks()
    statusMsg('jump  ' .. markName:upper() .. '  ' .. summarizeMarkContent(mark))
    -- updateMarksOrder(markName)
    return mark
end

local function _iterSeparator(separator, string, amount)
    local index = 0
    if not amount then
        amount = 2147483647
    end
    return function()
        if #string > 0 and index < amount then
            local endline = string:find(separator)
            if not endline then
            endline = #string + 1
        end
        local data = string:sub(1, endline - 1)
        string = string:sub(endline + 1)
        index = index + 1
        return index, data
        end
        return nil
    end
end

local function _iterChars(amount, string)
    local count = 0
    return function ()
        count = count + 1
        if count <= amount then
            local result = string:sub(count, count)
            if #result > 0 then
                if result:match('^%d$') then
                    result = tonumber(result)
                    return count, result
                elseif result == 't' then
                    return count, true
                elseif result == 'f' then
                    return count, false
                end
                return count, result
            end
        end
        return nil
    end
end

local function _iterCSV(amount, string)
    if not amount then
        amount = 2147483647
    end
    local count = 0
    return function ()
        local result1
        if #string > 0 and count < amount then
            local comma = string:find(',')
            if comma == nil then
                comma = #string + 1
            end
            local value = string:sub(1, comma - 1)
            if not value then
                return nil
            end
            count = count + 1
            if value:match('^%a') then
                result0 = value:sub(1, 1)
                result1 = value:sub(2)
            else
                result0 = count
                result1 = value + 0
            end
            string = string:sub(comma + 1)
            return result0, result1
        end
        return nil
    end
end

local function readMarksString(marksString)
    if not marksString then
        return {}
    end
    local result = {}
    local order = {}
    local string = string.sub(marksString, #MARKS_FORMAT_VERSION + 2)
    local count =- 0
    for i, line in _iterSeparator("\n", string) do
        print('LINE 1: ' .. line)
        local markData = {}
        local markName = line:sub(1, 1)
        table.insert(order, markName)
        line = line:sub(2)
        print('LINE 2: ' .. line)
        for i, value in _iterChars(16, line) do
            table.insert(markData, value)
        end
        line = line:sub(18)
        local length = 0
        print('LINE 3: ' .. line)
        for i, value in _iterSeparator(',', line, 21) do
            table.insert(markData, tonumber(value))
            if type(value) == type(1) then
                value = tostring(value)
            end
            length = length + value:len() + 1
        end
        line = line:sub(length + 1)
        local last  = 1
        print('LINE 4: ' .. line)
        for i, value in _iterChars(#renoise.song().tracks, line) do
            table.insert(markData, value)
            last = last + 1
        end
        last = last
        local copyTo = line:len()
        while last <= copyTo do
            table.insert(markData, line:sub(last, last))
            last = last + 1
        end
        result[markName] = markData
    end
    return result, order
end

local function loadMarks()
    local songData = renoise.song().tool_data or ''
    --rprint('songData', songData)
    if songData then
        SongMarks, SongMarksOrder = readMarksString(songData)
    end
    -- Don't load defaults
    --if io.exists(DefaultMarksFileName) then
        --local doc = renoise.Document.create('MarksPreferenceDefaults') {
            --data = ''
        --}
        --local ok, err = doc:load_from(DefaultMarksFileName)
        --if not ok then
            --print('Got error loading defaults.xml', err)
        --else
            --DefaultMarks = readMarksString(doc:property('data').value)
        --end
    --end
    print('Loaded')
    print(stringifyMarksTable(SongMarks))
end

local function getMarksMiniTitle()
    if not SongMarksOrder[1] then
        return ''
    end
    local result = SongMarksOrder[1]:upper()
    for i, char in ipairs(SongMarksOrder) do
        if i > 1 then
            result = result .. ' ' .. char
        end
    end
    return result
end

local function updateMarksOrder(markName)
    oprint(SongMarksOrder)
    for i, v in ipairs(SongMarksOrder) do
        if v == markName then
            table.remove(SongMarksOrder, i)
            break
        end
    end
    table.insert(SongMarksOrder, 1, markName)
end

local function addMark(markName, default)
    print('addMark', markName);
    SongMarks[markName] = renoiseMarkData()
    --if default then
        --DefaultMarks[markName] = SongMarks[markName]
        --local doc = renoise.Document.create('MarksPreferenceDefaults') {
            --data = stringifyMarksTable(DefaultMarks)
        --}
        --doc:save_as(DefaultMarksFileName)
        --print('saved')
    --end
    updateMarksOrder(markName)
    --print('Addmark', markName)
end

local function removeMark(markName)
    SongMarks[markName] = nil
    for i, val in ipairs(SongMarksOrder) do
        if val == markName then
            table.remove(SongMarksOrder, i)
            break
        end
    end
end


-- {{{1 Handling keys
local function keyUpDown(dir)
    return function (key)
        local song  = renoise.song()
        local line  = song.selected_line_index
        local pos   = song.transport.edit_pos
        local lines = song:pattern(song.sequencer:pattern(pos.sequence)).number_of_lines
        line = line + dir
        if line < 1 then
            -- TODO Get the proper length
            line = lines
        end
        if line > lines then
            line = 1
        end
        song.transport.edit_pos = renoise.SongPos(pos.sequence, line)
    end
end

local function keyLeftRight(dir)
    return function (key)
        local song = renoise.song()
        local effect = song.selected_effect_column_index
        local note = song.selected_note_column_index
        local newNote = note + dir
        if newNote > 0 then
            if newNote <= song.selected_track.visible_note_columns then
                song.selected_note_column_index = newNote
            else
                print "Next track"
            end
        elseif effect ~= 0 then
            song.selected_effect_column_index = effect + dir
        end
        print(effect, note)
    end
end

local forwardKeysToRenoiseName = {
    -- TODO Allow selection
    up    = keyUpDown(-1),
    down  = keyUpDown(1),
    left  = keyLeftRight(-1),
    right = keyLeftRight(1),

    space = function (key)
        local trans = renoise.song().transport
        if trans.playing then
            trans:stop()
        else
            local mode = renoise.Transport.PLAYMODE_RESTART_PATTERN
            if key.modifiers == 'shift' then
                mode = renoise.Transport.PLAYMODE_CONTINUE_PATTERN
            end
            trans:start(mode)
        end
    end
}

local function handleRenoiseKey(dialog, views, key)
    if key.name == 'esc' then
        dialog:close()
        return true
    end
    local fun = forwardKeysToRenoiseName[key.name]
    if fun then
        fun(key)
        return true
    end
    return false
end

local function handleNumpadKey(dialog, views, key)
    local numpadKey = string.match(key.name, "^numpad numpad(%d)$")
    if numpadKey then
        local win = renoise.app().window
        if numpadKey == '1' then
            local val = win.active_lower_frame - 1
            if val <= 0 then
                val = 4
            end
            win.active_lower_frame = val
            return true
        elseif numpadKey == '2' then
            win.lower_frame_is_visible = not win.lower_frame_is_visible
            return true
        elseif numpadKey == '3' then
            local val = win.active_lower_frame + 1
            if val >= 5 then
                val = 1
            end
            win.active_lower_frame = val
            return true
        elseif numpadKey == '4' then
            local val = win.active_middle_frame - 1
            if val <= 0 then
                val = 4
            end
            win.active_middle_frame = val
            return true
        elseif numpadKey == '5' then
            jumpToMark(SongMarksOrder[1])
            return true
        elseif numpadKey == '6' then
            local val = win.active_middle_frame + 1
            if val >= 5 then
                val = 1
            end
            win.active_middle_frame = val
            return true
        elseif numpadKey == '7' then
            local val = win.active_upper_frame - 1
            if val <= 0 then
                val = 4
            end
            win.active_upper_frame = val
            return true
        elseif numpadKey == '8' then
            win.upper_frame_is_visible = not win.upper_frame_is_visible
            return true
        elseif numpadKey == '9' then
            local val = win.active_upper_frame + 1
            if val >= 5 then
                val = 1
            end
            win.active_upper_frame = val
            return true
        elseif numpadKey == '*' then
            preferences.movecursor = preferences.movecursor + 1 % 3
        end
    end
    return false
end

local function handleAZ(dialog, views, key)
    local char = key.character
    if char then
        local byte = char:byte(1)
        if byte >= ('A'):byte(1) and byte <= ('Z'):byte(1) and key.modifiers == 'shift' then
            local mark = char:lower()
            addMark(mark)
            saveMarks()
            if preferences.miniwindow.value then
                REF.dialog:close()
                showMarksDialog()
            else
                updateButtons(REF.vb.views, mark, DefaultMarks[mark], SongMarks[mark])
            end
            return true
        elseif byte >= ('a'):byte(1) and byte <= ('z'):byte(1) then
            jumpToMark(char)
            return true
        end
    end
    return false
end

-- 1}}}

local function updateButtons(views, mark, default, song)
    if views then
        if default or song then
            local summary = summarizeMarkContent(default or song)
            views['jump_' .. mark].active = true
            views['text_' .. mark].text = summary
--             if default then
--                 views['default_' .. mark].color = colorDefault
--             else
--                 views['default_' .. mark].color = colorNone
--             end
            if song then
                views['song_' .. mark].color = colorMark
            else
                views['song_' .. mark].color = colorNone
            end
        else
            views['text_' .. mark].text = ''
            views['jump_' .. mark].active = false
            views['song_' .. mark].color = colorNone
            --views['default_' .. mark].color = colorNone
        end
    end
end

local function actionJump(mark)
    if SongMarks[mark] then
        removeMark(mark)
    else
        addMark(mark)
    end
    updateButtons(REF.vb.views, mark, DefaultMarks[mark], SongMarks[mark])
end

local function actionDefault(mark)
    if DefaultMarks[mark] then
        DefaultMarks[mark] = nil
    else
        addMark(mark, true)
    end
    updateButtons(REF.vb.views, mark, DefaultMarks[mark], SongMarks[mark])
end

local function actionHandler(ref, action, mark)
    if action == 'jump' then
        return function ()
            jumpToMark(mark)
        end
    else
        print('Unknown action', action, mark)
    end
end

local function buildRow(ref, mark, default, song)
    local colorB1 = colorDefault
    local colorB2 = colorMark
    local colorB3 = colorJump
    if not default then
        colorB1 = colorNone
    end
    if not song then
        colorB2 = colorNone
    end
    local markValue = default or song
    local jumpEnabled = false
    if markValue then
        jumpEnabled = true
    end
    local vb = REF.vb
    local row = vb:row {
        vb:text {
            text = mark:upper(),
            id = 'mark' .. mark,
            align = 'center',
            font = 'big'
        },
        vb:button {
            text = "✔",
            id = 'song_' .. mark,
            color = colorB2,
            notifier = function ()
                if SongMarks[mark] then
                    removeMark(mark)
                else
                    addMark(mark)
                end
                updateButtons(REF.vb.views, mark, DefaultMarks[mark], SongMarks[mark])
                saveMarks()
            end
        },
        vb:button {
            id = 'jump_' .. mark,
            text = 'jump',
            color = colorB3,
            active = jumpEnabled,
            notifier = actionHandler(REF, 'jump', mark)
        },
        vb:text {
            id = 'text_' .. mark,
            text = summarizeMarkContent(default or song),
            font = 'normal'
        }
    }
    return row
end

local function showMarksDialog()
    if REF.dialog and REF.dialog.visible then
        REF.dialog:close()
    end
    loadMarks()
    print('--loaded--')
    local vb = renoise.ViewBuilder()
    REF = {['vb'] = vb}
    local margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN
    local spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING
    local title
    local content
    local dialogContent
    if preferences.miniwindow.value then
        title = getMarksMiniTitle()  .. '  - Unfolds -'
        dialogContent = vb:column { }
    else
        title = "Marks v" .. MARKS_VERSION
        content = vb:column {
            id = 'content',
            margin = margin,
            spacing = spacing
        }
        for char = ('a'):byte(1), ('z'):byte(1) do
            local mark = string.char(char)
            content:add_child(buildRow(REF, mark, DefaultMarks[mark], SongMarks[mark]))
        end
        local settings = vb:horizontal_aligner {
            mode = 'distribute',
            vb:row {
                spacing = spacing,
                margin = margin,
                style = 'invisible',
                vb:column {
                    margin = margin,
                    spacing = spacing,
                    style = 'invisible',
                    vb:text {
                        text = "a-z jumps to a mark, A-Z toggles marks\n" ..
                        "Numpad * Sets Jump Granularity\n" ..
                        "Numpad 5 jumps to last mark,\n  other Numpad numbers change view\n",
                        align = 'left'
                    }
                },
                vb:column {
                    margin = margin,
                    spacing = spacing,
                    vb:row {
                        vb:text {
                            text = "Jump Granularity",
                            align = 'center'
                        }
                    },
                    vb:row {
                        vb:switch {
                            id = 'jump',
                            items = JumpAccuracyLabels,
                            width = 155,
                            bind = preferences.movecursor
                        }
                    }
                }
            }
        }
        dialogContent = vb:column {
            margin = margin,
            spacing = spacing,
            style = 'border',
            width = 464,
            content,
            vb:row {
                style = 'panel',
                width = "100%",
                settings
            }
        }
    end
    local jump = vb.views.jump
    if jump then
        jump.value = preferences.movecursor.value
    end
    REF.dialog = renoise.app():show_custom_dialog(title, dialogContent, function (dialog, key)
        local char = key.character
        if char == '-' then
            preferences.miniwindow.value = not preferences.miniwindow.value
            dialog:close()
            showMarksDialog()
        elseif char == '+' then
            local view = renoiseView()
            for i, v in ipairs(view) do
                SongMarks[SongMarksOrder[1]][i] = v
            end
        elseif handleAZ(dialog, REF.vb.views, key) then
        elseif handleNumpadKey(dialog, REF.vb.views, key) then
        elseif handleRenoiseKey(dialog, REF.vb.views, key) then
        else
            rprint(key)
        end
    end)
end

renoise.tool():add_keybinding {
    name = "Global:Tools:Marks",
    invoke = showMarksDialog
}

renoise.tool():add_menu_entry {
    name = "Main Menu:Tools:Marks",
    invoke = showMarksDialog
}

_AUTO_RELOAD_DEBUG = function()
  -- do tests like showing a dialog, prompts whatever, or simply do nothing
  print("XX Reload")
  local debug = require('remdebug.engine')
  print('---- remdebug,engine')
  rprint(debug)
  print('---- renoise.app()')
  oprint(renoise.app())
  print('---- renoise.song()')
  oprint(renoise.song())
  print('---- renoise.tool()')
  oprint(renoise.tool())
  showMarksDialog()
end


