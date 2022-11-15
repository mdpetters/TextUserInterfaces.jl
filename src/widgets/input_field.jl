# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Widget: Input field.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export WidgetInputField

################################################################################
#                                  Structure
################################################################################

@widget mutable struct WidgetInputField
    # Data array that contains the input to the field.
    data::Vector{Char} = Char[]

    # Maximum allowed data size.
    max_data_size::Int = 0

    # Field usable size in screen.
    size::Int = 0

    # State of the input field.
    curx::Int = 1
    vbegx::Int = 1
    vcurx::Int = 1

    # Internal buffer to avoid output flickering when drawing.
    internal_buffer::Ptr{WINDOW} = Ptr{WINDOW}(0)

    # Styling
    # ==========================================================================

    style::Symbol = :simple
end

# Conversion dictionary between style and height.
const _INPUT_FIELD_STYLE_HEIGHT = Dict(
    :boxed  => 3,
    :simple => 1,
    :none   => 1
)

################################################################################
#                                  Object API
################################################################################

function destroy!(widget::WidgetInputField)
    @unpack internal_buffer = widget

    # We must destroy the internal buffer.
    if widget.internal_buffer !== Ptr{WINDOW}(0)
        delwin(internal_buffer)
        widget.internal_buffer = Ptr{WINDOW}(0)
    end

    # Call the general function to destroy a widget.
    return invoke(destroy!, Tuple{Widget}, widget)
end

function update_layout!(widget::WidgetInputField; force::Bool = false)
    if invoke(update_layout!, Tuple{Widget}, widget; force = force)
        @unpack curx, data, internal_buffer, height, style, vbegx, vcurx = widget
        @unpack width = widget
        # Since the widget could have changed its size, we need to compute the
        # usable size to display the text.
        size = if style === :simple
            width - 2
        elseif style === :boxed
            width - 2
        else
            width
        end

        num_chars = length(data)

        # Make the position of the physical cursor valid.
        if curx > size
            curx  = max(size, 1)
            vbegx = vcurx - size + 1
        end

        # Recreate the internal buffer considering the new size.
        internal_buffer !== Ptr{WINDOW}(0) && delwin(internal_buffer)
        internal_buffer = newwin(height, width, 0, 0)

        @log INFO "AQUI" "$height, $width"
        @pack! widget = internal_buffer, size, curx, vbegx

        return true
    else
        return false
    end
end

################################################################################
#                                  Widget API
################################################################################

can_accept_focus(::WidgetInputField) = true

function create_widget(
    ::Val{:input_field},
    layout::ObjectLayout;
    max_data_size::Int = 0,
    style::Symbol = :simple,
    theme::Theme = tui.default_theme
)
    # Check arguments.
    if !haskey(_INPUT_FIELD_STYLE_HEIGHT, style)
        @log WARNING "create_widget" """
        The input field style :$style is not known.
        The style :simple will be used."""
        style = :simple
    end

    # Create the widget.
    input_field = WidgetInputField(
        id               = reserve_object_id(),
        layout           = layout,
        max_data_size    = max_data_size,
        style            = style,
        theme            = theme,
        horizontal_hints = (; width = 30),
        vertical_hints   = (; height = _INPUT_FIELD_STYLE_HEIGHT[style])
    )

    @log INFO "create_widget" """
    WidgetInputField created:
        ID             = $(input_field.id)
        Max. data size = $(max_data_size)
        Style          = $(style)"""

    # Return the created container.
    return input_field
end

function process_keystroke!(widget::WidgetInputField, k::Keystroke)
    # In this case, if we have a global command, we must not process the
    # keystroke.
    cmd = check_global_command(k)
    isnothing(cmd) || return :keystorke_not_processed

    # Handle the input.
    if _handle_input!(widget, k)
        # Update the cursor position.
        _update_cursor(widget)

        return :keystroke_processed
    else
        return :keystroke_not_processed
    end
end

function request_focus!(widget::WidgetInputField)
    # When accepting focus we must update the cursor position so that it can be
    # positioned in the position it was when the focus was released.
    _update_cursor(widget)
    request_update!(widget)
    return true
end

request_cursor(::WidgetInputField) = true

