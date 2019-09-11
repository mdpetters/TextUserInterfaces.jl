# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
#
#   This file contains functions related to windows handling.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export clear_window, create_window, create_window_layout, destroy_window,
       destroy_all_windows, refresh_window, refresh_all_windows, window_print,
       window_println, set_window_title!

"""
function create_window([parent::Union{Nothing,TUI_WINDOW}, ]nlines::Integer, ncols::Integer, begin_y::Integer, begin_x::Integer, id::String = ""; border = true)

Create a window inside the parent window `parent`. If `parent` is `nothing` or
if it is omitted, then the root window will be used as the parent window. The
new window size will be `nlines × ncols` and the origin will be placed at
`(begin_y, begin_x)` coordinate of the parent window. The window ID `id` is used
to identify the new window in the global window list.

# Keyword

* `border`: If `true`, then the window will have a border. (**Default** =
            `true`)
* `border_color`: Color mask that will be used to print the border. See function
                  `ncurses_color`. If negative, then the color will not be
                  changed. (**Default** = -1)
* `title`: The title of the window, which will only be printed if `border` is
           `true`. (**Default** = "")
* `title_color`: Color mask that will be used to print the title. See
                 function `ncurses_color`. If negative, then the color will not
                 be changed. (**Default** = -1)

"""
create_window(nlines::Integer, ncols::Integer, begin_y::Integer,
              begin_x::Integer, id::String = ""; kwargs...) =
    create_window(nothing, nlines, ncols, begin_y, begin_x, id; kwargs...)

function create_window(parent::Union{Nothing,TUI_WINDOW}, nlines::Integer,
                       ncols::Integer, begin_y::Integer, begin_x::Integer,
                       id::String = "";
                       border::Bool = true, border_color::Int = -1,
                       title::String = "", title_color::Int = -1)

    # Check if the TUI has been initialized.
    !tui.init && error("The text user interface was not initialized.")

    # If the user does not specify an `id`, then we choose based on the number
    # of available windows.
    length(id) == 0 && ( id = string(length(tui.wins)) )

    # If the user wants a border, then we create two windows: one to store the
    # borders and other to store the elements.
    if border
        win_border = (parent == nothing) ? newwin(            nlines, ncols, begin_y, begin_x) :
                                           derwin(parent.ptr, nlines, ncols, begin_y, begin_x)
        border_color >= 0 && wattron(win_border, border_color)
        wborder(win_border)
        border_color >= 0 && wattroff(win_border, border_color)

        ptr = derwin(win_border, nlines-2, ncols-2, 1, 1)
        win = TUI_WINDOW(id = id, parent = parent, border = win_border,
                         title = title, ptr = ptr)
        set_window_title!(win, title; title_color = title_color)

        push!(tui.wins, win)
    else
        ptr = (parent == nothing) ? newwin(            nlines, ncols, begin_y, begin_x) :
                                    derwin(parent.ptr, nlines, ncols, begin_y, begin_x)

        # Add the windows to the list.
        win = TUI_WINDOW(id = id, parent = parent, title = title, ptr = ptr)
        push!(tui.wins, win)
    end

    parent != nothing && push!(parent.children, win)

    # Return the pointer to the window.
    return win
end

"""
    function create_window_layout(parent::TUI_WINDOW, vert::Vector{T1}, horz::Vector{T2}) where {T1<:Number, T2<:Number}

Create a window layout inside the parent window `parent`. If it is omitted, then
the root window will be used as parent.

The layout dimensions is obtained from the vectors `vert` and `horz`. They will
be interpreted as a percentage of the total size. For example, if `vert =
[50,25,25]`, then the layout will have three lines in each the first will have
50% of the total size, and the second and third 25%. The same applies for the
`horz` vector for the columns size of the layout.

This function return a matrix with the windows references.

"""
function create_window_layout(vert::Vector{T1}, horz::Vector{T2}) where {T1<:Number, T2<:Number}
    create_window_layout(tui.wins[1], vert, horz)
end

function create_window_layout(parent::TUI_WINDOW, vert::Vector{T1},
                              horz::Vector{T2}) where {T1<:Number, T2<:Number}

    vert  = abs.(vert)
    vert /= sum(vert)
    horz  = abs.(horz)
    horz /= sum(horz)
    nv    = length(vert)
    nh    = length(horz)

    # Get the dimensions of the parent window.
    wsy, wsx = _get_window_dims(parent)

    # Compute the horizontal and vertical sizes of the grid.
    sy = Vector{Int}(undef, nv)
    sx = Vector{Int}(undef, nh)

    acc = 0
    for i = 1:nv
        sy[i]  = i != nv ? round(Int, vert[i]*wsy) : wsy - acc
        acc   += sy[i]
    end

    acc = 0
    for i = 1:nh
        sx[i]  = i != nv ? round(Int, horz[i]*wsx) : wsx - acc
        acc   += sx[i]
    end

    # Create the windows.
    win_grid = Matrix{TUI_WINDOW}(undef,nv,nh)

    beg_x = 0
    beg_y = 0

    for i = 1:nv
        for j = 1:nh
            win_grid[i,j] = create_window(parent, sy[i], sx[j], beg_y, beg_x)
            beg_x += sx[j]
        end

        beg_x  = 0
        beg_y += sy[i]
    end

    return win_grid
