include("DeclarativePackages.jl")
using DeclarativePackages

function installpackages()
	lines = readfile()
    init(lines)
    packages = parselines(lines)
    install(packages)
	resolve(packages)
	finish()
end

function readfile()
	print("Parsing $(ENV["DECLARE"]) ... ")
	lines = split(readall(ENV["DECLARE"]), '\n')
	lines = map(x->replace(x, r"#.*", ""), lines)
	lines = filter(x->!isempty(x), lines)
	println("ok")
	return lines
end

function init(lines)
	ENV["JULIA_PKGDIR"] = normpath(Pkg.dir()*"/../../tmp_"*randstring(32))
	metadata = filter(x->ismatch(r"METADATA.jl", x), lines)
	commit = ""
	if length(metadata)>0
		assert(length(metadata)==1)
		m = split(metadata[1])
		url = split(metadata[1])[1]
		length(m) > 1 ? commit = m[2] : nothing
		println("Found URL $url for METADATA")
	else
		url = "https://github.com/JuliaLang/METADATA.jl.git"
	end
	println("Cloning METADATA ...")
    mkpath(Pkg.dir())
	path = Pkg.dir("METADATA")
    run(`git clone $url $path`)
	if !isempty(commit)
	    run(`git --git-dir=$path/.git --work-tree=$path reset --hard $commit`)
	end
	run(`chmod -R a-w $(Pkg.dir())/METADATA`)
end


parselines(lines) = filter(x->isa(x,Package), map(parseline, lines))
function parseline(a)
	parts = split(a)

	if parts[1][1] == '@'
		os = parts[1]
		shift!(parts)
	else
		os = ""
	end

	nameorurl = parts[1]
	if contains(nameorurl, "/")
		url = nameorurl
		name = replace(replace(split(url, "/")[end], ".git", ""), ".jl", "")
		isregistered = false
	else
		name = nameorurl
		url = strip(readall("$(Pkg.dir())/METADATA/$name/url"))
		isregistered = true
	end
	if name=="METADATA"
		return []
	end

	commit = length(parts)>1 ? parts[2] : (isregistered ? "METADATA" : "")
	if length(split(commit,"."))==3
		commit = "v"*commit
	end
	return Package(os, name, url, commit, isregistered)
end

function checkout(url, commit)
end

type Package
	os
	name
	url
	commit
	isregistered
end

function install(packages::Array)
	osx = filter(x->x.os=="@osx", packages)
	unix = filter(x->x.os=="@unix", packages)
	linux = filter(x->x.os=="@linux", packages)
	windows = filter(x->x.os=="@windows", packages)
	everywhere = filter(x->x.os=="", packages)
	@osx_only map(install, osx)
	@unix_only map(install, unix)
	@linux_only map(install, linux)
	@windows_only map(install, windows)
	map(install, everywhere)
end

function install(a::Package)
 	path = Pkg.dir(a.name)
 	run(`git clone $(a.url) $path`)
	git = ["git", "--git-dir=$path/.git", "--work-tree=$path"]

	version(a) = VersionNumber(map(int, split(a, "."))...)
	latest() = "v"*string(maximum(map(version, readdir(Pkg.dir("METADATA/$(a.name)/versions")))))
	metadatacommit(version) = strip(readall(Pkg.dir("METADATA/$(a.name)/versions/$(version[2:end])/sha1")))
	
	commit = isempty(a.commit) ? strip(readall(`$git log -n 1 --format="%H"`)) : (a.commit == "METADATA" ? latest() : a.commit)
    run(`$git checkout --force -b pinned.$commit.tmp $(a.commit == "METADATA" ? metadatacommit(commit) : commit)`)
end

function resolve(packages)
	open(Pkg.dir()*"/REQUIRE","w") do io
		for pkg in packages
			write(io, "$(pkg.os) $(pkg.name)\n")
		end
	end
	Pkg.resolve()
end


function finish()
	exportDECLARE(ENV["DECLARE"])

    @osx_only md5 = strip(readall(`md5 -q $(ENV["DECLARE"])`))
    @linux_only md5 = strip(readall(`md5sum $(ENV["DECLARE"])`))
	md5 = split(md5)[1]
	dir = normpath(Pkg.dir()*"/../../"*md5)

	#@show normpath(Pkg.dir()*"/../") dir
	try	rm(dir; recursive=true)	catch end
    mv(normpath(Pkg.dir()*"/../"), dir)
	ENV["JULIA_PKGDIR"] = dir

	print("Marking $dir read only ...")
	run(`chmod -R 555 $dir`)
	run(`find $dir -name .git -exec chmod -R a+w {} \;`)
	run(`chmod 755 $dir`)
	println(" done")

	println("Finished installing packages from $(ENV["DECLARE"]).")
end

installpackages()





