__precompile__()
module Clarabel

    using SparseArrays, LinearAlgebra, Printf, Requires
    using LimitedLDLFactorizations # for lldl
    using CUDA, CUDA.CUBLAS # for GPU implementation
    const DefaultFloat = Float64
    const DefaultInt   = Int64
    const SOC_NO_EXPANSION_MAX_SIZE   = 5  # maximal size of second-order cones in GPU implementation

    # Rust-like Option type
    const Option{T} = Union{Nothing,T} 

    #internal constraint RHS limits.  This let block 
    #hides the INFINITY field in the module and makes 
    #it accessible only via the get/set provided
    let 
        _INFINITY_DEFAULT = 1e20
        INFINITY = _INFINITY_DEFAULT
        global default_infinity() = INFINITY = _INFINITY_DEFAULT;
        global set_infinity(v::Float64) = INFINITY =  Float64(v)
        global get_infinity() = INFINITY
    end 
    
    #List of GPU solvers
    gpu_solver_list = [:cudss, :cudssmixed]
    
    #version / release info
    include("./version.jl")

    #API for user cone specifications
    include("./cones/cone_api.jl")

    #cone type definitions
    include("./cones/cone_types.jl")
    include("./cones/cone_dispatch.jl")
    include("./cones/compositecone_type.jl")
    include("./gpucones/compositecone_type_gpu.jl")

    #core solver components
    include("./abstract_types.jl")
    include("./settings.jl")
    include("./statuscodes.jl")
    include("./chordal/include.jl")
    include("./types.jl")  
    include("./presolver.jl")
    include("./variables.jl")
    include("./residuals.jl")
    include("./problemdata.jl")

    #direct LDL linear solve methods
    include("./kktsolvers/direct-ldl/includes.jl")

    #KKT solvers and solver level kktsystem
    include("./kktsolvers/kktsolver_defaults.jl")
    include("./kktsolvers/kktsolver_directldl.jl")

    include("./kktsystem.jl")
    include("./kktsystem_gpu.jl")

    include("./info.jl")
    include("./solution.jl")

    #GPU ldl methods
    include("./kktsolvers/gpu/includes.jl")
    include("./kktsolvers/kktsolver_directldl_gpu.jl")

    # printing and top level solver
    include("./info_print.jl")
    include("./solver.jl")

    #conic constraints.  Additional
    #cone implementations go here
    include("./cones/coneops_defaults.jl")
    include("./cones/coneops_zerocone.jl")
    include("./cones/coneops_nncone.jl")
    include("./cones/coneops_socone.jl")
    include("./cones/coneops_psdtrianglecone.jl")
    include("./cones/coneops_expcone.jl")
    include("./cones/coneops_powcone.jl")
    include("./cones/coneops_genpowcone.jl")        #Generalized power cone 
    include("./cones/coneops_compositecone.jl")
    include("./cones/coneops_nonsymmetric_common.jl")
    include("./cones/coneops_symmetric_common.jl")

    #GPU cone implementations
    include("./gpucones/coneops_zerocone_gpu.jl")
    include("./gpucones/coneops_nncone_gpu.jl")
    include("./gpucones/coneops_socone_gpu.jl")
    include("./gpucones/coneops_expcone_gpu.jl")
    include("./gpucones/coneops_powcone_gpu.jl")
    include("./gpucones/coneops_compositecone_gpu.jl")
    include("./gpucones/coneops_nonsymmetric_common_gpu.jl")
    include("./gpucones/augment_socp.jl")

    #various algebraic utilities
    include("./utils/mathutils.jl")
    include("./utils/csc_assembly.jl")

    #data updating
    include("./data_updating.jl")

    #optional dependencies.  
    #NB: This __init__ function and its @require statements 
    #should be removed upon update of this package for use 
    #with Julia v1.10+, after which weakdeps / external 
    #dependencies will be natively supported 
    function __init__()
        @require Pardiso="46dd5b70-b6fb-5a00-ae2d-e8fea33afaf2" begin
            include("./kktsolvers/direct-ldl/directldl_pardiso.jl")  
        end 
        @require HSL="34c5aeac-e683-54a6-a0e9-6e0fdc586c50" begin
            include("./kktsolvers/direct-ldl/directldl_hsl.jl")
        end 
    end
 
    # JSON I/O
    include("./json.jl")

    #MathOptInterface for JuMP/Convex.jl
    module MOI  #extensions providing non-standard MOI constraint types
        include("./MOI_wrapper/MOI_extensions.jl")
    end
    module MOIwrapper #our actual MOI interface
         include("./MOI_wrapper/MOI_wrapper.jl")
    end
    const Optimizer{T} = Clarabel.MOIwrapper.Optimizer{T}


    #precompile minimal MOI / native examples
    using SnoopPrecompile
    include("./precompile.jl")
    redirect_stdout(devnull) do; 
        SnoopPrecompile.@precompile_all_calls begin
            __precompile_native()
            __precompile_moi()
        end
    end
    __precompile_printfcns()

end #end module