end

"""
    function clear_window(win::TUI_WINDOW; clear_type = :all)

Clear the window `win` according the to clearing type in `clear_type`:

* `:all`: Clears the entire window.
* `:to_screen_bottom`: Clears everything from the cursor position to the bottom
                       of the screen.
* `:to_eol`: Clear everything from the cursor position to the end of line.

"""
function clear_window(win::TUI_WINDOW; clear_type = :all)
    if clear_type == :to_screen_bottom
        wclrtobot(win.ptr)
    elseif clear_type == :to_eol
        wclrtoeol(win.ptr)
    else
        wclear(win.ptr)
    end
    nothing
end

"""
    function destroy_window(win::TUI_WINDOW)

Destroy the window `win`.

"""
function destroy_window(win::TUI_WINDOW)
    # Delete the window in the ncurses system.
    delwin(win.ptr)
    win.ptr = Ptr{WINDOW}(0)

    if win.border != C_NULL
        delwin(win.border)
        win.border = Ptr{WINDOW}(0)
    end

    # Remove the window from the global list.
    idx = findall(x->x == win, tui.wins)
    deleteat!(tui.wins, idx)

    nothing
end

"""
    function destroy_all_windows()

Destroy all windows managed by the TUI.

"""
function destroy_all_windows()
    # Notice that we must not delete the root window, which is the first one in
    # the array.
    while length(tui.wins) > 1
        destroy_window(tui.wins[end])
    end
end

"""
    function refresh_window(id::String)

Refresh the window with id `id` and all its parents windows except for the root
window.

"""
function refresh_window(id::String)
    idx = findfirst(x -> x.id == id, tui.wins)
    (idx == nothing) && error("The window id `$id` was not found.")
    refresh_window(tui.wins[idx])
end

"""
    function refresh_window(win::Ptr{WINDOW}; update = true)

Refresh the window `win` and all its parents windows except for the root window.
If `update` is `true`, then `doupdate()` is called and the physical screen is
updated.

"""
function refresh_window(win::TUI_WINDOW; update = true)
    while win != nothing
        wnoutrefresh(win.border)
        wnoutrefresh(win.ptr)
        win = win.parent
    end

    update && doupdate()
end

"""
    function refresh_all_windows()

Refresh all the windows, including the root window.

"""
function refresh_all_windows()
    for win in tui.wins
        refresh_window(win; update = false)
    end

    doupdate()
end

# Functions to draw on the window
# ==============================================================================

"""
    function set_window_title!(win::TUI_WINDOW, title::AbstractString; ...)

Set the title of the window `win` to `title`.

# Keywords

* `title_color`: Color mask that will be used to print the title. See
                 function `ncurses_color`. If negative, then the color will not
                 be changed. (**Default** = -1)

"""
function set_window_title!(win::TUI_WINDOW, title::AbstractString;
                          title_color::Int = -1)
    win.title = title

    if win.border != C_NULL
        # Get the dimensions of the border window.
        win_obj = unsafe_load(win.border)
        wsx     = win_obj.maxx + 1

        # Escape the string to avoid problems.
        title_esc = escape_string(title)

        # Print the title if there is any character.
        length_title_esc = length(title_esc)

        if length_title_esc > 0
            col = div(wsx - length(title_esc), 2)
            title_color > 0 && wattron(win.border, title_color)
            mvwprintw(win.border, 0, col, title_esc)
            title_color > 0 && wattroff(win.border, title_color)
        end
    end

    return nothing
end

"""
    function window_print(win::TUI_WINDOW, [row::Integer,] str::AbstractString; ...)

Print the string `str` at the window `win` in the row `row`. If the `row` is
negative or omitted, then the current row will be used.


# Keywords

* `alignment`: Text alignemnt: `:r` for left, `:c` for center`, and `:l` for
               left. (**Default** = `:l`)
* `pad`: Padding to print the text. (**Default** = 0)

# Remarks

If `str` has multiple lines, then all the lines will be aligned.

"""
window_print(win::TUI_WINDOW, str::AbstractString; kwargs...) =
    window_print(win, -1, str; kwargs...)

