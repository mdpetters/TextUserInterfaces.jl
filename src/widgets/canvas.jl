# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Widget: Canvas.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export WidgetCanvas

################################################################################
#                                     Type
################################################################################

@widget mutable struct WidgetCanvas
    chars::Matrix{String}
    colors::Matrix{Int}

    # Signals
    # ==========================================================================
    @signal return_pressed
end

################################################################################
#                                     API
################################################################################

function create_widget(
    ::Val{:canvas},
    layout::ObjectLayout;
    num_columns = 1,
    num_rows = 1
)

    # Check if all positioning is defined and, if not, try to help by
    # automatically defining the height and/or width.
    horizontal = _process_horizontal_info(layout)
    vertical   = _process_vertical_info(layout)

    vertical   == :unknown && (layout.height = num_rows)
    horizontal == :unknown && (layout.width  = num_columns)

    # Create the matrices that will hold the characters and the colors.
    chars  = [" " for i = 1:num_rows, j = 1:num_columns]
    colors = zeros(Int, num_rows, num_columns)

    # Create the widget.
    widget = WidgetCanvas(
        layout = layout,
        chars  = chars,
        colors = colors
    )

    @connect_signal widget key_pressed process_keystroke

    @log info "create_widget" """
    Canvas created:
        Reference = $(obj_to_ptr(widget))
        Num. cols = $num_columns
        Num. rows = $num_rows"""

    # Return the created widget.
    return widget
end

function redraw(widget::WidgetCanvas)
    @unpack buffer, chars, colors = widget

    wclear(buffer)

    N,M = size(chars)

    height = get_height(widget)
    width  = get_width(widget)

    @inbounds for i = 1:N
        i > height+1 && break

        for j = 1:M
            j > width+1 && break

            color_ij = colors[i,j]

            color_ij > 0 && wattron(buffer, color_ij)
            mvwprintw(buffer, i-1, j-1, first(chars[i,j],1))
            color_ij > 0 && wattroff(buffer, color_ij)
        end
    end

    return nothing
end

################################################################################
#                                   Helpers
################################################################################

@create_widget_helper canvas
