using DirWalker
using Test

@testset "DirWalker (Fidelity)" begin
    @test length(detect_ambiguities(DirWalker)) == 0
end

# Build a fixture tree under `root` and return it.
function make_fixture(root)
	mkpath(joinpath(root, "sub1"))
	mkpath(joinpath(root, "sub2", "nested"))
	mkpath(joinpath(root, ".git"))
	mkpath(joinpath(root, "onlydirs", "deeper"))   # a directory with no files, only a sub-directory
	mkpath(joinpath(root, "empty"))                # an empty directory
	write(joinpath(root, "a.txt"), "a")
	write(joinpath(root, "B.md"), "b")
	write(joinpath(root, "sub1", "c.txt"), "c")
	write(joinpath(root, "sub2", "d.txt"), "d")
	write(joinpath(root, "sub2", "nested", "e.txt"), "e")
	write(joinpath(root, "onlydirs", "deeper", "f.txt"), "f")
	write(joinpath(root, ".git", "config"), "git")
	return root
end

# A callable object usable as a sort key.
struct ByLength end
(::ByLength)(s) = length(s)

# Paths relative to `root`, with "/" separators.
rel(root, fs) = [replace(relpath(f, root), Base.Filesystem.path_separator => "/") for f in fs]

@testset "DirWalker (Count files)" begin
	mktempdir() do root
		make_fixture(root)

		# Create a directory iterator -- using the struct, DirItr.
		d = DirItr(root; dprune=[raw"^\.git$"], by_depth=true, ordered=true)

		# Iterate over all files within the directory sub-tree.
		collected = String[]
		for f in d
			push!(collected, f)
		end

		# Should find exactly 6 files -- .git is pruned, and files below a directory
		# that has only sub-directories are found.
		@test length(collected) == 6
		@test sort(rel(root, collected)) == ["B.md", "a.txt", "onlydirs/deeper/f.txt", "sub1/c.txt", "sub2/d.txt", "sub2/nested/e.txt"]
		@test !any(f -> contains(f, ".git"), collected)
		@test eltype(d) == String
		@test eltype(typeof(d)) == String
		@test collect(d) == collected

		# Default keyword values give the same result.
		@test collect(DirItr(root)) == collected

		# The same tree matches what `walkdir` finds.
		wd = String[]
		for (dir, _, files) in walkdir(root)
			contains(dir, ".git") && continue
			append!(wd, joinpath.(dir, files))
		end
		@test sort(collected) == sort(wd)
	end
end

@testset "DirWalker (Order)" begin
	mktempdir() do root
		make_fixture(root)

		# Depth first, ascending: the root's files first (case-insensitive order), then each sub-tree in full.
		fs = rel(root, collect(DirItr(root; by_depth=true, order_dir=:asc)))
		@test fs == ["a.txt", "B.md", "onlydirs/deeper/f.txt", "sub1/c.txt", "sub2/d.txt", "sub2/nested/e.txt"]

		# Depth first, descending.
		fs = rel(root, collect(DirItr(root; by_depth=true, order_dir=:desc)))
		@test fs == ["B.md", "a.txt", "sub2/d.txt", "sub2/nested/e.txt", "sub1/c.txt", "onlydirs/deeper/f.txt"]

		# Breadth first, ascending: all files at one level before the next level.
		fs = rel(root, collect(DirItr(root; by_depth=false, order_dir=:asc)))
		@test fs == ["a.txt", "B.md", "sub1/c.txt", "sub2/d.txt", "onlydirs/deeper/f.txt", "sub2/nested/e.txt"]

		# A different sort key (case sensitive).
		fs = rel(root, collect(DirItr(root; order_by=identity)))
		@test fs[1:2] == ["B.md", "a.txt"]

		# A callable object is accepted as the sort key.
		fs = rel(root, collect(DirItr(root; order_by=ByLength())))
		@test length(fs) == 6

		# Unordered: same set of files.
		fs = collect(DirItr(root; ordered=false))
		@test sort(rel(root, fs)) == sort(rel(root, collect(DirItr(root))))
	end
