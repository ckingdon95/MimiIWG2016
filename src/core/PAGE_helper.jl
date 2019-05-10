"""
Returns the IWG version of the PAGE 2009 model for the specified scenario.
"""
function get_page_model(scenario_name::String)

    # Get original version of PAGE
    m = MimiPAGE2009.getpage()

    # Reset the time index for the IWG:
    set_dimension!(m, :time, page_years)

    # Replace modified components
    replace_comp!(m, IWG_PAGE_ClimateTemperature, :ClimateTemperature)

    # Load all of the IWG parameters from excel that aren't scenario specific
    iwg_params = load_page_iwg_params()  
    set_param!(m, :ClimateTemperature, :sens_climatesensitivity, iwg_params["sens_climatesensitivity"])

    # Update y_year_0 and y_year parameters used by components
    update_param!(m, :y_year_0, 2000)
    update_param!(m, :y_year, page_years, update_timesteps = true)

    # Update all parameter values (and their timesteps) from the iwg parameters
    update_params!(m, iwg_params, update_timesteps = true)

    # Add the scenario choice component and load all the scenario parameter values
    add_comp!(m, IWG_PAGE_ScenarioChoice, :ScenarioChoice; before = :co2emissions)
    set_dimension!(m, :scenarios, length(scenario_names))
    set_page_scenario_params!(m)
    
    # Set the scenario number if a scenario_name was provided
    scenario_num = findfirst(isequal(scenario_name), scenario_names)
    scenario_num == nothing ? error("Unknown scenario name $scenario_name. Must provide one of the following scenario names to get_model: $(join(scenario_names, ", "))") : nothing
    set_param!(m, :ScenarioChoice, :scenario_num, scenario_num)

    return m
end

"""
set_scenario_params!(m::Model; comp_name::Symbol = :IWGScenarioChoice, connect::Boolean = true)
    m: a Mimi model with and IWGScenarioChoice component
    comp_name: the name of the IWGScenarioChoice component in the model, defaults to :IWGScenarioChoice
    connect: whether or not to connect the outgoing variables to the other components who depend on them as parameter values
"""
function set_page_scenario_params!(m::Model; comp_name::Symbol = :ScenarioChoice, connect::Bool = true)
    params_dict = Dict{String, Array}([k=>[] for k in page_scenario_specific_params])

    # add an array of each scenario's value to the dictionary
    for (i, scenario) in enumerate(scenario_names)
        params = load_page_scenario_params(scenario)
        for p in page_scenario_specific_params
            push!(params_dict[p], params[p])
        end
    end

    # reshape each array of values into one array for each param, then set that value in the model
    for (k, v) in params_dict
        _size = size(v[1])
        param = zeros(_size..., 5)
        for i in 1:5
            param[[1:l for l in _size]..., i] = v[i]
        end
        set_param!(m, comp_name, Symbol("$(k)_all"), param)
    end

    if connect 
        connect_param!(m, :GDP=>:gdp_0, comp_name=>:gdp_0)
        connect_all!(m, [:GDP, :EquityWeighting], comp_name=>:grw_gdpgrowthrate)
        connect_all!(m, [:Discontinuity, :MarketDamages, :NonMarketDamages, :SLRDamages], comp_name=>:GDP_per_cap_focus_0_FocusRegionEU)
        connect_all!(m, [:GDP, :Population], comp_name=>:pop0_initpopulation)
        connect_all!(m, [:EquityWeighting, :Population], comp_name=>:popgrw_populationgrowth)
        connect_all!(m, [:co2emissions=>:e0_baselineCO2emissions, :AbatementCostsCO2=>:e0_baselineemissions, :AbatementCostParametersCO2=>:e0_baselineemissions], comp_name=>:e0_baselineCO2emissions)
        connect_param!(m, :co2cycle=>:e0_globalCO2emissions, comp_name=>:e0_globalCO2emissions)
        connect_all!(m, [:co2emissions=>:er_CO2emissionsgrowth, :AbatementCostsCO2=>:er_emissionsgrowth], comp_name=>:er_CO2emissionsgrowth)
        connect_param!(m, :co2forcing=>:f0_CO2baseforcing, comp_name=>:f0_CO2baseforcing)
        connect_param!(m, :TotalForcing=>:exf_excessforcing, comp_name=>:exf_excessforcing)
    end
end

