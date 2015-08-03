using DeclarativePackages
using Base.Test

test(name, r, value) = test(name, r, x->x==value)
function test(name, r, f::Function)
    a = filter(x->length(x)>7 && x[1:7]!="Cloning", split(r[1], '\n'))
    a = filter(x->length(x)>4 && x[1:4]!="http", a)
    a = join(a)
    r2 = (a,r[2])
    if !f(r2)
        println("Test '$name' failed")
        println("the output was: ---------")
        @show r
        println("------ end of output")
        exit(1)
    end
end


decdir = "$(homedir())/.julia/declarative/"
existinginstallation = exists(decdir)

pathof(a...) = joinpath(dirname(@__FILE__), "..",a...)
jdp = pathof("bin/jdp")
function runjdp(file)
    file = pathof("test",file)
    listpackages = pathof("test/listpackages.jl")

    println("Testing $file")
    tmp = tempname()
    cp(file, tmp)
    ENV["DECLARE"] = tmp
    ENV["DECLARE_VERBOSITY"] = 0
    r = (readall(`$jdp $listpackages`), readall(tmp))
    rm(tmp)
    r
end

ENV["DECLARE_INCLUDETEST"] = ""
test("empty", runjdp("DECLARE.empty"), x->isempty(x[1]))
test("METADATA1", runjdp("DECLARE.METADATA1"), x->isempty(x[1]))
test("METADATA2", runjdp("DECLARE.METADATA2"), x->isempty(x[1]))
test("JSON1", runjdp("DECLARE.JSON1"), x->ismatch(r"JSON 0.3.9",x[2]))
test("JSON2", runjdp("DECLARE.JSON2"), x->ismatch(r"JSON 0.3.7",x[2]))
test("HDF51", runjdp("DECLARE.HDF5_1"), x->ismatch(r"HDF5 0\.4\.5",x[1]) && !ismatch(r"DataFrames", x[2]))
test("HDF52", runjdp("DECLARE.HDF5_2"), x->ismatch(r"HDF5 0\.4\.5",x[1]) && ismatch(r"DeclarativePackages 0\.0\.0-",x[1]))
test("HDF53", runjdp("DECLARE.HDF5_3"), x->ismatch(r"rened/HDF5",x[2]))
test("HDF54", runjdp("DECLARE.HDF5_4"), x->ismatch(r"HDF5 0\.4\.5",x[1]) && ismatch(r"rened/HDF5", x[2]))
ENV["DECLARE_INCLUDETEST"] = "true"
test("HDF55_withtest", runjdp("DECLARE.HDF5_1"), x->ismatch(r"DataFrames",x[1]))

if !existinginstallation
    run(`chmod -R a+w $decdir`)
    run(`rm -rf $decdir`)
end
