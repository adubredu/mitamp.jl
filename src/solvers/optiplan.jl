function get_fluent_range_indices(graph, level, max_num_fluents)
    lvl = 5(level-1) #+ 1
    row = length(graph.props[level])
    relevant = (1:row, lvl)
    nonrelevant = (row+1:max_num_fluents, lvl+1:lvl+5)
    return relevant, nonrelevant 
end

function get_fluent_terminal_indices(graph; loc=:init) 
    indices = []
    not_ind = [] 
    T = graph.num_levels 
    if loc == :init
        for i=1:length(graph.initprops) 
            ind = findall(x->x == graph.initprops[i], graph.props[0])[1]
            push!(indices, ind)
        end
    else
        for i=1:length(graph.goalprops) 
            ind = findall(x->x == graph.goalprops[i], graph.props[T])[1]
            push!(indices, ind)
        end 
    end
    not_ind = [i for i=1:length(graph.props[0]) if !(i in indices)]
    return indices, not_ind    
end


function get_action_indices(graph, fluent, level, set, except_set)
    actions = graph.acts[level]
    action_indices = []
    if set == :add && except_set == :pre
        for i = 1:length(actions)
            act = actions[i]  
            if fluent in act.pos_eff && !(fluent in act.pos_prec)
                push!(action_indices, i)
            end
        end
    elseif set == :del && except_set == :pre 
        for i = 1:length(actions)
            act = actions[i]  
            if fluent in act.neg_eff && !(fluent in act.pos_prec)
                push!(action_indices, i)
            end
        end
    elseif set == :pre && except_set == :del 
        for i = 1:length(actions)
            act = actions[i]  
            if fluent in act.pos_prec && !(fluent in act.neg_eff)
                push!(action_indices, i)
            end
        end
    else
        for i = 1:length(actions)
            act = actions[i]  
            if fluent in act.pos_prec && fluent in act.neg_eff
                push!(action_indices, i)
            end
        end
    end
    return action_indices 
end
 

#=
state change variables xₜ are encoded as 
            1     2      3    4     5
        preadd, predel, add, del, maintain
            pa,     pd,  ad,  dl,   mn
=#
function encode(domain_name, problem_name; max_levels=10)
    domain = load_domain(domain_name)
    problem = load_problem(problem_name)
    graph = create_graph(domain, problem; max_levels=max_levels)

    model = Model(Gurobi.Optimizer)
    T = graph.num_levels 
    max_nf = max([length(graph.props[i]) for i=1:T]...)
    max_na = max([length(graph.acts[i]) for i=1:T]...)
    pa, pd, ad, dl, mn = 1,2,3,4,5

    #=
        VARIABLES
    =#
    @variable(model, x[i=1:max_nf, j=1:5*T], Bin)
    @variable(model, y[i=1:max_na, j=1:T], Bin) 

    #=
        CONSTRAINTS
    =#

    #init constraints 
    init_idx, nr_init_idx = get_fluent_range_indices(graph, 1, max_nf)
    inits, notinits = get_fluent_terminal_indices(graph; loc=:init) 
    for i in inits
        @constraint(model, x[i, init_idx[2]+ad] == 1)
    end
    for i in notinits
        @constraint(model, x[i, init_idx[2]+ad] == 0)
    end
    @constraint(model, x[init_idx[1], init_idx[2]+mn] .== 0)
    @constraint(model, x[init_idx[1], init_idx[2]+pa] .== 0)
    @constraint(model, x[init_idx[1], init_idx[2]+pd] .== 0)
    @constraint(model, x[init_idx[1], init_idx[2]+dl] .== 0)

    # @constraint(model, x[nr_init_idx[1], nr_init_idx[2]] == 0)

    #goal constraints 
    goals, _ = get_fluent_terminal_indices(graph; loc=:goal) 
    gidx, _ = get_fluent_range_indices(graph, T, max_nf)
    for g in goals 
        @constraint(model, x[g,gidx[2]+ad] + x[g,gidx[2]+mn] + x[g, gidx[2]+pa] >= 1)
    end

    
    for t=2:T 
        #effect implication constraints 
        fidx,_ = get_fluent_range_indices(graph, t, max_nf)
        # Eq. 5
        for f = 1:length(graph.props[t]) 
            fluent = graph.props[t][f]
            act_inds = get_action_indices(graph, fluent, t, :add, :pre) 
            if !isempty(act_inds)
                @constraint(model, sum([y[i,t] for i in act_inds]) >= x[f, fidx[2]+ad])
                # Eq. 6
                [@constraint(model, y[i,t]  <= x[f, fidx[2]+ad]) for i in act_inds]
            end

        # # Eq. 7
        # for f = 1:length(graph.props[t]) 
            # fluent = graph.props[t][f]
            act_inds = get_action_indices(graph, fluent, t, :del, :pre) 
            if !isempty(act_inds)
                @constraint(model, sum([y[i,t] for i in act_inds]) >= x[f, fidx[2]+dl])
                #Eq. 8
                [@constraint(model, y[i,t]  <= x[f, fidx[2]+dl]) for i in act_inds]
            end

        # # Eq. 9
        # for f = 1:length(graph.props[t]) 
            # fluent = graph.props[t][f]
            act_inds = get_action_indices(graph, fluent, t, :pre, :del) 
            if !isempty(act_inds)
                @constraint(model, sum([y[i,t] for i in act_inds]) >= x[f, fidx[2]+pa])
                #Eq. 10
                [@constraint(model, y[i,t]  <= x[f, fidx[2]+pa]) for i in act_inds]
            end

        # # Eq. 11
        # for f = 1:length(graph.props[t]) 
            # fluent = graph.props[t][f]
            act_inds = get_action_indices(graph, fluent, t, :pre, :anddel) 
            if !isempty(act_inds)
                @constraint(model, sum([y[i,t] for i in act_inds]) >= x[f, fidx[2]+pd]) 
            end
            # Eq. 12
            @constraint(model, x[f,fidx[2]+ad] + x[f,fidx[2]+mn] + x[f,fidx[2]+dl] 
                            + x[f, fidx[2]+pd] <= 1)

            # Eq. 13
            @constraint(model, x[f,fidx[2]+pa] + x[f,fidx[2]+mn] + x[f,fidx[2]+dl] 
                            + x[f, fidx[2]+pd] <= 1)

            # Eq. 14
            fidx_prev,_ = get_fluent_range_indices(graph, t-1, max_nf)
            @constraint(model, x[f,fidx[2]+pa] + x[f,fidx[2]+mn] + x[f,fidx[2]+pd] 
                            <= x[f,fidx_prev[2]+pa] + x[f,fidx_prev[2]+ad] + x[f,fidx_prev[2]+mn])
        end

    end

    #objective
    @objective(model, Min, sum(y))
    
    return model 
end
