---@diagnostic disable: inject-field
local M = {}

local u = require( "test/utils" )
local _, eq = u.luaunit( "assertEquals" )
local RollingPopup = require( "src/RollingPopup" )

local function strip_functions( t )
  for _, line in ipairs( t ) do
    for k, v in pairs( line ) do
      if type( v ) == "function" then
        line[ k ] = nil
      end
    end
  end

  return t
end

local function cleanse( t )
  return u.map( strip_functions( t ), function( v )
    if (v.type == "text" or v.type == "info") and v.value then
      v.value = u.decolorize( v.value ) or v.value
    end

    return v
  end )
end

---@class RollingPopupMock : RollingPopup
---@field content fun(): table
---@field should_display fun( ...: table ): table
---@field is_visible fun(): boolean
---@field should_be_visible fun()
---@field should_be_hidden fun()
---@field click fun( button_type: RollingPopupButtonType )
---@field award fun( player_name: string )

---@param popup_builder PopupBuilder
---@param db table
---@param config Config
function M.new( popup_builder, db, config )
  local transformed_content
  local model ---@type RollingPopupData?

  local transformer = require( "src/RollingPopupContentTransformer" ).new( config )
  local popup = RollingPopup.new( popup_builder, transformer, db, config )
  popup.content = function() return transformed_content and cleanse( transformed_content ) or {} end

  local original_refresh = popup.refresh
  popup.refresh = function( _, input )
    transformed_content = transformer.transform( input )
    model = input
    original_refresh( _, model )
  end

  popup.is_visible = function()
    local frame = popup and popup.get_frame()
    return frame and frame:IsVisible() or false
  end

  popup.click = function( button_type )
    if not model then return end

    local buttons = model.type == "Tie" and model.roll_data.buttons or model.buttons

    if not buttons then
      error( "There were no buttons to click." )
    end

    for _, button in ipairs( buttons ) do
      if button.type == button_type then button.callback() end
    end
  end

  popup.award = function( player_name )
    if not model then return end

    for _, winner in ipairs( model.winners ) do
      if winner.name == player_name and winner.award_callback then winner.award_callback() end
    end
  end

  local function should_be_visible( level )
    if not popup.is_visible() then
      error( "Rolling popup is hidden.", level )
    end
  end

  popup.should_display = function( ... )
    should_be_visible( 3 )
    eq( transformed_content and cleanse( transformed_content ) or {}, { ... }, _, _, 3 )
  end

  popup.should_be_visible = function()
    should_be_visible( 2 )
  end

  popup.should_be_hidden = function()
    if popup.is_visible() then
      error( "Rolling popup is visible.", 2 )
    end
  end

  ---@type RollingPopupMock
  return popup
end

return M
