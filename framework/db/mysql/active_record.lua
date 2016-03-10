local Query = require "framework.db.mysql.query"
local Schema = require "framework.db.mysql.schema"
local Replica = require "framework.db.mysql.replica"

local ActiveRecord = {
    table_name = "",
    primary_key = "id",
    config_group = "default",
    config = {},
    table_schema = nil,
    replica = nil,
}

ActiveRecord.__index = ActiveRecord
 
function ActiveRecord:new(row, from_db)
    if from_db == nil then from_db = false end
    if row == nil then row = {} end
    local model = {
        attributes = row,
        is_new = not from_db,
        updated_columns = {},
    }
    setmetatable(model, {
        __newindex = function(table, key, value)
            if self:get_columns()[key] then
                rawset(table.updated_columns, key, value)
                rawset(table.attributes, key, value)
            else
                rawset(table, key, value)
            end
        end,
        __index = self,
    })
    return model
end

function ActiveRecord:get_replica()
    if self.replica then
        return self.replica
    end
    self.replica = Replica:instance(self.config_group, self.config)
    return self.replica
end

function ActiveRecord:get_master_conn()
    return self:get_replica():master()
end

function ActiveRecord:get_slave_conn()
    local conn = self:get_replica():slave()
    if not conn then
        conn = self:get_master_conn()
    end
    return conn
end

function ActiveRecord:get_table_schema()
    if self.table_schema then
        return self.table_schema
    end

    local table_schema = Schema:new(self)
    table_schema:load_table_schema()
    self.table_schema = table_schema
    return self.table_schema
end

function ActiveRecord:get_columns()
    local table_schema = self:get_table_schema()
    return table_schema.columns
end

function ActiveRecord:find()
    return Query:new(self)
end

local function insert(self)
    return Query:new(self):insert(self.table_name, self.attributes)
end

local function update(self)
    local attributes = {}
    for key, value in pairs(self.attributes) do
        if self.updated_columns[key] then
            attributes[key] = value
        end
    end
    return Query:new(self):update(self.table_name, attributes, self.attributes[self.primary_key])
end

function ActiveRecord:save()
    if self.is_new then
        local success = insert(self).affected_rows > 0
        if success then
            self.is_new = false
        end
        return success
    else
        -- TODO only update if new value not equals old value
        -- setted column value may not be dirty
        local success = update(self).affected_rows > 0
        if success then
            self.updated_columns = {}
        end
        return success
    end
end

function ActiveRecord:to_array()
    return self.attributes
end

return ActiveRecord
