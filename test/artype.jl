using EarthDataLab
using Test
import DataFrames: DataFrame,aggregate
import Dates: year
import Statistics: cor, mean

@testset "Dataframe representation" begin
c=Cube()

d = getCubeData(c,variable=["air_temperature_2m","gross_primary_productivity"],longitude=(10,11),latitude=(50,51),
                time=(Date("2002-01-01"),Date("2008-12-31")))

dmem=readcubedata(d)

function docor(xout,xin)
    #Inside this function, xin is now a data frame
    @test isa(xin,DataFrame)
    xout[1]=cor(xin[:air_temperature_2m],xin[:gross_primary_productivity])
end
indims = InDims(TimeAxis,VariableAxis,artype = AsDataFrame())
outdims = OutDims()
o = mapCube(docor,dmem,indims=indims,outdims=outdims)

@test all(isapprox.(o.data,[cor(dmem.data[i,j,:,1],dmem.data[i,j,:,2]) for i=1:4, j=1:4]))

function annMean(xout,xin)
    #xin is now a DataFrame where time is added as the third column
    #We derive the year and add it to the dataframe
    xin[!,:year] = year.(xin[!,:Time])
    #Now we do the annual aggregation, note that we have to exclude the time column, because we can't aggregate here
    x2 = aggregate(xin[!,[1,2,4]],:year,a->mean(skipmissing(a)))
    #We copy the results to our output
    xout[:,1] = x2[!,2]
    xout[:,2] = x2[!,3]
end
indims = InDims("time","var",artype=AsDataFrame(true))
outdims = OutDims(RangeAxis("Year",2002:2008),"var")

o = mapCube(annMean,dmem,indims=indims,outdims=outdims)

@test all(isapprox.(o.data[1,1,:,:],mean(dmem.data[:,:,1:46,1],dims=3)))
end
