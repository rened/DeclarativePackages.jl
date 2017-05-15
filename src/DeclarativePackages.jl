module DeclarativePackages

export exportDECLARE, exists, log

if VERSION < v"0.5.0"
    readstring = readall
end

exists(filename::AbstractString) = (s = stat(filename); s.inode!=0)

import Base.log
log(level, a) = if haskey(ENV, "DECLARE_VERBOSITY") && parse(Int,ENV["DECLARE_VERBOSITY"])>=level println(); println(a) end

type Spec
    selector
    package
    commit
end
string(a::Spec) = "$(a.selector)$(isempty(a.selector) ? "" : " ")$(a.package) $(a.commit)"

function exportDECLARE(filename = "DECLARE")
    specs, osspecific = generatespecs()
    log(2, "exportDECLARE: $specs")
    log(2, "exportDECLARE: $osspecific")

    os = map(x -> string(x[2]), osspecific)
    if exists(filename)
        newselectors = unique(map(x -> x[2].selector, osspecific))
        existingspecs = split(strip(readstring(filename)), '\n')
        existingspecs = filter(x -> length(x)>0 && split(x)[1][1]=='@' && !in(split(x)[1], newselectors), existingspecs)
        append!(os, existingspecs)
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

    requires = [try readstring(Pkg.dir(first(x))*"/REQUIRE") catch "" end for x in Pkg.installed()]
    requires = unique(vcat(map(x->collect(split(x,'\n')), requires)...))
    requires = filter(x->!isempty(x) && !ismatch(r"^julia", x), requires)
    a = map(x->split(x)[end], requires)
    b = map(x->x[1]=='@' ? split(x)[1] : "", requires)
    selectors = Dict{Any,Any}(zip(a,b))
    getsel(pkg) = haskey(selectors, pkg) ? selectors[pkg] : ""
 
    metapkgs = Any[]
    giturls = Any[]
    osspecific = Any[]
    for pkg in packages
        dir = Pkg.dir(pkg)
        git = ["git", "-C", dir, "--git-dir=$dir/.git"]
        url = strip(readstring(`$git config --get remote.origin.url`))
        metaurl = ""
        try metaurl = strip(readstring(Pkg.dir("METADATA")*"/$pkg/url")) catch end
        log(2, "generatespecs: url: $url  metaurl: $metaurl")
        if url==metaurl
            url = pkg
        end
        commit = strip(readstring(`$git log -n 1 --format="%H"`))
        # remote = strip(readstring(`$git remote`))
        # remote = split(remote)[end]
        # branch = strip(readstring(`$git rev-parse --abbrev-ref HEAD`))
        version = split(strip(readstring(`$git name-rev --tags --name-only $commit`)),"^")[1]
        onversion = version != "undefined"
        # isahead = ismatch(r"^pinned.*tmp", branch) ? false : !isempty(strip(readstring(`$git log $remote/$branch..HEAD`)))
        status = split(strip(readstring(`$git status -s`)), "\n")
        status = filter(x->!ismatch(r"deps",x) && length(x)>0 && !contains(x,"built.by.declarepackages.jl"), status)
        isdirty = length(status) > 0

        if pkg != "METADATA" && isdirty
            error("$status -- Cannot create a jdp declaration from the currently installed packages as '$dir' has local changes.\nPlease commit these changes, then run 'jdp' again.")
        end
        log(2, "generatespecs: pkg: $pkg getsel: $(getsel(pkg)) url: $url")
        list = isempty(getsel(pkg)) ? (url ==  pkg ? metapkgs : giturls) : osspecific
        spec = Spec(getsel(pkg), url, onversion ? version[2:end] : commit)
        log(2, "generatespecs: $spec")
        push!(list, (pkg, spec))
    end

    specs = Any[]
    if !(isempty(metapkgs))
        append!(specs, metapkgs[sortperm(map(first,metapkgs))])
    end
    if !(isempty(giturls))
        append!(specs, giturls[sortperm(map(first,giturls))])
    end
    (specs, osspecific)
end
 
end
