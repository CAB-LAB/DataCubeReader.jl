using Polynomials: fit
using Statistics: quantile!

function removeMSC(aout,ain,NpY::Integer)
    #Start loop through all other variables
    tmsc, tnmsc = zeros(Union{Float64,Missing},NpY),zeros(Int,NpY)
    @show "and nor I here"
    fillmsc(1,tmsc,tnmsc,ain,NpY)
    subtractMSC(tmsc,ain,aout,NpY)
    nothing
end

"""
    removeMSC(c)

Removes the mean annual cycle from each time series of a data cube.

**Input Axis** `Time`axis

**Output Axis** `Time`axis
"""
function removeMSC(c;kwargs...)
    NpY = getNpY(c)
    mapCube(
        removeMSC,
        c,
        NpY;
        indims  = InDims("Time"),
        outdims = OutDims("Time"),
        kwargs...
    )
end

"""
    gapFillMSC(c;complete_msc=false)

Fills missing values of each time series in a cube with the mean annual cycle.
If `complete_msc` is set to `true`, the MSC will be filled with a polynomial
in case it still contains missing values due to systematic gaps.

**Input Axis** `Time`axis

**Output Axis** `Time`axis
"""
function gapFillMSC(c;kwargs...)
  NpY=getNpY(c)
  mapCube(gapFillMSC,c,NpY;indims=InDims("Time"),outdims=OutDims("Time"),kwargs...)
end

function gapFillMSC(aout::AbstractVector,ain::AbstractVector,NpY::Integer;complete_msc=false)
  tmsc, tnmsc = zeros(Union{Float64,Missing},NpY),zeros(Int,NpY)
  fillmsc(1,tmsc,tnmsc,ain,NpY)
  if complete_msc
    fill_msc_poly!(tmsc)
  end
  replaceMisswithMSC(tmsc,ain,aout,NpY)
end

function fill_msc_poly!(tmsc)
  mscrep = [tmsc;tmsc;tmsc]
  n = length(tmsc)
  a = gapfillpoly!(mscrep, max_gap = n÷2, nbefore_after = max(3,n÷30))
  tmsc .= view(a,(n+1):(n+n))
end

gapfillpoly(x;max_gap=30,nbefore_after=10, polyorder = 2) =
  mapslices(gapfillpoly!,x,dims="Time",max_gap=max_gap, nbefore_after=nbefore_after, polyorder=polyorder)

"""
    fillgaps_poly(x;max_gap=30,nbefore_after=10, polyorder = 2)

Function for polnomial gap filling. Whenever a gap smaller than `max_gap` is found
the algorithm uses `nbefore_after` time steps before and after the gap to fit
a polynomial of order `polyorder`. The missing alues are then replaced by the
fitted polynomial.
"""
function gapfillpoly!(x;max_gap=30,nbefore_after=10, polyorder = 2)
    x = replace(i->(!ismissing(i) && isfinite(i)) ? i : missing,x)
    a = copy(x)
    workx = Float64[]
    worky = Float64[]
    # find first nonmissing value
    idxstart = findfirst(!ismissing,a)
    idxstart === nothing && return a
    while true
        #find next missing value
        gapstart = findnext(ismissing,a,idxstart)
        gapstart === nothing && break
        gapstop = findnext(!ismissing,a,gapstart)
        gapstop === nothing && break
        if gapstop-gapstart < max_gap
            idxfirst = max(1,gapstart - nbefore_after)
            idxlast  = min(length(a), gapstop + nbefore_after - 1)
            idxr = idxfirst:idxlast
            for (ii,idx) in enumerate(idxr)
                if !ismissing(x[idx])
                    push!(workx,idxr[ii])
                    push!(worky,x[idx])
                end
            end
            if length(workx)>polyorder
                p = fit(workx,worky,polyorder)
                for idx in gapstart:(gapstop-1)
                    a[idx] = p(idx)
                end
            end
        end
        idxstart = gapstop
        empty!(workx)
        empty!(worky)
    end
    a
end


"""
    getMSC(c)

Returns the mean annual cycle from each time series.

**Input Axis** `Time`axis

**Output Axis** `MSC`axis

"""
function getMSC(c;kwargs...)
  N = getNpY(c)
  outdims = OutDims(DD.Dim{:MSC}(DateTime(1900):Day(ceil(Int,366/N)):DateTime(1900,12,31,23,59,59)), 
  outtype = mscouttype(eltype(c)))
  indims = InDims("Time")
  mapCube(getMSC,c,getNpY(c);indims=indims,outdims=outdims,kwargs...)
end

mscouttype(T) = Base.nonmissingtype(T)
mscouttype(::Type{<:Union{Missing,Integer}}) = Float64

function getMSC(aout::AbstractVector,ain::AbstractVector,NpY;imscstart::Int=1)
    nmsc = zeros(Int,NpY)
    fillmsc(imscstart,aout,nmsc,ain,NpY)
end



"Subtracts given msc from input vector"
function subtractMSC(msc::AbstractVector,xin::AbstractVector,xout,NpY)
    imsc=1
    ltime=length(xin)
    for i in 1:ltime
        xout[i] = xin[i]-msc[imsc]
        imsc =imsc==NpY ? 1 : imsc+1 # Increase msc time step counter
    end
end

"Replaces missing values with mean seasonal cycle"
function replaceMisswithMSC(msc::AbstractVector,xin::AbstractArray,xout::AbstractArray,NpY::Integer)
  imsc=1
  for i in eachindex(xin)
    if ismissing(xin[i]) && !ismissing(msc[imsc])
      xout[i]=msc[imsc]
    else
      xout[i]=xin[i]
    end
    imsc= imsc==NpY ? 1 : imsc+1 # Increase msc time step counter
  end
end

"""
    getMedMSC(c)

Returns the median annual cycle from each time series.

**Input Axis** `Time`axis

**Output Axis** `MSC`axis
"""
function getMedSC(c;kwargs...)
  N = getNpY(c)
  outdims = OutDims(DD.Dim{:MSC}(DateTime(1900):Day(ceil(Int,366/N)):DateTime(1900,12,31,23,59,59)), 
  outtype = mscouttype(eltype(c)))
  indims = InDims("Time")
  mapCube(getMedSC,c;indims=indims,outdims=outdims,kwargs...)
end

function getMedSC(aout::AbstractVector{Union{T,Missing}},ain::AbstractVector) where T
    #Reshape the cube to squeeze unimportant variables
    NpY=length(aout)
    yvec=T[]
    q=[convert(T,0.5)]
    for doy=1:NpY
        empty!(yvec)
        for i=doy:NpY:length(ain)
            ismissing(ain[i]) || isnan(ain[i]) || push!(yvec,ain[i])
        end
        aout[doy] = isempty(yvec) ? missing : quantile!(yvec,q)[1]
    end
    aout
end


"Calculates the mean seasonal cycle of a vector"
function fillmsc(imscstart::Integer,msc::AbstractVector,nmsc::AbstractVector,xin::AbstractVector,NpY)
  imsc=imscstart
  fill!(msc, 0)
  fill!(nmsc,0)
  for v in xin
    if !ismissing(v)
      msc[imsc]  += v
      nmsc[imsc] += 1
    end
    imsc=imsc==NpY ? 1 : imsc+1 # Increase msc time step counter
  end
  for i in 1:NpY msc[i] = nmsc[i] > 0 ? msc[i]/nmsc[i] : missing end # Get MSC by dividing by number of points
end
