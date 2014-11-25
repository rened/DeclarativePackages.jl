using DeclarativePackages
using Base.Test

test(name, r, value) = test(name, r, x->x==value)
function test(name, r, f::Function)
	if !f(r)
		println("Test '$name' failed")
		@show r
		exit(1)
	end
end


decdir = "$(homedir())/.julia/declarative/"
existinginstallation = exists(decdir)

jdp = Pkg.dir("DeclarativePackages/bin/jdp")
function runjdp(file)
	file = Pkg.dir("DeclarativePackages")*"/test/"*file
	listpackages = Pkg.dir("DeclarativePackages")*"/test/listpackages.jl"

	println("Testing $file")
 	tmp = tempname()
	run(`touch $tmp`)
	cp(file, tmp)
	ENV["DECLARE"] = tmp
	ENV["DECLARE_VERBOSITY"] = 0
    r = readall(`$jdp $listpackages`)
	rm(tmp)
	r
end

test("empty", runjdp("DECLARE.empty"), "")
test("METADATA1", runjdp("DECLARE.METADATA1"), "")
test("METADATA2", runjdp("DECLARE.METADATA2"), "")
test("JSON1", runjdp("DECLARE.JSON1"), "JSON 0.3.9\n")
test("JSON2", runjdp("DECLARE.JSON2"), "JSON 0.3.7\n")
test("HDF51", runjdp("DECLARE.HDF5_1"), x->ismatch(r"HDF5 0\.4\.5",x))
test("HDF52", runjdp("DECLARE.HDF5_2"), x->ismatch(r"HDF5 0\.4\.5",x) && ismatch(r"DeclarativePackages 0\.0\.0-",x))

if !existinginstallation
	run(`chmod -R a+w $decdir`)
	run(`rm -rf $decdir`)
end
