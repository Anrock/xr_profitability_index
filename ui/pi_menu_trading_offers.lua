local trade_offers_menu = {}
local PIFuncs = {}

local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
	typedef uint64_t TradeID;
	typedef struct {
		const char* wareid;
		uint32_t amount;
	} UIWareAmount;
	bool GetTradeMemoryBestBuyOffers(TradeID* result, uint32_t resultlen, UniverseID spaceid, UniverseID traderid, TradeID* uiselloffers, uint32_t uisellofferslen, UIWareAmount* uicargospace, uint32_t uicargospacelen);
	int GetCargoSpaceUsedAfterShoppingList(UniverseID containerid);
	uint32_t GetNumStoredUnits(UniverseID defensibleid, const char* cat, bool virtualammo);
	UniverseID GetShipSuperHighwayDestinationSector(UniverseID shipid);
]]

function log(s)
    DebugError("PI: " .. s)
end

local function init()
    for _, menu in ipairs(Menus) do
        if menu.name == "TradingOffersMenu" then
            trade_offers_menu = menu
            PIFuncs.inject(trade_offers_menu)
            log("Injected")
            break
        end
    end
end

PIFuncs.inject = function(menu)
    menu.displayMenu = PIFuncs.displayMenu
    menu.addDeal = PIFuncs.addDeal
    menu.strings.profitability = "Profitability"
end

PIFuncs.buy_price = function(t)
    if t[1].isplayer then
        return 0
    else
        return t[1].price * t.amount
    end
end

PIFuncs.sell_price = function(t)
    return t[2].price * t.amount
end

PIFuncs.profitability = function(t)
    return PIFuncs.sell_price(t) / PIFuncs.buy_price(t)
end

PIFuncs.deals_profitability = function(a, b)
    if trade_offers_menu.invertsort then
        return PIFuncs.profitability(a) < PIFuncs.profitability(b)
    else
        return PIFuncs.profitability(a) > PIFuncs.profitability(b)
    end
