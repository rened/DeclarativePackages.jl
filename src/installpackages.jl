include("DeclarativePackages.jl")

Pkg.init()
Pkg.add("Compat")
using DeclarativePackages, Compat

if VERSION < v"0.5.0"
    readstring = readall
end

if !haskey(ENV, "DECLARE_VERBOSITY")
    ENV["DECLARE_VERBOSITY"] = 1
end

function installpackages()
    lines = readfile()
    init(lines)
    packages = parselines(lines)
    needbuilding = install(packages)
    resolve(packages, needbuilding)
    finish()
end

function readfile()
    log(1, "Parsing $(ENV["DECLARE"]) ... ")
    lines = split(readstring(ENV["DECLARE"]), '\n')
    lines = map(x->replace(x, r"#.*", ""), lines)
    lines = filter(x->!isempty(x), lines)
    return lines
end

pkgpath(basepath, pkg) = normpath(basepath*"/v$(VERSION.major).$(VERSION.minor)/$pkg/")
markreadonly(path) = run(`chmod a-w $path`)
stepout(path, n=1) = normpath(path*"/"*repeat("../",n))

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
        hardlinkfile(file[2] , path*file[1])
    end
end

function hardlinkfile(from, to)
    @static if is_apple() ccall((:link, "libc"), Int, (Ptr{UInt8}, Ptr{UInt8}), from, to) end
    @static if is_linux() ccall((:link, "libc.so.6"), Int, (Ptr{UInt8}, Ptr{UInt8}), from, to) end
end


gitcmd(path, cmd) = `git --git-dir=$path.git --work-tree=$path $(split(cmd))`
function gitcommitof(path)
    log(2, "gitcommitof $path")
    cmd = gitcmd(path, "log -n 1 --format=%H")
    log(2, "gitcommitof cmd $cmd")
    r = try
        strip(readstring(cmd))
    catch
        ""
    end
    log(2, "gitcommitof result $r")
    r
end

function gitcommitoftag(path, tag)
    contains(path, "METADATA") && return ""
    length(tag) > 1 && tag[1] != 'v' && return ""
    cmd = gitcmd(path, "rev-list -n 1 $tag")
    strip(readstring(cmd))
end

function gitclone(name, url, path, commit="")
    log(2, "gitclone: name: $name url: $url path: $path commit: $commit")
    run(`git clone $url $path`)
    if isempty(commit)
        commit = gitcommitof(path)
    else
        # check if the repo knows this commit. if not, check in METADATA
        isknown = ismatch(Regex(commit), readstring(gitcmd(path, "tag")))
        if !isknown
            filename = Pkg.dir("METADATA/$name/versions/$(commit[2:end])/sha1")
            if exists(filename)
                commit = strip(readstring(filename))
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
    log(2, "######## existscheckout $pkg $commit")
    basepath = stepout(Pkg.dir(), 2)
    dirs = readdir(basepath)
    nontmp = filter(x->length(x)>3 && x[1:4]!="tmp_", dirs)
    log(2, "  nontmp dirs: $nontmp")
    for dir in nontmp
        path = pkgpath(basepath*dir, pkg) 
        !exists(path) && continue
        existingcommit = gitcommitof(path) 
        existingtagcommit = try gitcommitoftag(path, commit) catch "" end
        log(2, "  existinging commit / existingtagcommit / wanted commit:  $existingcommit / $existingtagcommit / $commit")
        if exists(path) && (existingcommit == commit || existingcommit == existingtagcommit)
            log(2, "existscheckout: found $path for $pkg@$commit")
            return path
        end
    end
    return ""
end

function init(lines)
    tmpdir = "tmp_$(randstring(32))"
    ENV["JULIA_PKGDIR"] = normpath(Pkg.dir()*"/../../$tmpdir")
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
        url = strip(readstring("$(Pkg.dir())/METADATA/$name/url"))
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
    @static if is_apple() map(install, osx) end
    @static if is_unix() map(install, unix) end
    @static if is_linux() map(install, linux) end
    @static if is_windows() map(install, windows) end
    needbuilding = filter(x->x!=nothing, map(install, everywhere))
end

