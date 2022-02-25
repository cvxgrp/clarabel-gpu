# -----------------------------------------------------
# dispatch operators for multiple cones
# -----------------------------------------------------

function cones_rectify_equilibration!(
    cones::ConeSet{T},
     δ::SplitVector{T},
     e::SplitVector{T}
) where{T}

    any_changed = false

    #we will update e <- \delta .*e using return values
    #from this function.  default is to do nothing at all
    @. δ.vec = 1

    for i = eachindex(cones)
        any_changed |= rectify_equilibration!(cones[i],δ.views[i],e.views[i])
    end

    return any_changed
end


function cones_update_scaling!(
    cones::ConeSet{T},
    s::SplitVector{T},
    z::SplitVector{T},
    λ::SplitVector{T}
) where {T}

    # update scalings by passing subview to each of
    # the appropriate cone types.
    for i = 1:length(cones)
        update_scaling!(cones[i],s.views[i],z.views[i],λ.views[i])
    end

    return nothing
end


function cones_set_identity_scaling!(
    cones::ConeSet{T}
) where {T}

    for i = 1:length(cones)
        set_identity_scaling!(cones[i])
    end

    return nothing
end


# The diagonal part of the KKT scaling
# matrix for each cone
function cones_get_diagonal_scaling!(
    cones::ConeSet{T},
    diagW2::SplitVector{T}
) where {T}

    for i = 1:length(cones)
        get_diagonal_scaling!(cones[i],diagW2.views[i])
    end
    return nothing
end

# x = y ∘ z
function cones_circle_op!(
    cones::ConeSet{T},
    x::SplitVector{T},
    y::SplitVector{T},
    z::SplitVector{T}
) where {T}

    for i = 1:length(cones)
        circle_op!(cones[i],x.views[i],y.views[i],z.views[i])
    end
    return nothing
end

# x = y \ z
function cones_inv_circle_op!(
    cones::ConeSet{T},
    x::SplitVector{T},
    y::SplitVector{T},
    z::SplitVector{T}
) where {T}

    for i = 1:length(cones)
        inv_circle_op!(cones[i],x.views[i],y.views[i],z.views[i])
    end
    return nothing
end

# place a vector to some nearby point in the cone
function cones_shift_to_cone!(
    cones::ConeSet{T},
    z::SplitVector{T}
) where {T}

    for i = 1:length(cones)
        shift_to_cone!(cones[i],z.views[i])
    end
    return nothing
end

# computes y = αWx + βy, or y = αWᵀx + βy, i.e.
# similar to the BLAS gemv interface
function cones_gemv_W!(
    cones::ConeSet{T},
    is_transpose::Bool,
    x::SplitVector{T},
    y::SplitVector{T},
    α::T,
    β::T
) where {T}

    for i = eachindex(cones)
        gemv_W!(cones[i],is_transpose,x.views[i],y.views[i],α,β)
    end
    return nothing
end

# computes y = αW^{-1}x + βy, or y = αW⁻ᵀx + βy, i.e.
# similar to the BLAS gemv interface
function cones_gemv_Winv!(
    cones::ConeSet{T},
    is_transpose::Bool,
    x::SplitVector{T},
    y::SplitVector{T},
    α::T,
    β::T
) where {T}

    for i = 1:length(cones)
        gemv_Winv!(cones[i],is_transpose,x.views[i],y.views[i],α,β)
    end
    return nothing
end

# computes y = (W^TW){-1}x
function cones_mul_WtWinv!(
    cones::ConeSet{T},
    x::SplitVector{T},
    y::SplitVector{T}
) where {T}

    for i = 1:length(cones)
        mul_WtWinv!(cones[i],x.views[i],y.views[i])
    end

    return nothing
end

# computes y = (W^TW)x
function cones_mul_WtW!(
    cones::ConeSet{T},
    x::SplitVector{T},
    y::SplitVector{T}
) where {T}

    for i = 1:length(cones)
        mul_WtW!(cones[i],x.views[i],y.views[i])
    end
    return nothing
end

#computes y = y + αe
function cones_add_scaled_e!(
    cones::ConeSet{T},
    x::SplitVector{T},
    α::T
) where {T}

    for i = 1:length(cones)
        add_scaled_e!(cones[i],x.views[i],α)
    end
    return nothing
end

# maximum allowed step length over all cones
function cones_step_length(
    cones::ConeSet{T},
    dz::SplitVector{T},
    ds::SplitVector{T},
     z::SplitVector{T},
     s::SplitVector{T},
     λ::SplitVector{T}
) where {T}

    dz    = dz.views
    ds    = ds.views
    z     = z.views
    s     = s.views
    λ     = λ.views

    α = 1/eps(T)
    for i = eachindex(cones)
        nextα = step_length(cones[i],dz[i],ds[i],z[i],s[i],λ[i])
        α = min(α, nextα)
    end

    return α
end