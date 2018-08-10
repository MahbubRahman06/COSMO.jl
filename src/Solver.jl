

function setModel!(model::QOCS.Model,P::SparseMatrixCSC{Float64,Int64},q::Vector{Float64},A::SparseMatrixCSC{Float64,Int64},b::Vector{Float64},K::QOCS.Cone)
  model.P = P
  model.q = q
  model.A = A
  model.b = b
  model.K = K
  nothing
end

function admmStep!(x, s, μ, ν, x_tl, s_tl, ls, sol, F, q, b, K, ρ, α, σ, m, n)
  # Create right hand side for linear system
  for i=1:n
    ls[i] = σ*x[i]-q[i]
  end
  for i=1:m
    ls[n+i] = b[i]-s[i]+μ[i]/ρ[i]
  end
    sol = F \ ls
  # deconstruct solution vector ls = [x_tl(n+1);ν(n+1)]
  @. x_tl = sol[1:n]
  @. ν = sol[n+1:end]
  # Over relaxation
  @. x = α*x_tl + (1.0-α)*x
  @. s_tl = s - (ν+μ)./ρ
  @. s_tl = α*s_tl + (1.0-α)*s
  @. s = s_tl + μ./ρ
  # Project onto cone K
  Projections.projectCompositeCone!(s, K)
  # update dual variable μ
  @. μ = μ + ρ.*(s_tl - s)
  nothing
end

function solve!(model::QOCS.Model,settings::QOCS.Settings,results)
   resSolver, nothing = solve(model.P,model.q,model.A,model.b,model.K,settings)
   results.x = resSolver.x
   results.ν = resSolver.ν
   results.μ = resSolver.μ
   results.cost = resSolver.cost
   results.iter = resSolver.iter
   results.status = resSolver.status
   results.solverTime = resSolver.solverTime
   results.setupTime = resSolver.setupTime
   results.iterTime = resSolver.iterTime
   results.rPrim = resSolver.rPrim
   results.rDual = resSolver.rDual
   nothing
end

# SOLVER ROUTINE
# -------------------------------------
  function solve(P,q,A,b,K::QOCS.Cone,settings::QOCS.Settings)
    runTime_start = time()

    # create workspace variables
    ws = WorkSpace(Problem(P,q,A,b,K),ScaleMatrices())
    P = q = A = b = nothing

    # perform preprocessing steps (scaling, initial KKT factorization)
    setupTime = time()
    setup!(ws,settings)
    setupTime = time() - setupTime

    # instantiate variables
    iter = 0
    status = :Unsolved
    cost = Inf
    r_prim = Inf
    r_dual = Inf


    # print information about settings to the screen
    settings.verbose && printHeader(ws,settings,setupTime)

    timeLimit_start = time()
    #preallocate arrays
    δx = similar(ws.x)
    δy =  similar(ws.μ)
    x_tl = similar(ws.x) # i.e. xTilde
    s_tl = similar(ws.s) # i.e. sTilde
    const n = ws.p.n
    const m = ws.p.m
    ls = zeros(n + m)
    sol = zeros(n + m)

    iter_start = time()

    for iter = 1:settings.max_iter

      @. δx = ws.x
      @. δy = ws.μ
      admmStep!(
        ws.x, ws.s, ws.μ, ws.ν,
        x_tl, s_tl, ls,sol,
        ws.p.F, ws.p.q, ws.p.b, K, ws.p.ρVec,
        settings.alpha, settings.sigma,
        m, n
      )

      # compute deltas for infeasibility detection
      @. δx = ws.x - δx
      @. δy = -ws.μ + δy

      # compute residuals (based on optimality conditions of the problem) to check for termination condition
      # compute them every {settings.check_termination} step
      mod(iter,settings.check_termination)  == 0 && ((r_prim,r_dual) = calculateResiduals(ws,settings))


      # check convergence with residuals every {settings.checkIteration} steps
      if mod(iter,settings.check_termination) == 0
        # update cost
        cost = ws.sm.cinv*(1/2 * ws.x'*ws.p.P*ws.x + ws.p.q'*ws.x)[1]

        if abs(cost) > 1e20
          status = :Unsolved
          break
        end

        # print iteration steps
        settings.verbose && printIteration(settings,iter,cost,r_prim,r_dual)

        if hasConverged(ws,settings,r_prim,r_dual)
          status = :Solved
          break
        end
      end

      # check infeasibility conditions every {settings.checkInfeasibility} steps
      if mod(iter,settings.check_infeasibility) == 0
        if isPrimalInfeasible(δy,ws,settings)
            status = :Primal_infeasible
            cost = Inf
            ws.x .= NaN
            ws.μ .= NaN
            ws.ν .= NaN
            break
        end

        if isDualInfeasible(δx,ws,settings)
            status = :Dual_infeasible
            cost = -Inf
            ws.x .= NaN
            ws.μ .= NaN
            ws.ν .= NaN
            break
        end
      end


      # adapt rhoVec if enabled
      if settings.adaptive_rho && (mod(iter,settings.adaptive_rho_interval) == 0) && (settings.adaptive_rho_interval > 0)
        adaptRhoVec!(ws,settings)
      end

      if settings.timelimit !=0 &&  (time() - timeLimit_start) > settings.timelimit
        status = :Time_limit_reached
        break
      end

    end #END-ADMM-MAIN-LOOP

    iterTime = (time()-iter_start)

    # calculate primal and dual residuals
    if iter == settings.max_iter
      r_prim,r_dual = calculateResiduals(ws,settings)
      status = :Max_iter_reached
    end

    # reverse scaling for scaled feasible cases
    if settings.scaling != 0 && (cost != Inf && cost != -Inf)
      reverseScaling!(ws)
      # FIXME: Another cost calculation is not necessary since cost value is not affected by scaling
      cost =  (1/2 * ws.x'*ws.p.P*ws.x + ws.p.q'*ws.x)[1] #sm.cinv * not necessary anymore since reverseScaling
    end


    runTime = time() - runTime_start

    # print solution to screen
    settings.verbose && printResult(status,iter,cost,runTime)


    # create result object
    result = QOCS.Result(ws.x,ws.s,ws.ν,ws.μ,cost,iter,status,runTime,setupTime,iterTime,r_prim,r_dual);

    return result,ws, δx, -δy;

  end






