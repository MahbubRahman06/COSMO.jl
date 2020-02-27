__precompile__()
module COSMO

    using SparseArrays, LinearAlgebra, SuiteSparse, QDLDL, Pkg, DataStructures, Requires


    export assemble!, warmStart!, empty_model!

    const DefaultFloat = Float64
    const DefaultInt   = LinearAlgebra.BlasInt


    include("./kktsolver.jl")

    # optional dependencies
    @require Pardiso="46dd5b70-b6fb-5a00-ae2d-e8fea33afaf2" include("./kktsolver_pardiso.jl")

    @require IterativeSolvers="42fd0dbc-a981-5370-80f2-aaf504508153" begin
        @require LinearMaps="7a12625a-238d-50fd-b39a-03d52299707e" include("./kktsolver_indirect.jl")
    end

    include("./algebra.jl")
    include("./projections.jl")
    include("./trees.jl")
    include("./clique_merging.jl")
    include("./settings.jl")
    include("./types.jl")
    include("./constraint.jl")
    include("./parameters.jl")
    include("./residuals.jl")
    include("./scaling.jl")
    include("./infeasibility.jl")
    include("./transformations.jl")
    include("./chordal_decomposition.jl")
    include("./printing.jl")
    include("./setup.jl")
    include("./solver.jl")
    include("./interface.jl")
    include("./MOIWrapper.jl")


end #end module
