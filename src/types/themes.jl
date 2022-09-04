# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   This file contains the types related to themes.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    struct Theme

Defines a theme in the text user interface.

# Fields

- `default::Int`: The default NCurses color for all elements.
- `highlight::Int`: The NCurses color used for highlighted elements.
"""
@with_kw struct Theme
    default::Int = ncurses_color()
    highlight::Int = ncurses_color(A_REVERSE)
end