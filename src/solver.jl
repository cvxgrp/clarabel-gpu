# -------------------------------------
# utility constructor that includes
# both object creation and setup
#--------------------------------------
function Solver(
    P::AbstractMatrix{T},
    c::Vector{T},
    A::AbstractMatrix{T},
    b::Vector{T},
    cone_types::Vector{SupportedCones},
    cone_dims::Vector{Int};
    kwargs...
) where{T <: AbstractFloat}

    s = Solver{T}()
    setup!(s,P,c,A,b,cone_types,cone_dims,kwargs...)
    return s
end

# -------------------------------------
# setup!
# -------------------------------------


"""
	setup!(solver, P, q, A, b, cone_types, cone_dims, [settings])

Populates a [`Solver`](@ref) with a cost function defined by `P` and `q`, and one or more conic constraints defined by `A`, `b` and a description of a conic constraint composed of cones whose types and dimensions are in `cone_types` and `cone_dims`, respectively.

The solver will be configured to solve the following optimization problem:

```
min   1/2 x'Px + q'x
s.t.  Ax + s = b, s ∈ K
```

All data matrices must be sparse.   The matrix `P` is assumed to be symmetric and positive semidefinite, and only the upper triangular part is used.

The cone `K` is a composite cone whose consituent cones are described by
* cone_types::Vector{Clarabel.SupportedCones}
* cone_dims::Vector{Int}

The optional argument `settings` can be used to pass custom solver settings:
```julia
settings = Clarabel.Settings(verbose = true)
setup!(model, P, q, A, b, cone_types, cone_dims, settings)
```

To solve the problem, you must make a subsequent call to [`solve!`](@ref)
"""
function setup!(s,P,c,A,b,cone_types,cone_dims,settings::Settings)
    #this allows total override of settings during setup
    s.settings = settings
    setup!(s,P,c,A,b,cone_types,cone_dims)
end

function setup!(s,P,c,A,b,cone_types,cone_dims; kwargs...)
    #this allows override of individual settings during setup
    settings_populate!(s.settings, Dict(kwargs))
    setup!(s,P,c,A,b,cone_types,cone_dims)
end

# main setup function
function setup!(
    s::Solver{T},
    P::AbstractMatrix{T},
    q::Vector{T},
    A::AbstractMatrix{T},
    b::Vector{T},
    cone_types::Vector{SupportedCones},
    cone_dims::Vector{Int}
) where{T}

    #make this first to create the timers
    s.info    = DefaultInfo{T}()

    @timeit s.info.timer "setup!" begin

        s.data   = DefaultProblemData{T}(P,q,A,b)
        s.cones  = ConeSet{T}(cone_types,cone_dims)
        s.data.m == s.cones.numel || throw(DimensionMismatch())

        s.variables = DefaultVariables{T}(s.data.n,s.cones)
        s.residuals = DefaultResiduals{T}(s.data.n,s.data.m)

        #equilibrate problem data immediately on setup.
        #this prevents multiple equlibrations if solve!
        #is called more than once.
        s.equilibration  = DefaultEquilibration{T}(s.data.n,s.cones,s.settings)
        @timeit s.info.timer "equilibrate" begin
            equilibrate!(s.equilibration,s.data,s.cones,s.settings)
        end

        @timeit s.info.timer "kkt init" begin
            s.kktsolver = DefaultKKTSolver{T}(s.data,s.cones,s.settings)
        end

        # work variables for assembling step direction LHS/RHS
        s.step_rhs  = DefaultVariables{T}(s.data.n,s.cones)
        s.step_lhs  = DefaultVariables{T}(s.data.n,s.cones)

    end

    return s
end


# -------------------------------------
# solve!
# -------------------------------------

"""
	solve!(solver)

Computes the solution to the problem in a `Clarabel.Solver` previously defined in [`setup!`](@ref).
"""
function solve!(
    s::Solver{T}
) where{T}

    #various initializations
    info_reset!(s.info)
    iter   = 0
    isdone = false
    timer  = s.info.timer

    #initial residuals and duality gap
    gap       = T(0)
    sigma     = T(0)

    #solver release info, solver config
    #problem dimensions, cone type etc
    @notimeit print_header(s.info,s.settings,s.data,s.cones)

    @timeit timer "solve!" begin

        #initialize variables to some reasonable starting point
        @timeit timer "default start" solver_default_start!(s)

        @timeit timer "IP iteration" begin

        #----------
        # main loop
        #----------
        while true

            #update the residuals
            #--------------
            residuals_update!(s.residuals,s.variables,s.data)

            #calculate duality gap (scaled)
            #--------------
            μ = calc_mu(s.variables, s.residuals, s.cones)

            #convergence check and printing
            #--------------
            @timeit timer "check termination" begin
                info_update!(
                    s.info,s.data,s.variables,
                    s.residuals,s.equilibration,s.settings
                )
                isdone = info_check_termination!(s.info,s.residuals,s.settings)
            end
            iter += 1
            @notimeit print_status(s.info,s.settings)
            isdone && break

            #update the scalings
            #--------------
            @timeit timer "NT scaling" scaling_update!(s.cones,s.variables)

            #update the KKT system and the constant
            #parts of its solution
            #--------------
            @timeit timer "kkt update" kkt_update!(s.kktsolver,s.data,s.cones)

            #calculate the affine step
            #--------------
            calc_affine_step_rhs!(
                s.step_rhs, s.residuals,
                s.data, s.variables, s.cones
            )

            @timeit timer "kkt solve" begin
                kkt_solve!(
                    s.kktsolver, s.step_lhs, s.step_rhs,
                    s.data, s.variables, s.cones, :affine
                )
            end

            #calculate step length and centering parameter
            #--------------
            α = calc_step_length(s.variables,s.step_lhs,s.cones)
            σ = calc_centering_parameter(α)

            #calculate the combined step and length
            #--------------
            calc_combined_step_rhs!(
                s.step_rhs, s.residuals,
                s.data, s.variables, s.cones,
                s.step_lhs, σ, μ
            )

            @timeit timer "kkt solve" begin
                kkt_solve!(
                    s.kktsolver, s.step_lhs, s.step_rhs,
                    s.data, s.variables, s.cones, :combined
                )
            end

            #compute final step length and update the current iterate
            #--------------
            @timeit timer "step length" α  = calc_step_length(s.variables,s.step_lhs,s.cones)
            α *= s.settings.max_step_fraction

            variables_add_step!(s.variables,s.step_lhs,α)

            #record scalar values from this iteration
            info_save_scalars(s.info,μ,α,σ,iter)

        end  #end while
        #----------
        #----------

        end #end IP iteration timer

    variables_finalize!(s.variables, s.equilibration, s.info.status)

    end #end solve! timer

    info_finalize!(s.info)
    @notimeit print_footer(s.info,s.settings)

    return nothing
end


# Mehrotra heuristic
function calc_centering_parameter(α::T) where{T}

    return σ = (1-α)^3
end


function solver_default_start!(s::Solver{T}) where {T}

    #set all scalings to identity (or zero for the zero cone)
    scaling_identity!(s.cones)
    #Refactor
    kkt_update!(s.kktsolver,s.data,s.cones)
    #solve for primal/dual initial points via KKT
    kkt_solve_initial_point!(s.kktsolver,s.variables,s.data)
    #fix up (z,s) so that they are in the cone
    variables_shift_to_cone!(s.variables, s.cones)

    return nothing
end
