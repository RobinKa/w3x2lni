local progress = require 'progress'

local type = type
local pairs = pairs

local revert_list
local unit_list

local mt = {}
mt.__index = mt

local function remove_nil_value(key, data, default)
    if type(data) ~= 'table' then
        return
    end
    local len = 0
    for n in pairs(data) do
        if n > len then
            len = n
        end
    end
    local dest = default[key]
    local tp = type(data[len])
    for i = 1, len do
        if not data[i] then
            if tp == 'number' then
                data[i] = dest[#dest]
            end
        end
    end
end

local function fill_obj(name, obj, type, default, config)
    local parent = obj._lower_parent
    local max_level = obj._max_level
    local default = default[parent]
    for key, data in pairs(obj) do
        if key:sub(1, 1) ~= '_' then
            remove_nil_value(key, data, default)
        end
    end
end

local function get_revert_list(default, parent)
    if not revert_list then
        revert_list = {}
        for lname, obj in pairs(default) do
            local parent = obj['_lower_parent']
            local list = revert_list[parent]
            if not list then
                revert_list[parent] = lname
            else
                if type(list) ~= 'table' then
                    revert_list[parent] = {[list] = true}
                end
                revert_list[parent][lname] = true
            end
        end
    end
    return revert_list[parent]
end

local function get_unit_list(default, name)
    if not unit_list then
        unit_list = {}
        for lname, obj in pairs(default) do
            local _name = obj['_name']
            if _name then
                local list = unit_list[_name]
                if not list then
                    unit_list[_name] = lname
                else
                    if type(list) ~= 'table' then
                        unit_list[_name] = {[list] = true}
                    end
                    unit_list[_name][lname] = true
                end
            end
        end
    end
    return unit_list[name]
end

local function find_para(name, obj, default, type)
    if obj['_true_origin'] then
        local parent = obj['_lower_parent']
        return parent
    end
    if default[name] then
        return name
    end
    local parent = obj['_lower_parent']
    if parent then
        local list = get_revert_list(default, parent)
        if list then
            return list
        end
    end
    if type == 'unit' then
        local list = get_unit_list(default, obj['_name'])
        if list then
            return list
        end
    end
    return default
end

local function try_obj(obj, may_obj)
    local diff_count = 0
    for name, may_data in pairs(may_obj) do
        if name:sub(1, 1) ~= '_' then
            local data = obj[name]
            if type(may_data) == 'table' then
                if type(data) == 'table' then
                    for i = 1, #may_data do
                        if data[i] ~= may_data[i] then
                            diff_count = diff_count + 1
                            break
                        end
                    end
                else
                    diff_count = diff_count + 1
                end
            else
                if data ~= may_data then
                    diff_count = diff_count + 1
                end
            end
        end
    end
    return diff_count
end

local function parse_obj(name, obj, default, config, ttype)
    local parent
    local count
    local find_times = config.find_id_times
    local maybe = find_para(name, obj, default, ttype)
    if type(maybe) ~= 'table' then
        obj._lower_parent = maybe
        return
    end

    for try_name in pairs(maybe) do
        local new_count = try_obj(obj, default[try_name])
        if not count or count > new_count or (count == new_count and parent > try_name) then
            count = new_count
            parent = try_name
        end
        find_times = find_times - 1
        if find_times == 0 then
            break
        end
    end

    obj._lower_parent = parent
end

local function processing(w2l, type, chunk, target_progress)
    local default = w2l:parse_lni(io.load(w2l.default / (type .. '.ini')))
    metadata = w2l:read_metadata(type)
    local config = w2l.config
    local names = {}
    for name in pairs(chunk) do
        names[#names+1] = name
    end
    table.sort(names, function(a, b)
        return chunk[a]['_id'] < chunk[b]['_id']
    end)

    revert_list = nil
    unit_list = nil
    
    local clock = os.clock()
    for i, name in ipairs(names) do
        parse_obj(name, chunk[name], default, config, type)
        if os.clock() - clock >= 0.1 then
            clock = os.clock()
            message(('搜索最优模板[%s] (%d/%d)'):format(chunk[name]._id, i, #names))
            progress(i / #names)
        end
    end
    for i, name in ipairs(names) do
        fill_obj(name, chunk[name], type, default, config)
        if os.clock() - clock >= 0.1 then
            clock = os.clock()
            message(('补全数据[%s] (%d/%d)'):format(chunk[name]._id, i, #names))
        end
    end
end

return function (w2l, slk)
    local count = 0
    for type, name in pairs(w2l.info.template.obj) do
        count = count + 1
        local target_progress = 17 + 7 * count
        processing(w2l, type, slk[type], target_progress)
    end
end