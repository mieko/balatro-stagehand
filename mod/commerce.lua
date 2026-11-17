local Bridge = require('balatro_stagehand.bridge')
local Controls = require('balatro_stagehand.controls')
local Commerce = {}
Commerce.__index = Commerce

local function error_text(problem)
    return type(problem) == 'table' and problem.message or tostring(problem)
end

function Commerce.new(state)
    return setmetatable({ state = state }, Commerce)
end

function Commerce:begin(items, human_delay_ms)
    if type(items) ~= 'table' or #items == 0 or #items > 32 then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Supply 1–32 observed shop offers')
    end

    return { items = items, index = 1, results = Bridge.array(), humanDelayMs = human_delay_ms }
end

function Commerce:remaining(job)
    local remaining = Bridge.array()

    local first = job.index + (job.step and job.step.phase == 'buying' and 1 or 0)

    for i = first, #job.items do
        remaining[#remaining + 1] = job.items[i]
    end

    return remaining
end

function Commerce:attempted(job)
    if job.step and job.step.phase == 'buying' then
        return { offer = job.step.offer, status = 'unconfirmed' }
    end
end

function Commerce:select(job)
    local requested = job.items[job.index]
    local ref = type(requested) == 'table' and requested.ref or requested
    local card = self.state:find_card(ref)

    if
        card.area ~= G.shop_jokers
        and card.area ~= G.shop_vouchers
        and card.area ~= G.shop_booster
    then
        Bridge.fail(Bridge.INVALID_PARAMS, 'This card is not a current shop offer')
    end

    job.step = { card = card, area = card.area, offer = self.state:card(card), phase = 'selected' }

    if not card.highlighted then
        card:click()
    end
end

function Commerce:activate(job)
    local card = job.step.card
    local node = card.children.buy_button and card.children.buy_button.UIRoot

    if not node then
        return
    end

    Controls.refresh(node)

    if not node.config.button then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Native purchase is unavailable at this price')
    end

    if node.disable_button or node.under_overlay or not node.states.visible then
        return
    end

    if node.config.button == 'buy_from_shop' and not G.FUNCS.check_for_buy_space(card) then
        job.blocker = { kind = 'inventory_full', offer = job.step.offer }

        return 'choice_required'
    end

    Controls.validate_click(node, node.config.button)
    job.step.phase = 'buying'
    node:click()
end

local function base_events_finished()
    for _, event in ipairs(G.E_MANAGER.queues.base) do
        if event.blocking and not event.complete then
            return false
        end
    end

    return true
end

function Commerce:advance(job)
    if not job.step then
        if G.STATE ~= G.STATES.SHOP then
            return 'choice_required'
        end

        if Controls.wait_delay(job, job.humanDelayMs) then
            return
        end

        self:select(job)
        return
    end

    if job.step.phase == 'selected' then
        return self:activate(job)
    end

    local step = job.step
    local pack = self.state:is_pack()

    if not pack and (step.card.area == step.area or not base_events_finished()) then
        return
    end

    local result = { offer = step.offer, status = 'completed', state = self.state:read() }
    job.results[#job.results + 1] = result
    job.index = job.index + 1
    job.step = nil
    job.activate_at = nil

    if pack or G.OVERLAY_MENU or G.OVERLAY_TUTORIAL then
        return 'choice_required'
    end

    if job.index > #job.items then
        return 'completed'
    end
end

function Commerce:update(job)
    local ok, status = pcall(self.advance, self, job)

    if not ok then
        return 'failed', error_text(status)
    end

    return status
end

return Commerce
