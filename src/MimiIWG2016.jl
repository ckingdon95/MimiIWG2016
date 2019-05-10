using Mimi

# module MimiIWG2016

using Mimi
using MimiDICE2010
using ExcelReaders
using StatsBase
using Interpolations
using Dates
using DelimitedFiles

# export get_model #, get_SCC, run_scc_mcs

# General constants and functions
include("core/constants.jl")
# include("core/utils.jl)

# IWG modified components
# Mimi.load_comps(joinpath(@__DIR__, "components"))     # Need to fix this function in Mimi, then won't need to include each component file separately
include("components/IWG_DICE_co2cycle.jl")
include("components/IWG_DICE_radiativeforcing.jl")
include("components/IWG_DICE_climatedynamics.jl")
include("components/IWG_DICE_neteconomy.jl")

# Main models and functions
include("core/DICE_helper.jl")
# include("core/FUND_helper.jl")
# include("core/PAGE_helper.jl")
include("core/main.jl")

# Monte carlo support
include("montecarlo/DICE_mcs.jl")
# include("montecarlo/FUND_mcs.jl")
# include("montecarlo/PAGE_mcs.jl")
include("montecarlo/run_scc_mcs.jl")


# end