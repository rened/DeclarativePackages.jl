using DeclarativePackages
using Base.Test

if VERSION < v"0.5.0"
    readstring = readall
end

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
    r = (readstring(`$jdp $listpackages`), readstring(tmp))
    rm(tmp)
    r
end

ENV["DECLARE_INCLUDETEST"] = ""
test("empty", runjdp("DECLARE.empty"), x->isempty(x[1]))
test("METADATA1", runjdp("DECLARE.METADATA1"), x->isempty(x[1]))
test("METADATA2", runjdp("DECLARE.METADATA2"), x->isempty(x[1]))
test("JSON1", runjdp("DECLARE.JSON1"), x->contains(x[2],"JSON 0.3.9"))
test("JSON2", runjdp("DECLARE.JSON2"), x->contains(x[2],"JSON 0.3.7"))
test("HDF51", runjdp("DECLARE.HDF5_1"), x->contains(x[1],"HDF5 0.7.0") && !contains(x[2],"DataFrames"))
test("HDF52", runjdp("DECLARE.HDF5_2"), x->contains(x[1],"HDF5 0.7.0") && contains(x[2],(VERSION < v"0.5.0" ? "SHA 0.2.2" : "staticfloat/SHA.jl.git 0.2.2")))
test("HDF53", runjdp("DECLARE.HDF5_3"), x->contains(x[2],"HDF5.jl.git 0.7.0") && contains(x[2],"rened/HDF5"))
ENV["DECLARE_INCLUDETEST"] = "true"
test("HDF55_withtest", runjdp("DECLARE.HDF5_1"), x->contains(x[1],"HDF5 0.7.0"))

if !existinginstallation
    run(`chmod -R a+w $decdir`)
    run(`rm -rf $decdir`)
end
