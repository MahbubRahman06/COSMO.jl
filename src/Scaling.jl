module Scaling

using ..QOCS, SparseArrays, LinearAlgebra, Statistics
export scaleRuiz!,reverseScaling!


  function kktColNorms!(P,A,normLHS,normRHS)

    colNorms!(normLHS,P,reset = true);   #start from zero
    colNorms!(normLHS,A,reset = false);  #incrementally from P norms
    rowNorms!(normRHS,A)                 #same as column norms of A'
    return nothing
  end

  @inline function limitScaling!(s::Number,minval::Number,maxval::Number)
      s = s < minval ? 1  : (s > maxval ? maxval : s)
  end

  function limitScaling!(s::Array,minval,maxval)
      s .= limitScaling!.(s,minval,maxval)
  end

  function limitScaling!(s,set::QOCS.Settings)
      limitScaling!(s,set.MIN_SCALING,set.MAX_SCALING)
  end


  function scaleRuiz!(ws::QOCS.Workspace,set::QOCS.Settings)

      #references to scaling matrices from workspace
      D    = ws.sm.D
      E    = ws.sm.E

      #unit scaling to start
      D.diag .= 1.
      E.diag .= 1.
      c       = 1.

      #use the inverse scalings as intermediate
      #work vectors as well, since we don't
      #compute the inverse scaling until the
      #final step
      Dwork = ws.sm.Dinv
      Ework = ws.sm.Einv

      #references to QP data matrices
      P = ws.p.P
      A = ws.p.A
      q = ws.p.q
      b = ws.p.b

      #perform scaling operations for a fixed
      #number of steps, i.e. no tolerance or
      #convergence check
      for i = 1:set.scaling

          kktColNorms!(P,A,Dwork.diag,Ework.diag)
          limitScaling!(Dwork.diag,set)
          limitScaling!(Ework.diag,set)

          @. Dwork.diag = 1 / sqrt(Dwork.diag)
          @. Ework.diag = 1 / sqrt(Ework.diag)

          # Scale the problem data and update the
          # equilibration matrices
          scaleData!(P,A,q,b,Dwork,Ework,1.)
          lmul!(Dwork,D)        #D[:,:] = Dtemp*D
          lmul!(Ework,E)        #D[:,:] = Dtemp*D

          # now use the Dwork array to hold the
          # column norms of the newly scaled P
          # so that we can compute the mean
          colNorms!(Dwork.diag,P)
          mean_col_norm_P = mean(Dwork.diag)
          inf_norm_q      = norm(q,Inf)

          if mean_col_norm_P  != 0. && inf_norm_q != 0.

            limitScaling!(inf_norm_q,set)
            scale_cost = max(inf_norm_q,mean_col_norm_P)
            limitScaling!(scale_cost,set)
            ctmp = 1.0 / scale_cost

            # scale the penalty terms and overall scaling
            P .*= ctmp
            q .*= ctmp
            c  *= ctmp
          end

      end #end Ruiz scaling loop



      # for certain cones we can only use a
      # a single scalar value.  In these cases
      # compute an adjustment to the overall scaling
      # so that the aggregate scaling on the cone
      # in questions turns out to be component-wise eq
      if rectifySetScalings!(E,Ework,ws.p.convexSets)
          #only rescale if the above returns true,
          #i.e. some cone scalings were rectified
          scaleData!(P,A,q,b,I,Ework,1.)
-         lmul!(Ework,E)
     end

      #scale set components
      scaleSets!(E,ws.p.convexSets)

      #update the inverse scaling data, c and c_inv
      ws.sm.Dinv.diag .= 1. ./ D.diag
      ws.sm.Einv.diag .= 1. ./ E.diag
      ws.sm.c          = c
      ws.sm.cinv       = 1. ./ c

      # scale the potentially warm started variables
      ws.x[:] = ws.sm.Dinv *ws.x
      ws.μ[:] = ws.sm.Einv*ws.μ *c

  end

  function rectifySetScalings!(E,Ework,sets)

      anyRectifiedBlocks = false
      Ework.diag        .= 1

      # NB : we should actually provide each cone
      # with the opportunity to provide its own
      # (possibly non-scalar) rectification

      for set in sets
          isScalar, = set.scale!(set)

          if isScalar
              #at least one block was scalar
              anyRectifiedBlocks = true
              ind = set.indices
              tmp = mean(E.diag[ind])
              Ework.diag[ind] .= tmp./E.diag[ind]
          end
      end
      return anyRectifiedBlocks
  end


  function scaleSets!(E,sets)

      # scale set components (like u,l in a box)
      for set in sets
          scaleInfo = set.scale!(set)
          if length(scaleInfo) > 1
              #NB : Memory allocated here?
              for elem in scaleInfo[2:end]
                  elem[:] = E*elem
              end
          end
      end
  end


  function scaleData!(P,A,q,b,Ds,Es,cs=1.)

      lrmul!(Ds,P,Ds) # P[:,:] = Ds*P*Ds
      lrmul!(Es,A,Ds) # A[:,:] = Es*A*Ds
      q[:] = Ds*q
      b[:] = Es*b

      if cs != 1.
          P .*= cs
          q .*= cs
      end
      return nothing
  end


  function reverseScaling!(ws::QOCS.Workspace)

    ws.x[:] = ws.sm.D*ws.x
    ws.s[:] = ws.sm.Einv*ws.s
    ws.ν[:] = ws.sm.E*ws.ν*ws.sm.cinv
    ws.μ[:] = ws.sm.E*ws.μ*ws.sm.cinv

    # reverse scaling for model data
    if ws.p.flags.REVERSE_SCALE_PROBLEM_DATA
        scaleData!(ws.p.P,ws.p.A,ws.p.q,ws.p.b,
                   ws.sm.Dinv,ws.sm.Einv,ws.sm.cinv)
    end
    return nothing
  end

end # MODULE