end

@testset "DirWalker (Prune)" begin
	mktempdir() do root
		make_fixture(root)

		# Prune files by name.
		fs = rel(root, collect(DirItr(root; fprune=[raw"\.md$"])))
		@test fs == ["a.txt", "onlydirs/deeper/f.txt", "sub1/c.txt", "sub2/d.txt", "sub2/nested/e.txt"]

		# Prune directories by name -- everything below them goes too.
		fs = rel(root, collect(DirItr(root; dprune=[raw"^\.git$", raw"^sub2$"])))
		@test fs == ["a.txt", "B.md", "onlydirs/deeper/f.txt", "sub1/c.txt"]

		# Empty prune vectors prune nothing (so .git is walked).
		fs = rel(root, collect(DirItr(root; dprune=String[], fprune=String[])))
		@test ".git/config" in fs && length(fs) == 7

		# Patterns match the entry name only, not the full path.
		fs = rel(root, collect(DirItr(root; dprune=[raw"^\.git$", "nested"])))
		@test !("sub2/nested/e.txt" in fs) && "sub2/d.txt" in fs
	end
end

@testset "DirWalker (Edge cases)" begin
	mktempdir() do root
		# An empty directory yields nothing.
		@test collect(DirItr(root)) == String[]
		@test iterate(DirItr(root)) === nothing

		# A tree with only sub-directories and a single deep file.
		mkpath(joinpath(root, "a", "b"))
		write(joinpath(root, "a", "b", "deep.txt"), "x")
		@test rel(root, collect(DirItr(root))) == ["a/b/deep.txt"]
		@test rel(root, collect(DirItr(root; by_depth=false))) == ["a/b/deep.txt"]

		# Invalid arguments.
		@test_throws ArgumentError DirItr(root; order_dir=:sideways)
		@test_throws ArgumentError DirItr(joinpath(root, "does-not-exist"))

		# Compact and verbose show.
		d = DirItr(root)
		@test repr(d) == "DirItr($(repr(root)))"
		@test occursin("by_depth", repr("text/plain", d))
	end
end

if !Sys.iswindows()
	@testset "DirWalker (Symlinks)" begin
		mktempdir() do root
			mkpath(joinpath(root, "real"))
			write(joinpath(root, "real", "r.txt"), "r")
			write(joinpath(root, "f.txt"), "f")
			symlink(root, joinpath(root, "loop"))                       # a cycle
			symlink(joinpath(root, "real"), joinpath(root, "reallink"))  # a link to a sibling

			# Not following links: links are yielded as entries, never descended.
			fs = rel(root, collect(DirItr(root)))
			@test fs == ["f.txt", "loop", "reallink", "real/r.txt"]

			# Following links: each real directory visited once, so the cycle terminates.
			fs = rel(root, collect(DirItr(root; follow_symlinks=true)))
			@test fs == ["f.txt", "real/r.txt"]
		end
	end

	@testset "DirWalker (Unreadable directory)" begin
		mktempdir() do root
			mkpath(joinpath(root, "locked"))
			write(joinpath(root, "locked", "hidden.txt"), "h")
			write(joinpath(root, "ok.txt"), "ok")
			chmod(joinpath(root, "locked"), 0o000)
			try
				if Sys.isunix() && ccall(:geteuid, Cuint, ()) != 0  # root can read anything
					@test_throws Base.IOError collect(DirItr(root))
					errs = Any[]
					fs = rel(root, collect(DirItr(root; onerror=e -> push!(errs, e))))
					@test fs == ["ok.txt"] && length(errs) == 1 && errs[1] isa Base.IOError
				end
			finally
				chmod(joinpath(root, "locked"), 0o755)
			end
		end
	end
end
