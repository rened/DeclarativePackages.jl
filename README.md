z# Per-project, declarative Julia package installations

**DeclarativePackages.jl**, or `jdp` for short, allows to declaratively specify which Julia packages a project should use, with exact version or commit details.

`jdp` will install the specified packages (if necessary) and start 'julia' with exactly these packages available. 

`jdp` is heavily inspired by the [nix package manager](http://nixos.org/nix/).

## Installation

You need to have `git` installed. Install the package and link `jdp` to a directly on your `PATH`:

```jl
Pkg.add('DeclarativePackages') 
symlink(Pkg.dir("DeclarativePackages")*"/bin/jdp",  "~/local/bin/jdp")
```

## Usage

Simply create a `DECLARE` file in your project's directory and run `jdp` in that directory instead of `julia`. 

The syntax is very similar to Julia's `REQUIRE` files, and you can simply copy your `~/.julia/v0.x/REQUIRE` to `./DECLARE` to start off with your currently installed packages.

Example for a `DECLARE` file:
```
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
DECLARE=mydeclarations.txt JULIA=/usr/bin/juliafromgit jdp -e "println(123")
```
If you would like to start with `DECLARE` based on your currently installed packages, run:

```bash
julia -e "using DeclarativePackages; exportDECLARE()"
```
Finally, `git add DECLARE` and track the set of installed packages along with your code!

### How to update packages

You will see that your `DECLARE` files get auto-updated if not all packages are specified. Also `METADATA` (where Julia gets the information about available packages from) is listed and fixed at a commit.

There are several ways to update a package by editing `DECLARE`:

* You can change the version number or commit hash.
* You can remove the package and have `jdp` update it to the version `Pkg.add()` would pick.
* As long as `DECLARE` contains a line fixing `METADATA` to a specific commit packages can only be updated using the versions listed therein.
* You can use `METADATA` corresponding to a different commit hash (simply change it), or delete the line containing `METADATA` to pull in the newest `METADATA`. 
* You can keep a second declaration file, e.g. `DECLARE.minimal`, containing only the minumum you want to specify:
```
HDF5
```
Running `cp DECLARE.minimal DECLARE; jdp` will then update everything to the newest versions, which is usefull during development. As you have `DECLARE` in your `git` repo you can always go back.

## Uninstall

Remove the symlink to `jdp` you created, run `Pkg.rm("DeclarativePackages")` and delete all packages installed by `jdp`:

```
chmod -R +w $HOME/.julia/declarative && rm -rf $HOME/.julia/declarative
```

## How does it work?

Normally, Julia has a global, mutable state of installed packages in `$HOME/.julia/v0.x`.

`jdp`, in contrast, installs the packages for each unique `DECLARE` file in a distinct location, marks the installation read-only, and calls Julia with a modified `JULIA_PKGDIR`. Like this, Julia sees only the packages specified in `DECLARE`. And different projects and even different branches within a project can easily specify which package versions (or commits) to use.

The packages are actually installed in `$HOME/.julia/declarative/HASH/v0.x`, where `HASH` is the md5 hash over the contents of the `DECLARE` file.

In addition to `JULIA_PKGDIR` the `JULIA_LOAD_PATH` is set to point to the `submodules` subdirectory of where `jdp` was invoked. This is thus a great place to put any git submodules.

While cruft will accumulate over time in `$HOME/.julia/declarative`, the few MBs of disc space are a very cheap resource compared to programmer time and nerves. And, you can still simply delete that directory from time to time if you want to.

