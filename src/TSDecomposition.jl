using FFTW: plan_fft!
using Statistics: mean, cov, var
using Distributed: workers, remotecall, fetch, myid

function linreg(x,y)
  b = cov(x,y)/var(x)
  a = mean(y) - b*mean(x)
  a,b
end

function detrendTS!(outar::AbstractMatrix,xin::AbstractVector{T}) where T
    x=collect(T,eachindex(xin))
    a,b=linreg(x,xin)
    for i in eachindex(xin)
        outar[i,1]=a+b*x[i]
    end
end

function tscale2ind(b::Float64,l::Int)
    i=round(Int,l/b+1)
    return i
end
mirror(i,l)=l-i+2

"""
    filterTSFFT(c)

Filter each time series using a Fourier filter and return the decomposed series
in 4 time windows (Trend, Long-Term Variability, Annual Cycle, Fast Oscillations)

**Input Axis** `Time`axis

**Output Axes** `Time`axis, `Scale`axis

"""
function filterTSFFT(c;kwargs...)
  indims = InDims("time",filter=AnyMissing())
  outdims = OutDims("time",CategoricalAxis("Scale",["Trend", "Long-Term Variability", "Annual Cycle", "Fast Oscillations"]))
  ntime = length(getAxis("Time",c))
  plans = map(workers()) do id
    remotecall(id,ntime,eltype(c)) do nt,et
      testar = zeros(Complex{Base.nonmissingtype(et)},nt)
      fftplan = plan_fft!(testar)
      ifftplan = inv(fftplan)
      fftplan, ifftplan
    end
  end
  plandict = Dict(zip(workers(), plans))
  mapCube(filterTSFFT,c,getNpY(c),plandict;indims=indims,outdims=outdims,kwargs...)
end

function filterTSFFT(outar::AbstractMatrix,y::AbstractVector, annfreq::Number,
  plandict; nharm::Int=3)

  fftplan, ifftplan = fetch(plandict[myid()])

    detrendTS!(outar,y)
    l        = length(y)

    fy       = Complex{Base.nonmissingtype(eltype(y))}[y[i]-outar[i,1] for i=1:l]
    fftplan * fy #Apply fftplan on fy inplace changes fy
    fyout    = similar(fy)
    czero    = zero(eltype(fy))

    #Remove annual cycle
    fill!(fyout,zero(eltype(fyout)))

    for jharm = 1:nharm
        iup=tscale2ind(annfreq*1.1/jharm,l)

        idown=tscale2ind(annfreq*0.9/jharm,l)

        for i=iup:idown
            fyout[i]  = fy[i]
            i2        = mirror(i,l)
            fyout[i2] = fy[i2]
            fy[i]     = czero
            fy[i2]    = czero
        end
    end

    ifftplan * fyout #Apply ifftplan on fyout inplace, changes fyout
    for i=1:l
        outar[i,3]=real(fyout[i])
    end

    iup   = tscale2ind(annfreq*1.1,l)
    idown = tscale2ind(annfreq*0.9,l)
    #Now split the remaining parts
    fill!(fyout,czero)
    for i=2:iup-1
        i2        = mirror(i,l)
        fyout[i]  = fy[i]
        fyout[i2] = fy[i2]
        fy[i]     = czero
        fy[i2]    = czero
    end
    ifftplan * fyout
    ifftplan * fy

    for i=1:l
        outar[i,2]=real(fyout[i])
        outar[i,4]=real(fy[i])
    end
end
