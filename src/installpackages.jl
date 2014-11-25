include("DeclarativePackages.jl")
using DeclarativePackages

if !haskey(ENV, "DECLARE_VERBOSITY")
	ENV["DECLARE_VERBOSITY"] = 1
end

function installpackages()
	lines = readfile()
    init(lines)
    packages = parselines(lines)
    install(packages)
	resolve(packages)
	finish()
end

function readfile()
	log(1, "Parsing $(ENV["DECLARE"]) ... ")
	lines = split(readall(ENV["DECLARE"]), '\n')
	lines = map(x->replace(x, r"#.*", ""), lines)
	lines = filter(x->!isempty(x), lines)
	return lines
end

pkgpath(basepath, pkg) = normpath(basepath*"/v$(VERSION.major).$(VERSION.minor)/$pkg/")
markreadonly(path) = run(`chmod -R a-w $path`)
stepout(path, n) = normpath(path*"/"*repeat("../",n))

function hardlinkdirs(existingpath, path) 
	log(3, "hardlinking: existingpath: $existingpath\npath: $path")
	assert(existingpath[end]=='/')
	assert(path[end]=='/')
	mkpath(path)
	readdirabs(path) = map(x->(x, path*x), readdir(path))
	items = readdirabs(existingpath)
	for dir in filter(x->isdir(x[2]), items)
	    hardlinkdirs(dir[2]*"/", path*dir[1]*"/")
	end
	for file in filter(x->!isdir(x[2]), items)
		@osx_only ccall((:link, "libc"), Int, (Ptr{Uint8}, Ptr{Uint8}), file[2] , path*file[1])
		@linux_only ccall((:link, "libc.so.6"), Int, (Ptr{Uint8}, Ptr{Uint8}), file[2] , path*file[1])
	end
end


gitcmd(path, cmd) = `git --git-dir=$path.git --work-tree=$path $(split(cmd))`
function gitcommitof(path)
	log(2, "gitcommitof $path")
	cmd = gitcmd(path, "log -n 1 --format=%H")
	log(2, "gitcommitof cmd $cmd")
	r = strip(readall(cmd))
	log(2, "gitcommitof result $r")
	r
end

function gitclone(name, url, path, commit="")
	log(2, "gitclone: name: $name url: $url path: $path commit: $commit")
	run(`git clone $url $path`)
	if isempty(commit)
		commit = gitcommitof(path)
	else
		# check if the repo knows this commit. if not, check in METADATA
		isknown = ismatch(Regex(commit), readall(gitcmd(path, "tag")))
		if !isknown
			filename = Pkg.dir("METADATA/$name/versions/$(commit[2:end])/sha1")
			if exists(filename)
				commit = strip(readall(filename))
			else
				if commit[1] == 'v'
					error("gitclone: Could not find a commit hash for version $commit for package $name ($url)")
				end
			end
		end
	end
		
	run(gitcmd(path, "checkout --force -b pinned.$commit.tmp $commit"))
end


function existscheckout(pkg, commit)
	basepath = stepout(Pkg.dir(), 2)
    dirs = readdir(basepath)
	nontmp = filter(x->length(x)>3 && x[1:4]!="tmp_", dirs)
    for dir in nontmp
		path = pkgpath(basepath*dir, pkg) 
		if exists(path) &&  gitcommitof(path) == commit
			log(2, "existscheckout: found $path for $pkg@$commit")
			return path
		end
	end
    return ""
end

function init(lines)
	ENV["JULIA_PKGDIR"] = normpath(Pkg.dir()*"/../../tmp_"*randstring(32))
	metadata = filter(x->ismatch(r"METADATA.jl", x), lines)
	commit = ""
	if length(metadata)>0
		assert(length(metadata)==1)
		m = split(metadata[1])
		url = split(metadata[1])[1]
		length(m) > 1 ? commit = m[2] : ""
		log(2, "Found URL $url$(isempty(commit) ? "" : "@$commit") for METADATA")
	else
		url = "https://github.com/JuliaLang/METADATA.jl.git"
	end
    mkpath(Pkg.dir())
	path = Pkg.dir("METADATA/")
	installorlink("METADATA", url, path, commit)
	markreadonly(Pkg.dir("METADATA"))
end


parselines(lines) = filter(x->isa(x,Package), map(parseline, lines))
function parseline(a)
	parts = split(strip(a))

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

function installorlink(name, url, path, commit)
	log(2, "Installorlink: $name $url $commit $path")
	existingpath = existscheckout(name, commit)
	if isempty(existingpath)
		gitclone(name, url, path, commit)
	else
		log(1, "Linking $(name) ...")
		hardlinkdirs(existingpath, path)
	end
end

function install(a::Package)
 	path = Pkg.dir(a.name*"/")

	version(a) = VersionNumber(map(int, split(a, "."))...)
	latest() = "v"*string(maximum(map(version, readdir(Pkg.dir("METADATA/$(a.name)/versions/")))))
	metadatacommit(version) = strip(readall(Pkg.dir("METADATA/$(a.name)/versions/$(version[2:end])/sha1")))
	
	commit = a.commit == "METADATA" ? latest() : a.commit
	installorlink(a.name, a.url, path, commit)
end

function resolve(packages)
	open(Pkg.dir()*"/REQUIRE","w") do io
		for pkg in packages
			if !isempty(pkg.commit) && pkg.commit[1]=='v'
				m,n,o = map(int, split(pkg.commit[2:end], '.'))
				versions = "$m.$n.$o $m.$n.$(o+1)-"
			else
				versions = ""
			end
			log(3, "writing REQUIRE: $(pkg.os) $(pkg.name) $versions\n")
			write(io, "$(pkg.os) $(pkg.name) $versions\n")
		end
	end
	log(1, "Invoking Pkg.resolve() ...")
	Pkg.resolve()
end


function finish()
	exportDECLARE(ENV["DECLARE"])

    @osx_only md5 = strip(readall(`md5 -q $(ENV["DECLARE"])`))
    @linux_only md5 = strip(readall(`md5sum $(ENV["DECLARE"])`))
	md5 = split(md5)[1]
	dir = normpath(Pkg.dir()*"/../../"*md5)

	if exists(dir) 
		run(`chmod -R a+w $dir`)
		rm(dir; recursive=true)
	end
    mv(normpath(Pkg.dir()*"/../"), dir)
	ENV["JULIA_PKGDIR"] = dir

	log(1, "Marking $dir read-only ...")
	run(`chmod -R 555 $dir`)
	run(`find $dir -name .git -exec chmod -R a+w {} \;`)
	run(`chmod 755 $dir`)

	log(1, "Finished installing packages for $(ENV["DECLARE"]).")
end

installpackages()