end
---------------------------------- Injected -----------------------------------
PIFuncs.getTradesList = function(menu)
    local trades = {}
    if menu.mode == "wareexchange" then
        trades = GetWareExchangeTradeList(menu.modeparam[1], menu.modeparam[2])
    else
        trades = GetTradeList(menu.ships[menu.ship] and menu.ships[menu.ship].shipid or nil, nil, true)
    end
    menu.trades = {}
    menu.tradegroups = menu.initTradeGroups(trades)

    for _, tradegroup in pairs(menu.tradegroups) do
        table.sort(tradegroup, menu.preferPlayerOwned)
        table.insert(menu.trades, tradegroup[1])
    end
    if menu.sort == "adjustment" then
        table.sort(menu.trades, menu.preferPlayerOwned)
    else
        table.sort(menu.trades, menu.sorter[menu.sort])
    end

    if firsttime and menu.tradeid then
        local highlighttrade
        if menu.mode == "deals" then
            local deal = menu.findDeal(menu.tradeid)
            highlighttrade = deal and deal[1] or nil
        else
            highlighttrade = menu.findTrade(menu.tradeid)
        end
        if not highlighttrade then
            if menu.tradegroups[menu.tradeware] and (#menu.tradegroups[menu.tradeware] > 0) then
                highlighttrade = menu.tradegroups[menu.tradeware][1]
                menu.tradeid = highlighttrade.id
            end
            menu.tradeware = nil
        end
        if highlighttrade then
            if menu.tradegroups[highlighttrade.ware] and (#menu.tradegroups[highlighttrade.ware] > 1) then
                menu.extendedwares[highlighttrade.ware] = true
            end
        end
    elseif sellbuyswitch then
        local highlighttrade
        if menu.tradegroups[menu.tradeware] and (#menu.tradegroups[menu.tradeware] > 0) then
            highlighttrade = menu.tradegroups[menu.tradeware][1]
            menu.tradeid = highlighttrade.id
        end
        menu.tradeware = nil
    end
end

PIFuncs.shipTable = function(menu)
    local emptyFontStringSmall = Helper.createFontString("", false, Helper.standardHalignment, Helper.standardColor.r, Helper.standardColor.g, Helper.standardColor.b, Helper.standardColor.a, Helper.standardFont, 6, false, Helper.headerRow1Offsetx, Helper.headerRow1Offsety, 6)
    local setup = Helper.createTableSetup(menu)
    local title = ""
    if menu.mode == "wareexchange" then
        title = string.format(menu.sellbuyswitch and menu.strings.transferfrom or menu.strings.transferto, GetComponentData(menu.modeparam[2], "name"))
    elseif menu.mode == "deals" then
        title = menu.strings.tradedeals
    else
        title = menu.sellbuyswitch and menu.strings.selloffers or menu.strings.buyoffers
    end
    setup:addTitleRow({
        Helper.createFontString(title, false, Helper.standardHalignment, 255, 255, 255, 100, Helper.headerRow1Font, 18, false, Helper.standardTextOffsetx, Helper.standardTextOffsety, 32),
        Helper.createEditBox(Helper.createButtonText(menu.searchtext, "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), false, 0, 0, 300, 30, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_0", true), true),
        Helper.getEmptyCellDescriptor()
    }, nil, {3, 1, 2})
    setup:addHeaderRow({ emptyFontStringSmall }, nil, {6})
    if menu.ships[menu.ship] then
        local ship = menu.ships[menu.ship]
        local clusterid, sectorid, zone, zoneid, shipimage = GetComponentData(ship.shipid, "clusterid", "sectorid", "zone", "zoneid", "image")
        local cargo = GetCargoAfterShoppingList(ship.shipid)
        local cargoplanned = C.GetCargoSpaceUsedAfterShoppingList(ConvertIDTo64Bit(ship.shipid))
        local line1, line2, line3 = "", "", ""
        if next(cargo) then
            local tempcargo = {}
            for ware, amount in pairs(cargo) do
                if ware ~= "fuelcells" then
                    table.insert(tempcargo, {ware = ware, amount = amount})
                end
            end
            table.sort(tempcargo, menu.sortCargo)
            if cargo["fuelcells"] then
                table.insert(tempcargo, {ware = "fuelcells", amount = cargo["fuelcells"]})
            end
            local lines = 3
            local count = #tempcargo
            local step = math.floor(count / lines)
            local rest = count % lines
            local step1 = step + (rest > 0 and 1 or 0)
            local step2 = step1 + step + (rest > 1 and 1 or 0)
            for i, entry in ipairs(tempcargo) do
                local temp = ""
                if i <= step1 then
                    temp = line1
                elseif i <= step2 then
                    temp = line2
                else
                    temp = line3
                end

                local newwarestring = "   " .. GetWareData(entry.ware, "name") .. ReadText(1001, 120) .. " " .. ConvertIntegerString(entry.amount, true, 0, true)
                if i ~= count then
                    newwarestring = newwarestring .. ", "
                end
                temp = temp .. newwarestring
                if GetTextNumLines(temp .. ((i > step2 and i ~= count) and "   ..." or ""), Helper.standardFont, Helper.scaleFont(Helper.standardFont, Helper.standardFontSize), Helper.scaleX(Helper.standardSizeX - 2 * Helper.standardButtonWidth - 214 - Helper.standardTextOffsety) - 15) > 1 then
                    if i <= step1 then
                        line2 = line2 .. newwarestring
                        step1 = i - 1
                    elseif i <= step2 then
                        line3 = line3 .. newwarestring
                        step2 = i - 1
                    else
                        line3 = line3 .. "   ..."
                        break
                    end
                else
                    if i <= step1 then
                        line1 = temp
                    elseif i <= step2 then
                        line2 = temp
                    else
                        line3 = temp
                    end
                end
            end
        else
            line1 = line1 .. "-"
        end
        menu.cargolist = line1 .. "\n" .. line2 .. "\n" .. line3
        setup:addSimpleRow({
            Helper.createButton(nil, Helper.createButtonIcon("table_arrow_inv_left", nil, 255, 255, 255, 100), false, #menu.ships > 1 and menu.mode ~= "wareexchange", 0, 0, Helper.standardButtonWidth, 114, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_LB", true), nil, (#menu.ships == 1) and menu.strings.mot_noships or nil),
            Helper.createIcon(shipimage ~= "" and shipimage or "transferSlider", false, 255, 255, 255, 100, 0, 0, 114, 214),
            Helper.createFontString(ship.name .. " (" .. menu.ship .. "/" .. #menu.ships .. ") - " .. GetComponentData(clusterid, "mapshortname") .. (sectorid and ("." .. GetComponentData(sectorid, "mapshortname") .. "." .. GetComponentData(zoneid, "mapshortname")) or "") .. ReadText(1001, 120) .. " " .. zone .. "\n" .. menu.strings.queued .. ReadText(1001, 120) .. " " .. ship.numtrips .. " / " .. menu.maxtrips .. "\n" .. menu.strings.capacity .. ReadText(1001, 120) .. " " .. ConvertIntegerString(cargoplanned, true, 3, true) .. " / " .. ConvertIntegerString(ship.cargomax, true, 3, true) .. "\n" .. menu.cargolist, false, "left", 255, 255, 255, 100, Helper.standardFont, Helper.standardFontSize, true, Helper.standardTextOffsetx, Helper.standardTextOffsety, 114),
            Helper.createButton(nil, Helper.createButtonIcon("table_arrow_inv_right", nil, 255, 255, 255, 100), false, #menu.ships > 1 and menu.mode ~= "wareexchange", 0, 0, Helper.standardButtonWidth, 114, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_RB", true), nil, (#menu.ships == 1) and menu.strings.mot_noships or nil)
        }, nil, {1, 1, 3, 1})
    else
        setup:addSimpleRow({
            Helper.createButton(nil, Helper.createButtonIcon("table_arrow_inv_left", nil, 255, 255, 255, 100), false, false, 0, 0, Helper.standardButtonWidth, 114, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_LB", true), nil,  menu.strings.mot_noships),
            Helper.createFontString(menu.strings.noships, false, "left", 255, 255, 255, 100, Helper.standardFont, Helper.standardFontSize, true, Helper.standardTextOffsetx, Helper.standardTextOffsety, 114),
            Helper.createButton(nil, Helper.createButtonIcon("table_arrow_inv_right", nil, 255, 255, 255, 100), false, false, 0, 0, Helper.standardButtonWidth, 114, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_RB", true), nil,  menu.strings.mot_noships)
        }, nil, {1, 4, 1})
    end
    setup:addHeaderRow({ emptyFontStringSmall }, nil, {6})
    local padding = math.max(1, 32 - Helper.scaleX(Helper.standardButtonWidth))
    return setup:createCustomWidthTable({Helper.scaleX(Helper.standardButtonWidth), Helper.scaleX(214), 0, Helper.scaleX(300), padding, Helper.scaleX(Helper.standardButtonWidth)}, false, true, true, 2, 4, 0, 0, 0, false)
end

PIFuncs.dealsRangeFilterRow = function(menu)
    setup:addSimpleRow({
        menu.strings.range .. ReadText(1001, 120) .. " ",
        Helper.createButton(Helper.createButtonText(menu.filternames[1] .. (menu.filter == nil and " *" or ""), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 0, 25),
        Helper.createButton(Helper.createButtonText(menu.filternames[2] .. (menu.filtering[2] == menu.filter and " *" or ""), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 0, 25),
        Helper.createButton(Helper.createButtonText(menu.filternames[3] .. (menu.filtering[3] == menu.filter and " *" or ""), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 0, 25)
    }, nil, {5, 1, 1, 1})
end

PIFuncs.wareExchangeCargoTypeFilterRow = function(menu)
    setup:addSimpleRow({
        menu.strings.categories .. ReadText(1001, 120) .. " ",
        Helper.createButton(Helper.createButtonText(menu.filternames[1] .. (menu.filter == nil and " *" or ""), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 0, 25),
        Helper.createButton(Helper.createButtonText(menu.filternames[2] .. (menu.filtering[2] == menu.filter and " *" or ""), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 0, 25),
        Helper.createButton(Helper.createButtonText(menu.filternames[3] .. (menu.filtering[3] == menu.filter and " *" or ""), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 0, 25),
        Helper.createButton(Helper.createButtonText(menu.filternames[4] .. (menu.filtering[4] == menu.filter and " *" or ""), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 0, 25),
        Helper.createButton(Helper.createButtonText(menu.filternames[5] .. (menu.filtering[5] == menu.filter and " *" or ""), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 0, 25)
    }, nil, {2, 1, 1, 1, 1, 1})
end

PIFuncs.wareExchangeHeaderRow = function(menu)
    local arrowwidth = 22
    local arrowheight = 19
    local arrowoffsety = 2

    setup:addSimpleRow({
        Helper.createButton(Helper.createButtonText(menu.sortnames[1], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[1] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_up" or "table_arrow_inv_down", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[1],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[2], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[2] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_down" or "table_arrow_inv_up", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[2],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[3], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[3] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_up" or "table_arrow_inv_down", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[3],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil)
    }, nil, {5, 1, 1})
end

PIFuncs.dealsHeaderRow = function(menu)
    local arrowwidth = 22
    local arrowheight = 19
    local arrowoffsety = 2

    setup:addSimpleRow({
        Helper.createButton(Helper.createButtonText(menu.sortnames[1], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[1] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_up" or "table_arrow_inv_down", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[1],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[2], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[2] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_down" or "table_arrow_inv_up", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[2],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[3], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[3] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_up" or "table_arrow_inv_down", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[3],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[4], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[4] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_up" or "table_arrow_inv_down", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[4],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[5], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[5] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_up" or "table_arrow_inv_down", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[5],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil)
    }, nil, {4, 1, 1, 1, 1})
end

PIFuncs.tradeOffersHeaderRow = function(menu)
    local arrowwidth = 22
    local arrowheight = 19
    local arrowoffsety = 2
    setup:addSimpleRow({
        Helper.createButton(Helper.createButtonText(menu.sortnames[1], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[1] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_up" or "table_arrow_inv_down", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[1],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[2], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[2] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_down" or "table_arrow_inv_up", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[2],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[3], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[3] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_down" or "table_arrow_inv_up", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[3],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[4], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[4] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_down" or "table_arrow_inv_up", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[4],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[5], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[5] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_down" or "table_arrow_inv_up", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[5],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil),
        Helper.createButton(Helper.createButtonText(menu.sortnames[6], "left", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100, Helper.standardTextOffsetx), nil, false, true, 0, 0, 0, 25, nil, nil, (menu.sorting[6] == menu.sort) and Helper.createButtonIcon(menu.invertsort and "table_arrow_inv_down" or "table_arrow_inv_up", nil, 255, 255, 255, 100, arrowwidth, arrowheight, GetTextWidth(menu.sortnames[6],  Helper.standardFont, Helper.standardFontSize) + Helper.standardTextOffsetx, arrowoffsety) or nil)
    }, nil, {2, 1, 1, 1, 1, 1})
end

PIFuncs.tradeOfferTable = function(menu)
    setup = Helper.createTableSetup(menu)
    if menu.mode == "deals" then
        PIFuncs.dealsRangeFilterRow(menu)
    else
        PIFuncs.wareExchangeCargoTypeFilterRow(menu)
    end

    if menu.mode == "wareexchange" then
        PIFuncs.wareExchangeHeaderRow(menu)
    elseif menu.mode == "deals" then
        PIFuncs.dealsHeaderRow(menu)
    else
        PIFuncs.tradeOffersHeaderRow(menu)
    end

    local nooftrades = 0
    menu.highlighttraderow = 1

    if next(menu.trades) then
        if menu.mode == "deals" then
            for _, deal in ipairs(menu.trades) do
                if firsttime and menu.mode == "wareexchange" and #menu.tradegroups[deal[1].ware] > 1 then
                    menu.extendedwares[deal[1].ware] = true
                end
                if menu.extendedwares[deal[1].ware] then
                    setup:addSimpleRow({
                        Helper.createButton(Helper.createButtonText(menu.extendedwares[deal[1].ware] and "-" or "+", "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, #menu.tradegroups[deal[1].ware] > 1, 0, 0, 0, Helper.standardTextHeight),
                        deal[1].name
                    }, nil, {1, 7}, false, Helper.defaultHeaderBackgroundColor)
                    nooftrades = nooftrades + 1
                else
                    nooftrades = menu.addDeal(setup, deal, true, nooftrades)
                end
                if menu.extendedwares[deal[1].ware] then
                    nooftrades = menu.addDeal(setup, deal, false, nooftrades)
                    for i, deal2 in ipairs(menu.tradegroups[deal[1].ware]) do
                        if i ~= 1 then
                            nooftrades = menu.addDeal(setup, deal2, false, nooftrades)
                        end
                    end
                end
            end
        else
            for _, trade in ipairs(menu.trades) do
                if firsttime and menu.mode == "wareexchange" and #menu.tradegroups[trade.ware] > 1 then
                    menu.extendedwares[trade.ware] = true
                end
                if menu.extendedwares[trade.ware] then
                    setup:addSimpleRow({
                        Helper.createButton(Helper.createButtonText(menu.extendedwares[trade.ware] and "-" or "+", "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, #menu.tradegroups[trade.ware] > 1, 0, 0, 0, Helper.standardTextHeight),
                        trade.name
                    }, nil, {1, 6}, false, Helper.defaultHeaderBackgroundColor)
                    nooftrades = nooftrades + 1
                else
                    nooftrades = menu.addTrade(setup, trade, true, nooftrades)
                end
                if menu.extendedwares[trade.ware] then
                    nooftrades = menu.addTrade(setup, trade, false, nooftrades)
                    for i, trade2 in ipairs(menu.tradegroups[trade.ware]) do
                        if i ~= 1 then
                            nooftrades = menu.addTrade(setup, trade2, false, nooftrades)
                        end
                    end
                end
            end
        end
    else
        if menu.mode == "deals" then
            setup:addSimpleRow({
                menu.strings.notrades
            }, nil, {8}, false, menu.grey)
        else
            setup:addSimpleRow({
                menu.strings.notrades
            }, nil, {7}, false, menu.grey)
        end
    end

    local offertabledesc
    if menu.mode == "deals" then
        setup:addFillRows(12, false, {8})
        offertabledesc = setup:createCustomWidthTable({Helper.standardButtonWidth, 0, 100, 100, 100, 130, 130, 130}, false, false, true, 1, 2, 0, 177, 311, true, menu.settoprow or (menu.highlighttraderow > (nooftrades - 10) and (nooftrades - 7) or (menu.highlighttraderow + 2)), menu.highlighttraderow + 2)
    else
        setup:addFillRows(12, false, {7})
        offertabledesc = setup:createCustomWidthTable({Helper.standardButtonWidth, 0, 100, 100, 100, 130, 130}, false, false, true, 1, 2, 0, 177, 311, true, menu.settoprow or (menu.highlighttraderow > (nooftrades - 10) and (nooftrades - 7) or (menu.highlighttraderow + 2)), menu.highlighttraderow + 2)
    end
    menu.settoprow = nil
    return offertabledesc
end

PIFuncs.summaryTable = function(menu)
    local emptyFontStringSmall = Helper.createFontString("", false, Helper.standardHalignment, Helper.standardColor.r, Helper.standardColor.g, Helper.standardColor.b, Helper.standardColor.a, Helper.standardFont, 6, false, Helper.headerRow1Offsetx, Helper.headerRow1Offsety, 6)
    setup = Helper.createTableSetup(menu)
    setup:addHeaderRow({ emptyFontStringSmall }, nil, {9})
    setup:addTitleRow({ 
        Helper.createFontString("", false, "left", 255, 255, 255, 100, Helper.standardFont, Helper.standardFontSize, true, Helper.standardTextOffsetx, Helper.standardTextOffsety, 2 * Helper.standardTextHeight)
    }, nil, {9})
    setup:addHeaderRow({ emptyFontStringSmall }, nil, {9}, false, menu.transparent)
    local sellbuybuttontext = ""
    if menu.mode == "wareexchange" then
        sellbuybuttontext = menu.sellbuyswitch and menu.strings.totransferto or menu.strings.totransferfrom
    else
        sellbuybuttontext = menu.sellbuyswitch and menu.strings.tobuyoffers or menu.strings.toselloffers
        mot_sellbuybutton = menu.sellbuyswitch and menu.strings.mot_tobuyoffers or menu.strings.mot_toselloffers
    end
    setup:addSimpleRow({ 
        "",
        Helper.createButton(Helper.createButtonText(menu.strings.back, "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_B", true)),
        "",
        (menu.mode == "deals") and "" or Helper.createButton(Helper.createButtonText(sellbuybuttontext, "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_BACK", true), nil, mot_sellbuybutton),
        "",
        Helper.createButton(Helper.createButtonText(menu.strings.details, "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, next(menu.trades) ~= nil, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_Y", true), nil, menu.strings.mot_details),
        "",
        Helper.createButton(Helper.createButtonText(menu.strings.next, "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, next(menu.trades) and (menu.ships[menu.ship] ~= nil), 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_X", true)),
        ""
    }, nil, nil, false, menu.transparent)
    return setup:createCustomWidthTable({48, 150, 48, 150, 0, 150, 48, 150, 48}, false, false, true, 3, 4, 0, 489, 0, false)
end

PIFuncs.displayMenu = function()
    local menu = trade_offers_menu
    if menu.mode == "deals" then
        table.insert(menu.sortnames, menu.strings.profitability)
        table.insert(menu.sorting, "deals_profitability")
        menu.sorter.deals_profitability = PIFuncs.deals_profitability
    end

    -- Remove possible button scripts from previous view
    Helper.removeAllButtonScripts(menu)
    Helper.currentTableRow = {}
    Helper.currentTableRowData = nil
    menu.rowDataMap = {}

    PIFuncs.getTradesList(menu)
    local shiptabledesc = PIFuncs.shipTable(menu)
    local offertabledesc = PIFuncs.tradeOfferTable(menu)
    local buttontabledesc = PIFuncs.summaryTable(menu)

    -- create tableview
    menu.shiptable, menu.offertable, menu.buttontable = Helper.displayThreeTableView(menu, shiptabledesc, offertabledesc, buttontabledesc, false)

    -- set editbox script
    Helper.setEditBoxScript(menu, nil, menu.shiptable, 1, 4, menu.editboxUpdateText)

    -- set button scripts
    -- ship table
    Helper.setButtonScript(menu, nil, menu.shiptable, 3, 1, menu.buttonShipLeft)
    Helper.setButtonScript(menu, nil, menu.shiptable, 3, 6, menu.buttonShipRight)

    -- offer table
    if menu.mode == "deals" then
        Helper.setButtonScript(menu, nil, menu.offertable, 1, 6, function () return menu.buttonSetFilter(menu.filtering[1]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 1, 7, function () return menu.buttonSetFilter(menu.filtering[2]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 1, 8, function () return menu.buttonSetFilter(menu.filtering[3]) end)
    else
        Helper.setButtonScript(menu, nil, menu.offertable, 1, 3, function () return menu.buttonSetFilter(menu.filtering[1]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 1, 4, function () return menu.buttonSetFilter(menu.filtering[2]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 1, 5, function () return menu.buttonSetFilter(menu.filtering[3]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 1, 6, function () return menu.buttonSetFilter(menu.filtering[4]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 1, 7, function () return menu.buttonSetFilter(menu.filtering[5]) end)
    end

    Helper.setButtonScript(menu, nil, menu.offertable, 2, 1, function () return menu.buttonSetSorter(menu.sorting[1]) end)
    if menu.mode == "wareexchange" then
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 6, function () return menu.buttonSetSorter(menu.sorting[2]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 7, function () return menu.buttonSetSorter(menu.sorting[3]) end)
    elseif menu.mode == "deals" then
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 5, function () return menu.buttonSetSorter(menu.sorting[2]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 6, function () return menu.buttonSetSorter(menu.sorting[3]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 7, function () return menu.buttonSetSorter(menu.sorting[4]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 8, function () return menu.buttonSetSorter(menu.sorting[5]) end)
    else
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 3, function () return menu.buttonSetSorter(menu.sorting[2]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 4, function () return menu.buttonSetSorter(menu.sorting[3]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 5, function () return menu.buttonSetSorter(menu.sorting[4]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 6, function () return menu.buttonSetSorter(menu.sorting[5]) end)
        Helper.setButtonScript(menu, nil, menu.offertable, 2, 7, function () return menu.buttonSetSorter(menu.sorting[6]) end)
    end

    local nooflines = 0
    for _, trade in ipairs(menu.trades) do
        nooflines = nooflines + 1
        if menu.mode == "deals" then
            Helper.setButtonScript(menu, nil, menu.offertable, 2 + nooflines, 1, function () return menu.buttonWareExtend(trade[1].ware, trade[1].id) end)
        else
            Helper.setButtonScript(menu, nil, menu.offertable, 2 + nooflines, 1, function () return menu.buttonWareExtend(trade.ware, trade.id) end)
        end
        local ware = (menu.mode == "deals") and trade[1].ware or trade.ware
        if menu.extendedwares[ware] then
            nooflines = nooflines + 1
            for i, trade2 in ipairs(menu.tradegroups[ware]) do
                if i ~= 1 then
                    nooflines = nooflines + 1
                end
            end
        end
    end

    -- button table
    Helper.setButtonScript(menu, nil, menu.buttontable, 4, 2, function () return menu.onCloseElement("back") end)
    if menu.mode ~= "deals" then
        Helper.setButtonScript(menu, nil, menu.buttontable, 4, 4, menu.buttonBuySellSwitch)
    end
    Helper.setButtonScript(menu, nil, menu.buttontable, 4, 6, menu.buttonDetails)
    Helper.setButtonScript(menu, "next", menu.buttontable, 4, 8, menu.buttonNext)

    -- clear descriptors again
    Helper.releaseDescriptors()
end

PIFuncs.addDeal = function(setup, deal, isfirst, nooftrades)
    local menu = trade_offers_menu

	nooftrades = nooftrades + 1
	if IsSameTrade(deal[1].id, menu.tradeid) then
		menu.highlighttraderow = nooftrades
	end
	local sector = menu.getShipSector()
	local gates, jumps = FindJumpRoute(sector, deal[1].stationsectorid)
	local gates2, jumps2 = FindJumpRoute(deal[1].stationsectorid, deal[2].stationsectorid)
	gates = gates + gates2
	jumps = jumps + jumps2

	local isplayer = deal[1].isplayer
	local isillegal = IsWareIllegalTo(deal[1].ware, "player")
	local textcolor = isplayer and menu.green or (isillegal and menu.orange or menu.white)

	setup:addSimpleRow({
		isfirst and Helper.createButton(Helper.createButtonText(menu.extendedwares[deal[1].ware] and "-" or "+", "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, #menu.tradegroups[deal[1].ware] > 1, 0, 0, 0, Helper.standardTextHeight) or "",
		Helper.createFontString(deal[1].name, false, "left", textcolor.r, textcolor.g, textcolor.b, textcolor.a),
		Helper.createFontString((gates and jumps) and (gates .. menu.strings.gates .. " - " .. jumps .. menu.strings.jumps) or menu.strings.na, false, "right", textcolor.r, textcolor.g, textcolor.b, textcolor.a),
		Helper.createFontString((isplayer and "-" or ConvertMoneyString(RoundTotalTradePrice(deal.amount * deal[1].price), false, true, 0, true)) .. menu.strings.cr, false, "right", textcolor.r, textcolor.g, textcolor.b, textcolor.a),
		Helper.createFontString(ConvertMoneyString(RoundTotalTradePrice(deal.amount * (deal[2].price - (isplayer and 0 or deal[1].price))), false, true, 0, true) .. menu.strings.cr, false, "right", textcolor.r, textcolor.g, textcolor.b, textcolor.a),
		Helper.createFontString(string.format("%.2f", PIFuncs.profitability(deal)), false, "left", textcolor.r, textcolor.g, textcolor.b, textcolor.a),
	}, {deal[1].id, deal[2].id}, {1, 3, 1, 1, 1, 1}, false)

	return nooftrades
end

init()
