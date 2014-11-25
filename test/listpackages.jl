pkgs = Pkg.installed(); 
map(k -> println(k, ' ', pkgs[k]), sort(collect(keys(pkgs))))
