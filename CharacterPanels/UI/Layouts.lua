local _, AJ = ...

-- The page sizes the journal can open in. A tab names one of them (see
-- Sections.lua), so choosing a tab's size is choosing its name there.
--
-- Each size is a window of a given width, with one of three layouts:
--   single  one centred page, as the Fishing Trip has
--   book    two pages of the same size, side by side
--   split   two pages of uneven size: the left page is `left` wide, and the
--           right page is what is left of the window
--
-- To add a size, add a line to UI.Layouts. Nothing else needs to change.

local UI = AJ.UI
local W = UI.Widgets
local C = UI.Components

local BOOK_WIDTH = 670      -- the two-page book
local BOOK_INSET = 6        -- the book's inset from the frame (Components)
local PAGE_INSET = 14       -- a single page's inset from the frame (Components)

local SINGLE_WIDTH = W.SINGLE_PAGE_WIDTH               -- 448 modern, 484 classic
local SINGLE_PAPER = SINGLE_WIDTH - 2 * PAGE_INSET     -- the paper of a single page: 420 modern
local BOOK_PAGE = math.floor((BOOK_WIDTH - 2 * BOOK_INSET) / 2)   -- one page of the book: 329

UI.Layouts = {
    single = {
        kind = "single",
        width = SINGLE_WIDTH,
    },
    book = {
        kind = "book",
        width = BOOK_WIDTH,
    },
    -- Double a single page wide: the spellbook.
    wideBook = {
        kind = "book",
        width = 2 * SINGLE_WIDTH,
    },
    -- Halfway between the single page and the book, with a book page on the left.
    uneven = {
        kind = "split",
        width = math.floor((SINGLE_WIDTH + BOOK_WIDTH) / 2 + 0.5),
        left = BOOK_PAGE,
    },
    -- Between the single page and the book, with a full single page on the left
    -- and a short page on the right.
    singleLeft = {
        kind = "split",
        width = 713,
        left = 414,
    },
	singleRight = {
        kind = "split",
        width = 630,
        left = 280,
    },
}

-- Creates the window for a layout. Returns the frame and its pages: one page
-- for "single", otherwise a left and a right page.
function UI:CreateLayoutWindow(name, frameName, title)
    local layout = UI.Layouts[name]
    if not layout then
        error("unknown page layout '" .. tostring(name) .. "'", 2)
    end

    local frame = C.CreateWindow(
        frameName, title, layout.width, 508, 16, -104,
        W.Sounds.SPELLBOOK_OPEN, W.Sounds.SPELLBOOK_CLOSE
    )
    frame:Hide()

    if layout.kind == "single" then
        return frame, C.CreatePage(frame)
    elseif layout.kind == "book" then
        local _, left, right = C.CreateBook(frame)
        return frame, left, right
    end

    local _, left, right = C.CreateSplitBook(frame, layout.left)
    return frame, left, right
end

-- The width of each page a layout has, for laying out text. A single page
-- gives its paper and no right page.
function UI:PageWidths(name)
    local layout = UI.Layouts[name]
    if not layout then
        error("unknown page layout '" .. tostring(name) .. "'", 2)
    end

    if layout.kind == "single" then return SINGLE_PAPER, nil end
    if layout.kind == "book" then
        local page = math.floor((layout.width - 2 * BOOK_INSET) / 2)
        return page, page
    end
    return layout.left, layout.width - 2 * BOOK_INSET - layout.left
end