"""
    Returns a dictionary of the scenario-specific parameter values for the specified scenario.
        (also possible TODO: should I just make data files for all of these instead of using Excel?)
"""
function load_page_scenario_params(scenario_name::String)

    # Build a dictionary of values to return
    p = Dict{Any, Any}()

    # Specify the scenario parameter file path
    fn = joinpath(iwg_page_datadir, "PAGE09 v1.7 SCCO2 ($(page_scenario_convert[scenario_name]), for 2013 SCC technical update - Input files).xlsx")
    f = openxl(fn)

    p["pop0_initpopulation"] = dropdims(convert(Array{Float64}, readxl(f, "Base data!E24:E31")), dims=2)    # Population base year
    p["popgrw_populationgrowth"]= convert(Array{Float64}, readxl(f, "Base data!C47:L54")')                  # Population growth rate
    p["gdp_0"] = dropdims(convert(Array{Float64}, readxl(f, "Base data!D24:D31")), dims=2)                  # GDP base year
    p["grw_gdpgrowthrate"] = convert(Array{Float64}, readxl(f, "Base data!C36:L43")')                       # GDP growth rate
    p["GDP_per_cap_focus_0_FocusRegionEU"] = p["gdp_0"][1] / p["pop0_initpopulation"][1]                    # EU initial income
    p["e0_baselineCO2emissions"] = convert(Array{Float64}, readxl(f, "Base data!F24:F31"))[:, 1]            # initial CO2 emissions
    p["e0_globalCO2emissions"] = sum(p["e0_baselineCO2emissions"])                                          # sum to get global
    p["f0_CO2baseforcing"] = readxl(f, "Base data!B21:B21")[1]                                              # CO2 base forcing
    p["exf_excessforcing"] = convert(Array{Float64}, readxl(f, "Policy A!B50:K50")')[:, 1]                  # Excess forcing
    p["er_CO2emissionsgrowth"] = convert(Array{Float64}, readxl(f, "Policy A!B5:K12")')                     # CO2 emissions growth

    return p
end

"""
    Returns a dicitonary of all of the necessary parameters that are the same for all IWG scenarios.
"""
function load_page_iwg_params()

    # Build a dictionary of values to return
    p = Dict{Any, Any}()

    # Specify the scenario parameter file path
    fn = joinpath(iwg_page_input_file)
    f = openxl(fn)

    #------------------------
    # 1. BASE DATA sheet
    #------------------------

    # Socioeconomics
    p["lat_latitude"] = convert(Array{Float64}, readxl(f, "Base data!M24:M31"))[:, 1]
    # the rest of the Socioeconomics parameters are scenario-specific

    # Initial emissions (all but CO2)
    p["e0_baselineCH4emissions"] = convert(Array{Float64}, readxl(f, "Base data!G24:G31"))[:, 1]    # initial CH4 emissions
    p["AbatementCostsCH4_e0_baselineemissions"] = p["e0_baselineCH4emissions"]                      # same initial values, but different parameter name in the AbatementCosts component
    p["AbatementCostParametersCH4_e0_baselineemissions"] = p["e0_baselineCH4emissions"]             # same initial values, but different parameter name in the AbatementCostParameters component
    p["e_0globalCH4emissions"] = sum(p["e0_baselineCH4emissions"])                                  # sum to get global
    p["e0_baselineN2Oemissions"] = convert(Array{Float64}, readxl(f, "Base data!H24:H31"))[:, 1]    # initial N2O emissions
    p["AbatementCostsN2O_e0_baselineemissions"] = p["e0_baselineN2Oemissions"]                      # same initial values, but different parameter name in the AbatementCosts component
    p["AbatementCostParametersN2O_e0_baselineemissions"] = p["e0_baselineN2Oemissions"]             # same initial values, but different parameter name in the AbatementCostParameters component
    p["e_0globalN2Oemissions"] = sum(p["e0_baselineN2Oemissions"])                                  # sum to get global
    p["e0_baselineLGemissions"] = convert(Array{Float64}, readxl(f, "Base data!I24:I31"))[:, 1]     # initial Linear Gas emissions
    p["AbatementCostsLin_e0_baselineemissions"] = p["e0_baselineLGemissions"]                       # same initial values, but different parameter name in the AbatementCosts component
    p["AbatementCostParametersLin_e0_baselineemissions"] = p["e0_baselineLGemissions"]              # same initial values, but different parameter name in the AbatementCostParameters component
    p["e_0globalLGemissions"] = sum(p["e0_baselineLGemissions"])                                    # sum to get global
    p["se0_sulphateemissionsbase"] = convert(Array{Float64}, readxl(f, "Base data!J24:J31"))[:, 1]  # initial Sulphate emissions
    p["nf_naturalsfx"] = convert(Array{Float64}, readxl(f, "Base data!K24:K31"))[:, 1]              # natural Sulphate emissions

    p["rtl_0_realizedtemperature"] = convert(Array{Float64}, readxl(f, "Base data!L24:L31"))[:, 1]  # RTL0

    # Forcing slopes and bases (excludes CO2 base forcing)
    p["fslope_CO2forcingslope"] = readxl(f, "Base data!B14:B14")[1]     # CO2 forcing slope
    p["fslope_CH4forcingslope"] = readxl(f, "Base data!C14:C14")[1]     # CH4 forcing slope
    p["fslope_N2Oforcingslope"] = readxl(f, "Base data!D14:D14")[1]     # CO2 forcing slope
    p["fslope_LGforcingslope"] = readxl(f, "Base data!E14:E14")[1]      # LG forcing slope
    p["f0_CH4baseforcing"] = readxl(f, "Base data!C21:C21")[1]          # CH4 base forcing
    p["f0_N2Obaseforcing"] = readxl(f, "Base data!D21:D21")[1]          # CO2 base forcing
    p["f0_LGforcingbase"] = readxl(f, "Base data!E21:E21")[1]           # LG base forcing

    # stimulation, air fractions, and halflifes
    p["stim_CH4emissionfeedback"] = readxl(f, "Base data!C15:C15")[1] 
    p["air_CH4fractioninatm"] = readxl(f, "Base data!C17:C17")[1] 
    p["res_CH4atmlifetime"] = readxl(f, "Base data!C18:C18")[1] 
    p["stim_N2Oemissionfeedback"] = readxl(f, "Base data!D15:D15")[1] 
    p["air_N2Ofractioninatm"] = readxl(f, "Base data!D17:D17")[1] 
    p["res_N2Oatmlifetime"] = readxl(f, "Base data!D18:D18")[1] 
    p["stim_LGemissionfeedback"] = readxl(f, "Base data!E15:E15")[1] 
    p["air_LGfractioninatm"] = readxl(f, "Base data!E17:E17")[1] 
    p["res_LGatmlifetime"] = readxl(f, "Base data!E18:E18")[1] 

    # concentrations
    p["stay_fractionCO2emissionsinatm"] = readxl(f, "Base data!B16:B16")[1] / 100 # percent of CO2 emissions that stay in the air
    p["c0_CO2concbaseyr"] = readxl(f, "Base data!B19:B19")[1]               # CO2 base year concentration
    p["c0_baseCO2conc"] = p["c0_CO2concbaseyr"]
    p["ce_0_basecumCO2emissions"] = readxl(f, "Base data!B20:B20")[1]       # CO2 cumulative emissions
    p["c0_CH4concbaseyr"] = readxl(f, "Base data!C19:C19")[1]                 # CH4 base year concentration
    p["c0_baseCH4conc"] = p["c0_CH4concbaseyr"]
    p["c0_N2Oconcbaseyr"] = readxl(f, "Base data!D19:D19")[1]                 # N2O base year concentration
    p["c0_baseN2Oconc"] = p["c0_N2Oconcbaseyr"]
    p["c0_LGconcbaseyr"] = readxl(f, "Base data!E19:E19")[1]                # LG base year concentration

    # BAU emissions
    p["AbatementCostParametersCO2_bau_businessasusualemissions"] = convert(Array{Float64}, readxl(f, "Base data!C68:L75")')
    p["AbatementCostParametersCH4_bau_businessasusualemissions"] = convert(Array{Float64}, readxl(f, "Base data!C77:L84")')
    p["AbatementCostParametersN2O_bau_businessasusualemissions"] = convert(Array{Float64}, readxl(f, "Base data!C86:L93")')
    p["AbatementCostParametersLin_bau_businessasusualemissions"] = convert(Array{Float64}, readxl(f, "Base data!C95:L102")')

    #elasticity of utility
    p["emuc_utilityconvexity"] = readxl(f, "Base data!B10:B10")[1]

    #pure rate of time preference
    p["ptp_timepreference"] = readxl(f, "Base data!B8:B8")[1]

    #------------------------
    # 2. LIBRARY DATA sheet
    #------------------------

    p["sens_climatesensitivity"] = readxl(f, "Library data!C18:C18")[1]  # Climate sensitivity
    
    # p["cutbacks_at_neg_cost_grw"] = readxl(f, "Library data!C123:C123")[1]    # cutbacks at negative cost growth rate (??)
    # p["max_cutbacks_grw"] = readxl(f, "Library data!C125:C125")[1]        # Maximum cutbacks growth rate
    # p["most_neg_grw"] = readxl(f, "Library data!C127:C127")[1]           # Most negative cost growth rate
    
    # p["automult_autonomoustechchange"] = readxl(f, "Library data!C134:C134")[1]        # Autonomous technical change
    # p["auto"] = readxl(f, "Library data!C134:C134")[1]        # Autonomous technical change

    p["d_sulphateforcingbase"] = readxl(f, "Library data!C11:C11")[1]
    p["ind_slopeSEforcing_indirect"] = readxl(f, "Library data!C12:C12")[1]

    p["q0propmult_cutbacksatnegativecostinfinalyear"] = readxl(f, "Library data!C122:C122")[1]
    p["qmax_minus_q0propmult_maxcutbacksatpositivecostinfinalyear"] = readxl(f, "Library data!C124:C124")[1]
    p["c0mult_mostnegativecostinfinalyear"] = readxl(f, "Library data!C126:C126")[1]

    p["civvalue_civilizationvalue"] = readxl(f, "Library data!C44:C44")[1]

    #------------------------
    # 3. POLICY A sheet
    #------------------------

    # Emissions growth (all but CO2)
    p["er_CH4emissionsgrowth"] = convert(Array{Float64}, readxl(f, "Policy A!B14:K21")')    # CH4 emissions growth
    p["er_N2Oemissionsgrowth"] = convert(Array{Float64}, readxl(f, "Policy A!B23:K30")')    # N2O emissions growth
    p["er_LGemissionsgrowth"] = convert(Array{Float64}, readxl(f, "Policy A!B32:K39")')    # Lin emissions growth
    p["AbatementCostsCH4_er_emissionsgrowth"] = convert(Array{Float64}, readxl(f, "Policy A!B14:K21")')    # CH4 emissions growth
    p["AbatementCostsN2O_er_emissionsgrowth"] = convert(Array{Float64}, readxl(f, "Policy A!B23:K30")')    # N2O emissions growth
    p["AbatementCostsLin_er_emissionsgrowth"] = convert(Array{Float64}, readxl(f, "Policy A!B32:K39")')    # Lin emissions growth
    
    p["pse_sulphatevsbase"] = convert(Array{Float64}, readxl(f, "Policy A!B41:K48")')

    return p
end

function getpageindexfromyear(year)
    i = findfirst(isequal(year), page_years)
    if i == 0
        error("Invalid PAGE year: $year.")
    end 
    return i 
end

function getpageindexlengthfromyear(year)
    if year == 2010
        return 10
    end 
    
    i = findfirst(page_years, year)
    if i == 0
        error("Invalid PAGE year: $year.")
    end 

    return page_years[i] - page_years[i-1]
end

function getperiodlength(year)
    if year==2010
        return 10
    end

    i = getpageindexfromyear(year)

    return (page_years[i+1] - page_years[i-1]) / 2
end


"""
    Returns marginal damages each year from an additional emissions pulse in the specified year. 
    User must specify an IWG scenario name `scenario_name`.
    If no `year` is specified, will run for an emissions pulse in $_default_year.
    If no `discount` is specified, will return undiscounted marginal damages.
    Default returns global values; specify `regional=true` for regional values.
"""
function get_page_marginaldamages(scenario_name::String, year::Int, discount::Float64, regional::Bool=false)

    # Check the emissions year
    if ! (year in page_years)
        error("$year not a valid year; must be in model's time index $page_years.")
    end

    base, marginal = get_marginal_page_models(scenario_name=scenario_name, year=year, discount=discount)

    if discount == 0
        base_impacts = base[:EquityWeighting, :wit_equityweightedimpact]
        marg_impacts = marginal[:EquityWeighting, :wit_equityweightedimpact]
    else
        base_impacts = base[:EquityWeighting, :widt_equityweightedimpact_discounted]
        marg_impacts = marginal[:EquityWeighting, :widt_equityweightedimpact_discounted]
    end

    marg_damages = (marg_impacts .- base_impacts) ./ 100000     # TODO: comment with specified units here

    if regional
        return marg_damages
    else
        return sum(marg_damages, dims = 2) # sum along second dimension to get global values
    end
end

@defcomp PAGE_marginal_emissions begin 
    er_CO2emissionsgrowth = Variable(index=[time,region], unit = "%")
    marginal_emissions_growth = Parameter(index=[time,region], unit = "%", default = zeros(10,8))
    function run_timestep(p, v, d, t)
        if is_first(t)
            v.er_CO2emissionsgrowth[:, :] = p.marginal_emissions_growth[:, :]
        end
    end
end

function get_marginal_page_models(; scenario_name::Union{String, Nothing}=nothing, year=nothing, discount=nothing)

    base = get_page_model(scenario_name)
    if discount != nothing
        update_param!(base, :ptp_timepreference, discount * 100)
    end
    marginal = Model(base)

    add_comp!(marginal, PAGE_marginal_emissions, :marginal_emissions; before = :co2emissions)
    connect_param!(marginal, :co2emissions=>:er_CO2emissionsgrowth, :marginal_emissions=>:er_CO2emissionsgrowth)
    connect_param!(marginal, :AbatementCostsCO2=>:er_emissionsgrowth, :marginal_emissions=>:er_CO2emissionsgrowth)

    if year != nothing
        run(base)
        Mimi.build(marginal)
        perturb_marginal_page_emissions!(base, marginal, year)
        run(marginal)
    end

    return base, marginal
end


# Called after base has already been run; marginal's emission growth modified relative to base's values.
# This modifies emissions growth parameter in marginal's model instance's model definition, so that the isntance isn't decached.
function perturb_marginal_page_emissions!(base::Model, marginal::Model, emissionyear)

    i = getpageindexfromyear(emissionyear) 

    # Base model
    base_glob0_emissions = base[:co2cycle, :e0_globalCO2emissions]
    er_co2_a = base[:co2emissions, :er_CO2emissionsgrowth][i, :]
    e_co2_g = base[:co2emissions, :e_globalCO2emissions]    

    # Calculate pulse 
    ER_SCC = 100 * -100000 / (base_glob0_emissions * getperiodlength(emissionyear))
    pulse = er_co2_a - ER_SCC * (er_co2_a/100) * (base_glob0_emissions / e_co2_g[i])
    marginal_emissions_growth = copy(base[:co2emissions, :er_CO2emissionsgrowth])
    marginal_emissions_growth[i, :] = pulse

    # Marginal emissions model
    md = marginal.mi.md 
    update_param!(md, :marginal_emissions_growth, marginal_emissions_growth)    # this updates the marginal_emissions_growth parameter that both :er_CO2emissionsgrowth and :AbatementCostsCO2_er_emissionsgrowth are connected to from the PAGE_marginal_emissions comp

    return nothing
end  

"""
    Returns the Social Cost of Carbon for a given `year` and `discount` rate from one deterministic run of the IWG-PAGE model.
    User must specify an IWG scenario name `scenario_name`.
    If no `year` is specified, will return SCC for $_default_year.
    If no `discount` is specified, will return SCC for a discount rate of $(_default_discount * 100)%.
"""
function get_page_scc(scenario_name::String, year::Int, discount::Float64; domestic=false)

    # Check the emissions year
    _need_to_interpolate = false
    if year < page_years[1] || year > page_years[end]
        error("$year is not a valid year; can only calculate SCC within the model's time index $page_years.")
    elseif ! (year in page_years)
        _need_to_interpolate = true         # boolean flag for if the desired SCC years is in the middle of the model's time index
        mid_year = year     # save the desired SCC year to interpolate later
        year = filter(x-> x < year, page_years)[end]    # use the last year less than the desired year as the lower scc value
    end

    base, marginal = get_marginal_page_models(scenario_name=scenario_name, year=year, discount=discount)
    DF = [(1 / (1 + discount)) ^ (Y - 2000) for Y in page_years]
    idx = getpageindexfromyear(year)

    if domestic
        td_base = sum(base[:EquityWeighting, :addt_equityweightedimpact_discountedaggregated][:, 2])  # US is the second region; then sum across time
        td_marginal = sum(marginal[:EquityWeighting, :addt_equityweightedimpact_discountedaggregated][:, 2])
    else 
        td_base = base[:EquityWeighting, :td_totaldiscountedimpacts]
        td_marginal = marginal[:EquityWeighting, :td_totaldiscountedimpacts] 
    end
        
    EMUC = base[:EquityWeighting, :emuc_utilityconvexity]
    UDFT_base = DF[idx] * (base[:EquityWeighting, :cons_percap_consumption][idx, 1] / base[:EquityWeighting, :cons_percap_consumption_0][1]) .^ (-EMUC)
    UDFT_marginal = DF[idx] * (marginal[:EquityWeighting, :cons_percap_consumption][idx, 1] / base[:EquityWeighting, :cons_percap_consumption_0][idx]) ^ (-EMUC)

    scc = ((td_marginal / UDFT_marginal) - (td_base / UDFT_base)) / 100000 * page_inflator

    if _need_to_interpolate     # need to calculate SCC for next year in time index as well, then interpolate for desired year
        lower_scc = scc
        next_year = page_years[findfirst(page_years, year) + 1] 
        upper_scc = get_page_scc(scenario_name, next_year, discount, domestic=domestic)
        scc = _interpolate([lower_scc, upper_scc], [year, next_year], [mid_year])[1]
    end 

    return scc
end