function window_print(win::TUI_WINDOW, row::Integer, str::AbstractString;
                      alignment::Symbol = :l, pad::Integer = 0)

    # Check if we need to get the cursor position.
    if row < 0
        row, _ = _get_window_cur_pos(win)
    end

    # Get the dimensions of the window.
    _, wsx = _get_window_dims(win)

    # Split the string in each line.
    tokens = split(str, "\n")

    for line in tokens
        # Check the alignment and print accordingly.
        if alignment == :r
            col = wsx - length(line) - pad
            window_print(win, row, col, line)
        elseif alignment == :c
            col = div(wsx - length(line) + pad, 2)
            window_print(win, row, col, line)
        else
            window_print(win, row, pad, line)
        end

        row += 1
    end

    nothing
end

window_print(win::TUI_WINDOW, row::Integer, col::Integer, str::AbstractString) =
    win.ptr != C_NULL && mvwprintw(win.ptr, row, col, str)

"""
    function window_println(win::TUI_WINDOW, [row::Integer,] str::AbstractString; ...)

Print the string `str` at the window `win` in the row `row` adding a break line
character at the end. If the `row` is negative or omitted, then the current row
will be used.

# Keywords

* `alignment`: Text alignemnt: `:r` for left, `:c` for center`, and `:l` for
               left. (**Default** = `:l`)
* `pad`: Padding to print the text. (**Default** = 0)

# Remarks

If `str` has multiple lines, then all the lines will be aligned.

"""
window_println(win::TUI_WINDOW, str::AbstractString; kwargs...) =
    window_print(win, str * "\n"; kwargs...)

window_println(win::TUI_WINDOW, row::Integer, str::AbstractString; kwargs...) =
    window_print(win, row, str * "\n"; kwargs...)

################################################################################
#                                     API
################################################################################

# Focus manager
# ==============================================================================


"""
    function accept_focus(win::TUI_WINDOW)

Command executed when window `win` must state whether or not it accepts the
focus. If the focus is accepted, then this function returns `true`. Otherwise,
it returns `false`.

"""
function accept_focus(win::TUI_WINDOW)
    # Search for a child that can accept the focus.
    for i = 1:length(win.children)
        if accept_focus(win.children[i])
            win.focus_id  = i
            win.focus_ptr = win.children[i]
            win.has_focus = true
            win.on_focus_acquired(win)
            return true
        end
    end

    return false
end

"""
    function process_focus(win::TUI_WINDOW, k::Keystroke)

Process the actions when the window `win` is in focus and the keystroke `k` was
issued by the user.

"""
function process_focus(win::TUI_WINDOW, k::Keystroke)
    num_children = length(win.children)
    num_children == 0 && return false

    if win.focus_ptr != nothing
        return process_focus(win.focus_ptr, k)
    else
        return false
    end
end

"""
    function release_focus(win::TUI_WINDOW)

Release the focus from the window `win`.

"""
function release_focus(win::TUI_WINDOW)
    if win.focus_ptr != nothing
        release_focus(win.focus_ptr)
    end

    win.focus_id  = 1
    win.focus_ptr = nothing
    win.has_focus = false

    win.on_focus_released(win)

    return nothing
end

"""
    function request_focus_change(win::TUI_WINDOW)

Request to change the focus of the children elements in window `win`. If all the
children has already been cycled, then this function returns `true` to state
that the focus should be released from the window.

"""
function request_focus_change(win::TUI_WINDOW)
    # If we have not child, than just allow focus change.
    num_children = length(win.children)
    num_children == 0 && return true

    # Otherwise, move to the next child until hit the last one.
    win.focus_ptr != nothing && release_focus(win.focus_ptr)

    # Loop the children to find one that can accept the focus.
    for i = win.focus_id+1:num_children
        if accept_focus(win.children[i])
            win.focus_id  = i
            win.focus_ptr = win.children[i]
            win.has_focus = true

            return false
        end
    end

    release_focus(win)

    return true
end

################################################################################
#                              Private Functions
################################################################################

"""
    function _get_window_dims(win::TUI_WINDOW)

Get the dimensions of the window `win` and return it on a tuple `(dim_y,dim_x)`.
If the window is not initialized, then this function returns `(-1,-1)`.

"""
function _get_window_dims(win::TUI_WINDOW)
    if win.ptr != C_NULL
        win_obj = unsafe_load(win.ptr)
        wsx     = win_obj.maxx
        wsy     = win_obj.maxy

        return wsy + 1, wsx + 1
    else
        return -1, -1
    end
end

"""
    function _get_window_cur_pos(win::TUI_WINDOW)

Get the cursor position of the window `win` and return it on a tuple
`(cur_y,cur_x)`.  If the window is not initialized, then this function returns
`(-1,-1)`.

"""
function _get_window_cur_pos(win::TUI_WINDOW)
    if win.ptr != C_NULL
        win_obj = unsafe_load(win.ptr)
        cury    = win_obj.cury
        curx    = win_obj.curx

        return cury, curx
    else
        return -1, -1
    end
end
