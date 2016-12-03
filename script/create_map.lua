local stormlib = require 'ffi.stormlib'
local lni = require 'lni'
local read_metadata = require 'read_metadata'
local read_ini = require 'read_ini'
local create_template = require 'create_template'
local read_slk = require 'read_slk'
local read_txt = require 'read_txt'
local progress = require 'progress'

local table_insert = table.insert

local function dir_scan(dir, callback)
	for full_path in dir:list_directory() do
		if fs.is_directory(full_path) then
			-- 递归处理
			dir_scan(full_path, callback)
		else
			callback(full_path)
		end
	end
end

local function remove_then_create_dir(dir)
	if fs.exists(dir) then
		task(fs.remove_all, dir)
	end
	task(fs.create_directories, dir)
end

local function add_table(tbl1, tbl2)
    for k, v in pairs(tbl2) do
        if tbl1[k] then
            if type(tbl1[k]) == 'table' and type(v) == 'table' then
                add_table(tbl1[k], v)
            end
        else
            tbl1[k] = v
        end
    end
end

local function resize_string(str, left, right)
    local points = {}
    local chars = {}
    for p, c in utf8.codes(str) do
        chars[#chars+1] = c
        points[#points+1] = #chars
        if c > 255 then
            points[#points+1] = #chars
        end
    end
    if #points <= left + right then
        return str
    end
    return utf8.char(table.unpack(chars, 1, points[left] or 0)) .. '...' .. utf8.char(table.unpack(chars, points[#points - right + 1] or (#points+1)))
end

local mt = {}
mt.__index = mt

function mt:add(format, ...)
    self.hexs[#self.hexs+1] = (format):pack(...)
end

function mt:add_head()
    self:add('c4', 'HM3W')
    self:add('c4', '\0\0\0\0')
end

function mt:add_name()
    self:add('z', self.w3i.map_name)
end

function mt:add_flag()
    self:add('l', self.w3i.map_flag)
end

function mt:add_playercount()
    self:add('l', self.w3i.player_count)
end

function mt:add_input(input)
    if fs.is_directory(input) then
        if #self.w3xs > 0 then
            return false
        end
        table_insert(self.dirs, input)
    else
        if #self.dirs > 0 then
            return false
        end
        table_insert(self.w3xs, input)
    end
    return true
end

function mt:get_listfile()
    local files = {}
    local dirs = {}
    local listfile = {}
	local pack_ignore = {}
	for _, name in ipairs(self.info['pack']['packignore']) do
		pack_ignore[name:lower()] = true
	end
    
	local clock = os.clock()
	local success, failed = 0, 0
    for _, dir in ipairs(self.dirs) do
        local dir_len = #dir:string()
        dir_scan(dir, function(path)
            local name = path:string():sub(dir_len+2)
            if not pack_ignore[name:lower()] then
                listfile[#listfile+1] = name
                files[name] = io.load(path)
                dirs[name] = dir
                if files[name] then
                    success = success + 1
                else
                    failed = failed + 1
                    message('文件读取失败', name)
                end
                if os.clock() - clock >= 0.5 then
                    clock = os.clock()
                    if failed == 0 then
                        message('正在读取', '成功:', success)
                    else
                        message('正在读取', '成功:', success, '失败:', failed)
                    end
                end
            end
        end)
    end
    if failed == 0 then
        message('读取完毕', '成功:', success)
    else
	    message('读取完毕', '成功:', success, '失败:', failed)
    end
	return listfile, files, dirs
end

function mt:to_w3x(name, file)
	if name:sub(-4) == '.ini' and self.info['metadata'][name:sub(1, -5)] then
		message('正在转换:', name)
		local data = lni:loader(file, name)
		local new_name = name:sub(1, -5)
        if self.on_lni then
            data = self:on_lni(new_name, data)
        end
        if self.wts then
            self.wts:save(data)
        end
		local key = lni:loader(io.load(self.dir['key'] / name), name)
		local metadata = read_metadata(self.dir['meta'] / self.info['metadata'][new_name])
		local template = lni:loader(io.load(self.dir['template'] / name), new_name)
		local content = self.w3x2lni:lni2obj(data, metadata, key, template)
		return new_name, content
	elseif name == 'war3map.w3i.ini' then
		message('正在转换:', name)
		local data = lni:loader(file, name)
		local new_name = name:sub(1, -5)
        if self.on_lni then
            data = self:on_lni(new_name, data)
        end
        if self.wts then
            self.wts:save(data)
        end
		local content = self.w3x2lni:lni2w3i(data)
		return new_name, content
	elseif name == 'war3map.w3i' then
		w3i = file
		return name, file
	else
		return name, file
	end
end

function mt:import_files(map, listfile, files, dirs)
	self.wts = self.w3x2lni:read_wts(files['war3map.wts'] or '')
	local clock = os.clock()
	local success, failed = 0, 0
	for i = 1, #listfile do
		local name = listfile[i]
        local content = files[name]
        if self.on_save then
            name, content = self:on_save(name, content, dirs[name])
        end
        if name then
            local name, content = self:to_w3x(name, content)
            if content then
                if map:save_file(name, content) then
                    success = success + 1
                else
                    failed = failed + 1
                    message('文件导入失败', name)
                end
                if os.clock() - clock >= 0.5 then
                    clock = os.clock()
                    if failed == 0 then
                        message('正在导入', '成功:', success)
                    else
                        message('正在导入', '成功:', success, '失败:', failed)
                    end
                end
            end
        end
	end
    if failed == 0 then
        message('导入完毕', '成功:', success)
    else
	    message('导入完毕', '成功:', success, '失败:', failed)
    end
    local content = self.wts:refresh()
    map:save_file('war3map.wts', content)
    if not files['war3mapunits.doo'] then
        map:save_file('war3mapunits.doo', self.w3x2lni:create_unitsdoo())
    end
end

function mt:import_imp(map, listfile)
	local imp_ignore = {}
	for _, name in ipairs(self.info['pack']['impignore']) do
		imp_ignore[name:lower()] = true
	end

	local imp = {}
	for _, name in ipairs(listfile) do
		if not imp_ignore[name:lower()] then
			imp[#imp+1] = ('z'):pack(name)
		end
	end
	table.insert(imp, 1, ('ll'):pack(1, #imp))
	if not map:save_file('war3map.imp', table.concat(imp, '\r')) then
		message('war3map.imp导入失败')
	end
end

function mt:save_map(map_path)
    local w3i = {
        map_name = '只是另一张魔兽争霸III地图',
        map_flag = 0,
        player_count = 2333,
    }
    for _, dir in ipairs(self.dirs) do
        if fs.exists(dir / 'war3map.w3i.ini') then
            w3i = self.w3x2lni:read_w3i(self.w3x2lni:lni2w3i(lni:loader(io.load(dir / 'war3map.w3i.ini'), 'war3map.w3i.ini')))
            break
        end
    end

    self.hexs = {}
    self.w3i  = w3i

    self:add_head()
    self:add_name()
    self:add_flag()
    self:add_playercount()

    local temp_path = fs.path 'temp'

    io.save(temp_path, table.concat(self.hexs))
    
    local listfile, files, dirs = self:get_listfile()
    local map = stormlib.create(temp_path, #listfile+8)
	if not map then
		message('地图创建失败,可能是文件被占用了')
		return nil
	end

	self:import_files(map, listfile, files, dirs)
	self:import_imp(map, listfile)

    map:close()
    fs.rename(temp_path, map_path)
    
    return true
end

function mt:extract_files(map_path, output_dir, max_count)
	local files = {}
	local paths = {}
	local dirs = {}
    local map = stormlib.open(map_path)

	local clock = os.clock()
	local success, failed = 0, 0
    local function extract_file(name, is_try)
		local new_name, output_dir = name, output_dir
        if self.on_save then
            new_name, output_dir = self:on_save(name)
        end
		if new_name then
			if not dirs[output_dir:string()] then
				dirs[output_dir:string()] = true
				remove_then_create_dir(output_dir)
			end
			local path = output_dir / new_name
			fs.create_directories(path:parent_path())
			local buf = map:load_file(name)
			if buf then
				files[name] = buf
				paths[name] = path
				success = success + 1
			elseif not is_try then
				failed = failed + 1
				--message('文件读取失败', name)
			end
			if os.clock() - clock >= 0.1 then
				clock = os.clock()
				--if failed == 0 then
				--	message('正在读取', '成功:', success)
				--else
				--	message('正在读取', '成功:', success, '失败:', failed)
				--end
                local name = resize_string(name, 10, 15)
                message(('正在读取 [%s]'):format(name))
                progress((success + failed) / max_count)
			end
		end
    end
    
	for name in pairs(map) do
		extract_file(name:lower())
	end
	for name in pairs(self.info['metadata']) do
        if not files[name:lower()] then
            extract_file(name:lower(), 'try')
        end
        for _, name in ipairs(self.info['template']['slk'][name]) do
            if not files[name:lower()] then
                extract_file(name:lower(), 'try')
            end
        end
        for _, name in ipairs(self.info['template']['txt'][name]) do
            if not files[name:lower()] then
                extract_file(name:lower(), 'try')
            end
        end
    end
    --if failed == 0 then
    --    message('读取完毕', '成功:', success)
    --else
    --    message('读取完毕', '成功:', success, '失败:', failed)
    --end
    map:close()
    return files, paths
end

function mt:load_slk(file_name, meta, files, delete, data)
    local template = create_template(file_name)
    
    local slk = self.info['template']['slk'][file_name]
    for i = 1, #slk do
        local name = slk[i]
        message('正在转换', name)
        template:add_slk(read_slk(files[name] or io.load(self.dir['meta'] / name)))
        if files[name] then
            delete[name] = true
        end
    end

    local txt = self.info['template']['txt'][file_name]
    for i = 1, #txt do
        local name = txt[i]
        message('正在转换', name)
        template:add_txt(read_txt(files[name] or io.load(self.dir['meta'] / name)))
        if files[name] then
            delete[name] = true
        end
    end

    return template
end

function mt:load_obj(file_name, meta, files, delete, target_progress)
    local data = {}
    local metadata = read_metadata(self.dir['meta'] / self.info['metadata'][file_name])
    local temp_data = lni:loader(io.load(self.dir['template'] / (file_name .. '.ini')), file_name)
    local key_data = lni:loader(io.load(self.dir['key'] / (file_name .. '.ini')), file_name)

    if files[file_name] then
        message('正在转换', file_name)
        add_table(data, self.w3x2lni:read_obj(files[file_name], metadata))
        delete[file_name] = true
    end

    if self.config['unpack']['read_slk'] then
        local template = self:load_slk(file_name, meta, files, delete, data)
        add_table(data, template:save(metadata, key_data))
    end

    if next(data) then
        if not data['_版本'] then
            data['_版本'] = 2
        end
        if self.on_lni then
            data = self:on_lni(file_name, data)
        end
        local max_level_key = self.info['key']['max_level'][file_name]
        progress:target(target_progress)
        local content = self.w3x2lni:obj2lni(data, metadata, self.editstring, temp_data, key_data, max_level_key, file_name)
        if self.wts then
            content = self.wts:load(content)
        end
        return content
    end
end

function mt:to_lni(files, paths, output_dir, max_count)
	--读取编辑器文本
    progress:target(12)
	local ini = read_ini(self.dir['meta'] / 'WorldEditStrings.txt')
	if ini then
		self.editstring = ini['WorldEditStrings']
	end
	
	--读取字符串
    progress:target(15)
	if files['war3map.wts'] then
		self.wts = self.w3x2lni:read_wts(files['war3map.wts'])
	end
	
	local clock = os.clock()
	local success, failed = 0, 0
	local function save(path, content, max_count)
		if io.save(path, content) then
			success = success + 1
		else
			failed = failed + 1
			--message('文件导出失败', name)
		end
		if os.clock() - clock >= 0.1 then
			clock = os.clock()
			--if failed == 0 then
			--	message('正在导出', '成功:', success)
			--else
			--	message('正在导出', '成功:', success, '失败:', failed)
			--end
            if max_count then
                local name = resize_string(path:string(), 0, 25)
                message(('正在导出 [%s]'):format(name))
                progress((success + failed) / max_count)
            end
		end
	end

    local delete = {}
    local count = 0
    for file_name, meta in pairs(self.info['metadata']) do
        count = count + 1
        local target_progress = 15 + count * 9
        progress:target(target_progress - 7)
        --message(file_name)
        local content = self:load_obj(file_name, meta, files, delete, target_progress)
        if content then
            save(output_dir / (file_name .. '.ini'), content)
        end
    end

    for name in pairs(delete) do
        files[name] = nil
    end

    progress:target(98)
	for name, file in pairs(files) do
        if name == 'war3map.w3i' then
			local content = file
			local data = self.w3x2lni:read_w3i(content)
            if self.on_lni then
                data = self:on_lni(name, data)
            end
			local content = self.w3x2lni:w3i2lni(data)
            if self.wts then
			    content = self.wts:load(content, false, true)
            end
			save(paths['war3map.w3i']:parent_path() / 'war3map.w3i.ini', content, max_count)
		elseif name == 'war3map.wts' then
		else
			save(paths[name], file, max_count)
		end
	end
	
	--if failed == 0 then
	--	message('导出完毕', '成功:', success)
	--else
	--	message('导出完毕', '成功:', success, '失败:', failed)
	--end

	--刷新字符串
    progress:target(100)
    message('即将完成...')
	if self.wts then
		local content = self.wts:refresh()
		io.save(paths['war3map.wts'], content)
	end
end

function mt:unpack(output_dir)
    local map_path = self.w3xs[1]
    -- 解压地图
	local map = stormlib.open(map_path)
	if not map then
		message('地图打开失败')
		return false
	end

	if not map:has_file '(listfile)' then
		message('不支持没有文件列表(listfile)的地图')
		return false
	end
	
    local max_count = 0
    local list_file = map:load_file('(listfile)')
    for _ in list_file:gmatch '[^\r\n]+' do
        max_count = max_count + 1
    end

    map:close()
	
    progress:target(10)
	local files, paths = self:extract_files(map_path, output_dir, max_count)
	self:to_lni(files, paths, output_dir, max_count)
    progress:target(100)
    return true
end

function mt:save(map_path)
    if #self.dirs > 0 then
        return self:save_map(map_path)
    elseif #self.w3xs > 0 then
        return self:unpack(map_path)
    end
    return false
end

return function (w3x2lni)
    local self = setmetatable({}, mt)
    self.dirs = {}
    self.w3xs = {}
    self.config = w3x2lni.config
    self.info = w3x2lni.info
    self.dir = w3x2lni.dir
    self.w3x2lni = w3x2lni
    return self
end
