module DeclarativePackages

export exportDECLARE, exists, log

exists(filename::String) = (s = stat(filename); s.inode!=0)

import Base.log
log(level, a) = if haskey(ENV, "DECLARE_VERBOSITY") && parse(Int,ENV["DECLARE_VERBOSITY"])>=level println(a) end

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
        existingspecs = split(strip(readall(filename)), '\n')
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

    requires = map(x->try readall(Pkg.dir(first(x))*"/REQUIRE") catch "" end, Pkg.installed())
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
        git = ["git", "--git-dir=$dir/.git"]
        url = strip(readall(`$git config --get remote.origin.url`))
        metaurl = ""
        try metaurl = strip(readall(Pkg.dir("METADATA")*"/$pkg/url")) catch end
        log(2, "generatespecs: url: $url  metaurl: $metaurl")
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
        log(2, "generatespecs: pkg: $pkg getsel: $(getsel(pkg)) url: $url")
        list = isempty(getsel(pkg)) ? (url ==  pkg ? metapkgs : giturls) : osspecific 
        push!(list, (pkg, Spec(getsel(pkg), url, onversion ? version[2:end] : commit)))
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
