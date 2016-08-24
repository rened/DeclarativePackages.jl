[![Build Status](http://pkg.julialang.org/badges/DeclarativePackages_0.4.svg)](http://pkg.julialang.org/?pkg=DeclarativePackages&ver=0.4)
[![Build Status](http://pkg.julialang.org/badges/DeclarativePackages_0.5.svg)](http://pkg.julialang.org/?pkg=DeclarativePackages&ver=0.5)

**DeclarativePackages.jl**, or `jdp` for short, allows to declaratively specify which Julia packages a project should use, with exact version or commit details.

`jdp` will install the specified packages (if necessary) and start Julia with exactly these packages available. 

`jdp` is heavily inspired by the [nix package manager](http://nixos.org/nix/).

## Installation

You need to have `git` installed. Install the package and link `jdp` into a directory on your `PATH`, for example in `~/local/bin`:

```jl
Pkg.add("DeclarativePackages") 
symlink(Pkg.dir("DeclarativePackages")*"/bin/jdp",  "$(homedir())/local/bin/jdp")
```

## Usage

Simply create a `DECLARE` file in your project's directory and invoke `jdp` in that directory instead of `julia`. 

Example for a `DECLARE` file:
```yaml
# Julia packages:  Packagename [ version or commit hash]
JSON
HDF5 0.4.6
Images 86a43d8368

# Any Git URL:  URL [ version or commit hash ]
https://github.com/JuliaLang/BinDeps.jl.git
https://github.com/timholy/HDF5.jl.git 0.4.6
https://github.com/jakebolewski/LibGit2.jl.git dcbf6f2419f92edeae4014f0a293c66a3c053671
```

You can change both the name of the `DECLARE` file as well as the `julia` binary called via environment variables. All arguments after `jdp` will be passed on to Julia:

```bash
DECLARE=mydeclarations.txt DECLARE_JULIA=/usr/bin/juliafromgit jdp -e "println(123)"
```
To launch IJulia make sure that `IJulia` is listed in your `DECLARE` file and start Julia like this:

```bash
jdp -e "using IJulia; notebook()"
```

If you would like to initially create a `DECLARE` file based on your currently installed packages, run:

```bash
julia -e "using DeclarativePackages; exportDECLARE()"
```
Finally, `git add DECLARE` and track the set of installed packages along with your code!

### How to update packages

You will see that your `DECLARE` files get auto-updated if not all packages details are fully specified. There is also an entry for `METADATA`, the repo where Julia gets the information about available packages from, fixed at a commit.

There are several ways to update a package by editing `DECLARE`:

* You can change the version number or commit hash.
* You can remove the package and, in the case that another package requires it, have `jdp` update it to the version `Pkg.add()` would pick.
* As long as `DECLARE` contains a line fixing `METADATA` to a specific commit, packages can only be updated using the versions listed therein.
* You can use `METADATA` corresponding to a different commit hash (simply change it), or delete the line containing `METADATA` to pull in the newest `METADATA`. 

If you want to only control a few packages and update the rest automatically, you can keep a second declaration file, e.g. `DECLARE.minimal`, containing only the minumum you want to specify:

```
HDF5 0.4.0
Images
```
Running `cp DECLARE.minimal DECLARE; jdp` will then update the rest of the required dependencies to the newest versions. And as you have `DECLARE` in your `git` repo, you can always go back.

### Parameters

`jdp` can be influenced using the following environment variables:

* `DECLARE_JULIA` - path of the Julia executable
* `DECLARE` - path of the DECLARE file to be used
* `DECLARE_VERBOSITY` - control dignostic output. 0==quiet, 1==default, 2==debug, 3==chatty
* `DECLARE_INCLUDETEST` - include all dependencies in the packages' `test/REQUIRE` files

## Uninstall

Remove the symlink to `jdp` you created during installation, run `Pkg.rm("DeclarativePackages")` and delete all packages installed by `jdp`:

```
chmod -R +w $HOME/.julia/declarative && rm -rf $HOME/.julia/declarative
```

## How does it work?

Normally, Julia has a global, mutable state of installed packages in `$HOME/.julia/v0.x`.

`jdp`, in contrast, installs the packages for each unique `DECLARE` file in a distinct location, marks the installation read-only, and calls Julia with a modified `JULIA_PKGDIR`. Like this, Julia sees only the packages specified in `DECLARE`. And different projects and even different branches within a project can easily specify which package versions (or commits) to use.

The packages are actually installed in `$HOME/.julia/declarative/HASH/v0.x`, where `HASH` is the md5 hash over the contents of the `DECLARE` file.

In addition to `JULIA_PKGDIR` Julia's `LOAD_PATH` is set to include the `src`, `modules` and `submodules` subdirectories of where `jdp` was invoked. The first is handy when working on a module while the second or third are a great places to put any git submodules.

Hard links are used for packages at the same commit, resuling in very little disc space used in `$HOME/.julia/declarative`. You can delete that directory without ill-effect at any time, `jdp` will re-install packages as needed on the next invokation.

## Open issues

* `jdp` was tested on Linux and OSX - help adapting it to Windows would be much appreciated!