function redraw!(widget::WidgetInputField)
    @unpack buffer, data, height, internal_buffer, size, style, vbegx = widget
    @unpack theme, width = widget

    if internal_buffer === Ptr{WINDOW}(0)
        @log ERROR "redraw!" """
        Internal buffer of input field ($(widget.id)) was not created."""
        return nothing
    end

    # Clear the internal buffer.
    wclear(internal_buffer)

    # Check which color to apply to the widget
    c = has_focus(widget) ? theme.input_field_focused : theme.default

    # Convert the data to string.
    if isempty(data)
        str = ""
    else
        aux = clamp(vbegx + size - 1, 1, length(data))
        str = String(@view data[vbegx:aux])
    end

    if style === :simple
        mvwprintw(internal_buffer, 0, 0, "[")

        @ncolor c internal_buffer begin
            mvwprintw(internal_buffer, 0, 1, str)
        end

        mvwprintw(internal_buffer, 0, size + 1, "]")

    elseif style === :boxed
        wborder(internal_buffer)

        @ncolor c internal_buffer begin
            mvwprintw(internal_buffer, 1, 1, str)
        end

    else
        @ncolor c internal_buffer begin
            mvwprintw(internal_buffer, 0, 0, str)
        end
    end

    # Copy the internal buffer to the output buffer.
    copywin(internal_buffer, buffer, 0, 0, 0, 0, height - 1, width - 1, 0)

    # We need to update the cursor after every redraw.
    _update_cursor(widget)

    return nothing
end

################################################################################
#                                   Helpers
################################################################################

@create_widget_helper input_field

################################################################################
#                              Private functions
################################################################################

# Handle the input `k` to the input field `widget`.
function _handle_input!(widget::WidgetInputField, k::Keystroke)
    @unpack data, max_data_size, size = widget
    @unpack curx, vbegx, vcurx = widget

    # Number of characters in the data array.
    num_chars = length(data)

    # Flag to indicate if the field must be updated.
    update = false

    # Get the action.
    action = _get_input_field_action(k)

    # Translate the action and update the field state.
    if action === :add_character
        # Check if we can add a new character.
        if (max_data_size <= 0) || (num_chars < max_data_size)
            c = k.value |> first
            insert!(data, vcurx, c)

            vcurx += 1
            curx  += textwidth(c)

            if curx > size
                vbegx += curx - size
                curx   = size
            end

            update = true
        end

    elseif action === :delete_forward_character
        if vcurx <= num_chars
            deleteat!(data, vcurx)
            update = true
        end

    elseif action === :delete_previous_character
        if vcurx > 1
            c = data[vcurx - 1]
            deleteat!(data, vcurx - 1)
            vcurx -= 1

            if vbegx > 1
                vbegx -= 1
            elseif curx > 1
                curx -= 1
            end

            update = true
        end

    elseif action === :goto_beginning
        curx   = 1
        vbegx  = 1
        vcurx  = 1
        update = true

    elseif action === :goto_end
        curx   = min(num_chars + 1, size)
        vcurx  = num_chars + 1
        vbegx  = max(vcurx - size + 1, 1)
        update = true

    elseif action === :move_cursor_to_left
        if vcurx > 1
            curx  -= 1
            vcurx -= 1

            if curx < 1
                curx = 1
                vbegx = max(vbegx - 1, 1)
            end

            update = true
        end

    elseif action === :move_cursor_to_right
        if vcurx <= num_chars
            curx  += 1
            vcurx += 1

            if curx > size
                vbegx += curx - size
                curx   = size
            end

            update = true
        end
    end

    update && request_update!(widget)

    @pack! widget = curx, vbegx, vcurx

    return true
end

# Obtain the action that the user wants by hitting the keystroke `k`.
function _get_input_field_action(k::Keystroke)
    action = :none

    if k.ktype === :left
        action = :move_cursor_to_left

    elseif k.ktype === :right
        action = :move_cursor_to_right

    elseif k.ktype === :home
        action = :goto_beginning

    elseif k.ktype === :end
        action = :goto_end

    elseif k.ktype === :backspace
        action = :delete_previous_character

    elseif k.ktype === :delete
        action = :delete_forward_character

    elseif (k.ktype === :char) || (k.ktype === :utf8)
        action = :add_character
    end

    return action
end

# Update the physical cursor in the `widget`.
function _update_cursor(widget::WidgetInputField)
    @unpack buffer, curx, style = widget

    # Move the physical cursor to the correct position considering the border if
    # present.
    #
    # NOTE: The initial position here starts at 1, but in NCurses it starts in
    # 0.

    if style === :simple
        px = curx
        py = 0

    elseif style === :boxed
        px = curx
        py = 1

    else
        px = curx - 1
        py = 0

    end

    wmove(buffer, py, px)

    return nothing
end
