-- =========================================================
-- SEPGP Forever - Item Tooltip
-- =========================================================

SEPGP = SEPGP or {}

print("SEPGP: Tooltip module loaded.")


-- =========================================================
-- Helpers
-- =========================================================

local function GetTooltipItemLink(tooltip, data)
    -- Preferred method for a displayed item.
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local _, itemLink =
            TooltipUtil.GetDisplayedItem(tooltip)

        if itemLink then
            return itemLink
        end
    end

    -- Inspect/comparison/AH tooltips often give us a GUID.
    if data
        and data.guid
        and C_Item.GetItemLinkByGUID then

        local itemLink =
            C_Item.GetItemLinkByGUID(data.guid)

        if itemLink then
            return itemLink
        end
    end

    -- Some tooltip types provide the hyperlink directly.
    if data and data.hyperlink then
        return data.hyperlink
    end

    -- Auction House tooltips may only provide an item ID.
    if data and data.id then
        local _, itemLink =
            C_Item.GetItemInfo(data.id)

        if itemLink then
            return itemLink
        end
    end

    return nil
end


-- =========================================================
-- Tooltip display
-- =========================================================

local function AddGPToTooltip(tooltip, data)
    local recipient = SEPGP.DFB and SEPGP.DFB.GetAwardRecipient(data and data.guid)
    if recipient then
        tooltip:AddLine("SEPGP: Awarded to " .. recipient, 0.2, 1.0, 0.2)
        tooltip:Show()
    end
    local itemLink =
        GetTooltipItemLink(tooltip, data)

    if not itemLink then
        print(
            "SEPGP tooltip: no item link",
            "id:",
            data and tostring(data.id) or "nil",
            "guid:",
            data and tostring(data.guid) or "nil"
        )
        return
    end

    local gp, info =
        SEPGP.GP.GetItemGP(itemLink)

    if not gp then
        print(
            "SEPGP tooltip: no GP for",
            itemLink,
            tostring(info)
        )
        return
    end

    tooltip:AddLine(
        string.format(
            "SEPGP GP: %d",
            gp
        ),
        1.0, 0.82, 0.0
    )

    -- Temporary debugging line.
    tooltip:AddLine(
        string.format(
            "iLvl %d / rarity %d / slot %s / modifier %.2f",
            info.itemLevel,
            info.rarity,
            tostring(info.equipLoc),
            info.slotModifier
        ),
        0.7, 0.7, 0.7
    )

    tooltip:Show()
end


-- =========================================================
-- Registration
-- =========================================================

TooltipDataProcessor.AddTooltipPostCall(
    Enum.TooltipDataType.Item,
    AddGPToTooltip
)
