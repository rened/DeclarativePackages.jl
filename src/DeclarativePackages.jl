module DeclarativePackages

export exportDECLARE

type Spec
	selector
	package
	commit
end
string(a::Spec) = "$(a.selector)$(isempty(a.selector) ? "" : " ")$(a.package) $(a.commit)"

function exportDECLARE(filename = "DECLARE")
	specs, osspecific = generatespecs()
	os = map(x -> string(x[2]), osspecific)
	try
		newselectors = unique(map(x -> x[2].selector, osspecific))
		existingspecs = split(strip(readall(filename)), '\n')
		keeping = filter(x -> split(x)[1][1]=='@' && !in(split(x)[1], newselectors), existingspecs)
		append!(os, keeping)
	catch
	end
	open(filename,"w") do io 
		map(x->println(io, string(x[2])), specs)
		map(x->println(io, x), sort(os))
	end
	nothing
end

function generatespecs()
	packages = collect(keys(Pkg.installed()))
	packages = filter(x->x!="DeclarativePackages", packages)
	push!(packages, "METADATA")

 	requires = map(x->readall(Pkg.dir(first(x))*"/REQUIRE"), Pkg.installed())
	requires = unique(vcat(map(x->collect(split(x,'\n')), requires)...))
	requires = filter(x->!isempty(x) && !ismatch(r"^julia", x), requires)
	selectors = Dict(map(x->split(x)[end], requires), map(x->x[1]=='@' ? split(x)[1] : "", requires))
	getsel(pkg) = haskey(selectors, pkg) ? selectors[pkg] : ""
 
	metapkgs = {}
	giturls = {}
	osspecific = {}
	for pkg in packages
		dir = Pkg.dir(pkg)
		git = ["git", "--git-dir=$dir/.git"]
		url = strip(readall(`$git config --get remote.origin.url`))
		metaurl = ""
		try metaurl = strip(readall(Pkg.dir("METADATA")*"/$pkg/url")) catch end
		if url==metaurl
			url = pkg
		end
		commit = strip(readall(`$git log -n 1 --format="%H"`))
		remote = strip(readall(`$git remote`))
		branch = strip(readall(`$git rev-parse --abbrev-ref HEAD`))
		version = split(strip(readall(`$git name-rev --tags --name-only $commit`)),"^")[1]
		onversion = version != "undefined"
		isahead = ismatch(r"^pinned.*tmp", branch) ? false : !isempty(strip(readall(`$git log $remote/$branch..HEAD`)))
		if isahead
			error("Cannot create a jdp declaration from the currently installed packages as '$pkg' has local commits ahead of origin.\nPush those commits, then run 'jdp' again.")
		end
		list = isempty(getsel(pkg)) ? (url ==  pkg ? metapkgs : giturls) : osspecific 
		push!(list, (pkg, Spec(getsel(pkg), url, onversion ? version[2:end] : commit)))
	end

	specs = {}
	if !(isempty(metapkgs))
		append!(specs, metapkgs[sortperm(map(first,metapkgs))])
	end
 	if !(isempty(giturls))
		append!(specs, giturls[sortperm(map(first,giturls))])
	end
	(specs, osspecific)
end
 
end
