using DirWalker
import Pkg

Pkg.add("Documenter")
using Documenter

makedocs(
	sitename = "DirWalker",
	format = Documenter.HTML(),
	modules = [DirWalker]
	)

	# Documenter can also automatically deploy documentation to gh-pages.
	# See "Hosting Documentation" and deploydocs() in the Documenter manual
	# for more information.
	deploydocs(
		repo = "github.com/scottrsm/DirWalker.jl.git"
	)