function installorlink(name, url, path, commit)
    log(2, "Installorlink: $name $url $commit $path")
    existingpath = existscheckout(name, commit)
    if isempty(existingpath)
        gitclone(name, url, path, commit)
        return name
    else
        log(1, "Linking $(name) ...")
        hardlinkdirs(existingpath, path)
        
        # link the compiled module, too
        # @show name url path commit existingpath path
        # if name != "METADATA"
            # v = "v$(VERSION.major).$(VERSION.minor)"
            # from = joinpath("/",split(existingpath,"/")[1:end-3]..., "lib", v, name*".ji")
            # todir = joinpath("/",split(path        ,"/")[1:end-3]..., "lib", v)
            # mkpath(todir)
            # to =  joinpath(todir, name*".ji")
            # @show from to
            # hardlinkfile(from, to)
        # end
        return
    end
end

function install(a::Package)
    path = Pkg.dir(a.name*"/")

    version(a) = VersionNumber(map(x->parse(Int,x), split(a, "."))...)
    function latest()
        versionsdir = Pkg.dir("METADATA/$(a.name)/versions/")
        if exists(versionsdir)
            "v"*string(maximum(map(version, readdir(versionsdir))))
        else
            ""
        end
    end
    metadatacommit(version) = strip(readstring(Pkg.dir("METADATA/$(a.name)/versions/$(version[2:end])/sha1")))

    commit = a.commit == "METADATA" ? latest() : a.commit
    installorlink(a.name, a.url, path, commit)
end

function resolve(packages, needbuilding)
    requirename = Pkg.dir()*"/REQUIRE"
    log(3, requirename)
    open(requirename,"w") do io
        for pkg in packages
            if !isempty(pkg.commit) && pkg.commit[1]=='v'
                m,n,o = map(x->parse(Int,x), split(split(pkg.commit[2:end],'~')[1], '.'))
                versions = "$m.$n.$o $m.$n.$(o+1)-"
            else
                versions = ""
            end
            log(3, "writing REQUIRE: $(pkg.os) $(pkg.name) $versions\n")
            write(io, "$(pkg.os) $(pkg.name) $versions\n")

            # add test dependencies
            if haskey(ENV, "DECLARE_INCLUDETEST") && ENV["DECLARE_INCLUDETEST"]=="true"
                testrequire = Pkg.dir(pkg.name*"/test/REQUIRE")
                if exists(testrequire)
                    write(io, readstring(testrequire))
                end
            end
        end
    end
    log(1, "Invoking Pkg.resolve() ...")
    Pkg.resolve()
    map(buildifnecessary, needbuilding)
end

function buildifnecessary(x)
    depsdir = Pkg.dir(x,"deps")
    buildscript = joinpath(depsdir, "build.jl")
    declarebuilt = joinpath(depsdir, "built.by.declarepackages.jl")
    exists(buildscript) || return
    exists(declarebuilt) && return
    Pkg.build(x)
    touch(declarebuilt)
end


function finish()
    exportDECLARE(ENV["DECLARE"])

    @static if is_apple() md5 = strip(readstring(`md5 -q $(ENV["DECLARE"])`)) end
    @static if is_linux() md5 = strip(readstring(`md5sum $(ENV["DECLARE"])`)) end
    md5 = split(md5)[1]
    if haskey(ENV, "DECLARE_INCLUDETEST") && ENV["DECLARE_INCLUDETEST"]=="true"
        md5 = md5*"withtest"
    end
    dir = normpath(Pkg.dir()*"/../../"*md5*"-$(VERSION.major).$(VERSION.minor)")
    
    if exists(dir) 
        run(`chmod -R a+w $dir`)
        rm(dir; recursive=true)
    end
    mv(stepout(Pkg.dir(),1), dir)
    symlink(dir, stepout(Pkg.dir())[1:end-1])
    ENV["JULIA_PKGDIR"] = dir

    cp(ENV["DECLARE"], joinpath(dir,"DECLARE"))

    log(1, "Marking $dir read-only ...")
    run(pipeline(`find $dir -maxdepth 1`,`xargs chmod 555 `))
    run(`chmod 755 $dir`)

    log(1, "Finished installing packages for $(ENV["DECLARE"]).")
end

installpackages()





