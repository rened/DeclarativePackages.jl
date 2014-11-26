exists(filename::String) = (s = stat(filename); s.inode!=0)
if exists(Pkg.dir("METADATA"))
	pkgs = Pkg.installed(); 
	map(k -> println(k, ' ', pkgs[k]), sort(collect(keys(pkgs))))
end
